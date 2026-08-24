# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Record::Model`, the record base class: CRUD and
# finders, validations, auto-timestamps and callbacks, all driven by column
# metadata read at compile time from the `META` constant a generated
# `db/schema.cr` defines. Attributes and finder arguments are typed by the
# schema, so a wrong column or type is a compile error, not a runtime 500.
module Altair
  module Record
    # Raised by `find!` and the `find_by_*!` finders when no record matches.
    class RecordNotFound < Altair::Error
      def initialize(message : String)
        super(message)
      end
    end

    # Raised by `save!` when validations fail; carries the invalid record.
    class RecordInvalid < Altair::Error
      # The record that failed validation.
      getter record : Model

      def initialize(record : Model)
        @record = record
        super("Validation failed: #{record.errors.full_messages.join(", ")}")
      end
    end

    # The runtime registry backing polymorphic associations: every model
    # registers itself here when defined, so `<name>_type` columns resolve
    # to classes without compile-time enumeration.
    def self.polymorphic_klasses : Hash(String, Model.class)
      REGISTRY
    end

    def self.resolve_klass(type : String) : Model.class
      klass = REGISTRY[type]?
      raise Altair::Error.new(
        "Unknown polymorphic type: #{type} — is it an Altair::Record::Model?"
      ) unless klass
      klass
    end

    REGISTRY = {} of String => Model.class

    # The base class of every record. Subclass it and declare the backing
    # table; the attributes, finders and pluckers follow:
    #
    # ```
    # class Post < Altair::Record::Model
    #   table :posts
    # end
    #
    # Post.create(title: "Hello")
    # Post.find_by_title("Hello")
    # ```
    class Model
      # The union of every value an attribute can hold.
      alias Value = Int32 | Int64 | String | Float64 | Bool | Time? | JSON::Any? | BigDecimal?

      # The Crystal type name for each logical column type.
      CRYSTAL_TYPE = {
        :string   => "String",
        :text     => "String",
        :integer  => "Int32",
        :bigint   => "Int64",
        :float    => "Float64",
        :decimal  => "BigDecimal",
        :boolean  => "Bool",
        :datetime => "Time",
        :json     => "JSON::Any",
      }

      # The default value expression for each logical column type.
      DEFAULT_FOR = {
        :string   => "\"\"",
        :text     => "\"\"",
        :integer  => "0",
        :bigint   => "0_i64",
        :float    => "0.0",
        :decimal  => "BigDecimal.new(\"0\")",
        :boolean  => "false",
        :datetime => "Time.utc(1970, 1, 1)",
        :json     => "JSON::Any.new(\"null\")",
      }

      # Sentinel marking an argument the caller did not pass.
      struct Unset
      end

      # The bind-parameter ceiling a single bulk statement stays under,
      # whatever the adapter's real limit is (SQLite historically 999,
      # PostgreSQL 65535).
      INSERT_ALL_MAX_BINDS = 900

      # The bind-parameter ceiling for preload `IN (...)` clauses. The
      # loaders split oversized id lists into consecutive queries and
      # concatenate the rows, so eager loading never trips the driver's
      # variable limit on large collections.
      PRELOAD_MAX_BINDS = 500

      # Yields each chunk of `ids` sized to stay under
      # `PRELOAD_MAX_BINDS` bind parameters. Accepts any numeric id array
      # (Int32/Int64 primary keys) and yields as bind-compatible values.
      def self.each_preload_chunk(ids : Enumerable(Int64 | Int32), & : Array(Model::Value) -> Nil) : Nil
        ids.each_slice(PRELOAD_MAX_BINDS) do |chunk|
          yield chunk.map(&.as(Model::Value))
        end
      end

      # The validation errors of a record, keyed by attribute.
      class Errors
        # The messages per attribute.
        getter messages : Hash(Symbol, Array(String)) = {} of Symbol => Array(String)

        # Adds a message for the attribute.
        def add(attribute : Symbol, message : String) : Nil
          (@messages[attribute] ||= [] of String) << message
        end

        # Removes all messages.
        def clear : Nil
          @messages.clear
        end

        # Whether there are no errors.
        def empty? : Bool
          @messages.empty?
        end

        # The messages for an attribute, empty when there are none.
        def [](attribute : Symbol) : Array(String)
          @messages[attribute]? || [] of String
        end

        # The messages prefixed with the attribute name:
        # `["title can't be blank"]`.
        def full_messages : Array(String)
          @messages.flat_map { |attribute, list| list.map { |message| "#{attribute} #{message}" } }
        end
      end

      # One declared validation rule.
      struct Rule
        # The rule kind: `:presence`, `:length`, `:numericality`,
        # `:uniqueness` or `:custom`.
        getter kind : Symbol

        # The attribute the rule checks (`nil` for custom-method rules).
        getter attribute : Symbol?

        # The method a `:custom` rule runs.
        getter method : Symbol?

        # The `minimum` option of a `:length` rule.
        getter minimum : Int32?

        # The `maximum` option of a `:length` rule.
        getter maximum : Int32?

        # The `greater_than` option of a `:numericality` rule.
        getter greater_than : Float64?

        # The `integer` option of a `:numericality` rule.
        getter integer : Bool?

        # The `scope` option of a `:uniqueness` rule.
        getter scope : Symbol?

        # The allowed values (`Array` or `Range`) of an `:inclusion` /
        # `:exclusion` rule.
        getter possibilities : (Array(String) | Range(Int32, Int32))?

        # The pattern a `:format` rule must match.
        getter format : Regex?

        # A custom message replacing the default one.
        getter message : String?

        # The predicate method an `if:` option names — the rule runs only
        # while it returns true.
        getter if_method : Symbol?

        # The predicate method an `unless:` option names — the rule is
        # skipped while it returns true.
        getter unless_method : Symbol?

        # Whether a nil attribute value skips this rule.
        getter? allow_nil : Bool

        # Whether uniqueness compares case-sensitively; `false` folds both
        # sides through LOWER before matching.
        getter? case_sensitive : Bool

        def initialize(@kind : Symbol, @attribute : Symbol? = nil, @method : Symbol? = nil,
                       @minimum : Int32? = nil, @maximum : Int32? = nil,
                       @greater_than : Float64? = nil, @integer : Bool? = nil,
                       @scope : Symbol? = nil, @message : String? = nil,
                       @possibilities : (Array(String) | Range(Int32, Int32))? = nil,
                       @format : Regex? = nil,
                       @if_method : Symbol? = nil, @unless_method : Symbol? = nil,
                       @allow_nil : Bool = false, @case_sensitive : Bool = true)
        end
      end

      # The set of attributes changed since the last load or save. Consumed
      # by `update_row` so a save only writes the columns that actually
      # changed.
      @dirty : Set(Symbol) = Set(Symbol).new

      # The attribute values as of the last load or save — the baseline
      # `restore_attributes` reverts to.
      @originals : Hash(Symbol, Value) = {} of Symbol => Value

      # Whether any attribute changed since the last load or save.
      def changed? : Bool
        !@dirty.empty?
      end

      # The primary key normalized to Int64 — the polymorphic loaders'
      # type-safe handle, since the base class carries no `id` column of
      # its own. Overridden by the `table` macro.
      def __pk : Int64?
        nil
      end

      # The changed attributes, sorted by name.
      def changed_attributes : Array(Symbol)
        @dirty.to_a.sort
      end

      # Whether the given attribute changed since the last load or save.
      def attribute_changed?(name : Symbol) : Bool
        @dirty.includes?(name)
      end

      # Reverts attributes to their values at the last load or save. With
      # no names, every changed attribute is restored. A record that has
      # never been persisted has no baseline, so restoring an attribute it
      # only ever held in memory leaves that value untouched.
      def restore_attributes(*names : Symbol) : Nil
        restore_columns(names.to_a.sort)
      end

      # Reverts every changed attribute to its last loaded or saved value.
      def restore_attributes : Nil
        restore_columns(changed_attributes)
      end

      private def restore_columns(targets : Array(Symbol)) : Nil
        targets.each do |name|
          unless self.class.column_names.includes?(name.to_s)
            raise ArgumentError.new("Unknown column :#{name} for #{self.class.table_name}")
          end
          next unless @originals.has_key?(name)
          restore_column_value(name, @originals[name])
          @dirty.delete(name)
        end
      end

      # The errors of this record, populated by `valid?`.
      getter errors : Errors = Errors.new

      # The table backing this model. Overridden by the `table` macro.
      def self.table_name : String
        raise Altair::Error.new("#{self} has no table — declare one with `table :name`")
      end

      # The eager loader for an association, or a clear error. The
      # signature is uniform across every model so nested include specs
      # can dispatch through a record's metaclass at runtime.
      def self.__preloader_for(name : Symbol) : Proc(Array(Altair::Record::Model), Array(Altair::Record::Model))
        raise ArgumentError.new("Unknown association :#{name} for #{self}")
      end

      # The model's columns in schema order. Overridden by the `table` macro.
      def self.column_names : Array(String)
        raise Altair::Error.new("#{self} has no columns — declare a table with `table :name`")
      end

      # The timestamp columns present in the schema. Overridden by the
      # `table` macro.
      def self.timestamp_columns : Array(Symbol)
        [] of Symbol
      end

      # Builds a record from a result-set row. Overridden by the `table`
      # macro.
      def self.from_row(rs : DB::ResultSet) : self
        raise Altair::Error.new("#{self} has no schema — declare a table with `table :name`")
      end

      # Declares the table backing this model and generates the typed
      # attributes, finders and pluckers from its schema columns:
      #
      # ```
      # class Post < Altair::Record::Model
      #   table :posts
      # end
      # ```
      #
      # The column metadata comes from the `META` constant of a generated
      # `db/schema.cr`, which must be required before the model file.
      macro table(name, primary_key = "id")
        {% unless Altair::Record::Schema::META.keys.any? { |key| key.stringify == name.id.stringify } %}
          {% raise "Unknown table :#{name.id} — db/schema.cr defines: #{Altair::Record::Schema::META.keys.map(&.id).join(", ")}. Run the migrations to regenerate it." %}
        {% end %}

        {% columns = Altair::Record::Schema::META[name] %}

        {% select_columns = columns.map { |col_name, _| "\"#{col_name.id}\"" }.join(", ") %}
        {% select_sql_literal = "SELECT " + select_columns + " FROM \"" + name.id.stringify + "\"" %}

        {% pk_name = primary_key.id %}
        {% pk_type = :integer %}
        {% for col_name, col in columns %}
          {% if col[:primary] || col_name.id == pk_name %}
            {% pk_type = col[:type] %}
          {% end %}
        {% end %}
        PRIMARY_KEY_NAME = {{ pk_name.stringify }}

        # The primary key; `nil` until the record is saved.
        @id : {{ CRYSTAL_TYPE[pk_type].id }}? = nil

        # Normalized primary key for polymorphic grouping. String PKs
        # (e.g. UUID) hash to a stable numeric via their bytes.
        def __pk : Int64
          value = @{{ pk_name.id }}
          case value
          when Int32 then value.to_i64
          when Int64 then value
          when String then value.bytes.sum { |byte| byte.to_i64 * 31 }
          else 0_i64
          end
        end

        # Re-reads this record's attributes from the database.
        def reload : self
          raise Altair::Error.new("Cannot reload an unpersisted record") if @{{ pk_name.id }}.nil?
          fresh = self.class.find!(@{{ pk_name.id }}.not_nil!)
          {% for col_name, _ in columns %}
            @{{ col_name.id }} = fresh.{{ col_name.id }}
          {% end %}
          clear_dirty
          self
        end

        # Whether the primary key auto-generates (numeric AUTOINCREMENT).
        # String PKs (UUID) are assigned before insert instead.
        def self.auto_pk? : Bool
          {{ pk_type != :string }}
        end

        TABLE_NAME = {{ name.id.stringify }}

        def self.table_name : String
          "{{ name.id }}"
        end

        def self.column_names : Array(String)
          [{% for col_name, col in columns %}"{{ col_name.id }}", {% end %}]
        end

        def self.primary_key_name : String
          {{ pk_name.stringify }}
        end

        def self.timestamp_columns : Array(Symbol)
          [:created_at, :updated_at].select { |column| column_names.includes?(column.to_s) }
        end

        # The logical column type of every non-primary-key column, keyed by
        # column name. Bulk paths (`insert_all`) resolve types through this
        # at runtime, since their row shapes are caller-supplied.
        def self.column_types : Hash(Symbol, Symbol)
          {
            {% for col_name, col in columns %}
              {% unless col[:primary] %}
                {{ col_name }}: :{{ col[:type].id }},
              {% end %}
            {% end %}
          }.to_h
        end

        # The `SELECT` prefix over every column, in schema order — expanded
        # at compile time so a query never allocates the prefix. Identifiers
        # are double-quoted, which both shipped adapters emit the same way.
        def self.select_sql : String
          {{ select_sql_literal }}
        end

        {% for col_name, col in columns %}
          {% type = col[:type] %}
          {% primary = col[:primary] %}
          {% nullable = primary || col[:null] %}
          {% unless CRYSTAL_TYPE.has_key?(type) %}
            {% raise "Column :#{col_name.id} of :#{name.id} has unsupported type :#{type.id}" %}
          {% end %}

          {% unless primary %}
            @{{ col_name.id }} : {{ CRYSTAL_TYPE[type].id }}{% if nullable %}?{% end %} = {% if nullable %}nil{% else %}{{ DEFAULT_FOR[type].id }}{% end %}
          {% end %}

          def {{ col_name.id }} : {{ CRYSTAL_TYPE[type].id }}{% if nullable %}?{% end %}
            @{{ col_name.id }}
          end

          def {{ col_name.id }}=(value : {{ CRYSTAL_TYPE[type].id }}{% if nullable %}?{% end %}) : Nil
            {% unless primary %}
              @dirty << :{{ col_name.id }}
            {% end %}
            @{{ col_name.id }} = value
          end
        {% end %}

        def initialize(
          {% for col_name, col in columns %}
            {{ col_name.id }} : {{ CRYSTAL_TYPE[col[:type]].id }}{% if col[:primary] || col[:null] %}?{% end %} = {% if col[:primary] || col[:null] %}nil{% else %}{{ DEFAULT_FOR[col[:type]].id }}{% end %},
          {% end %}
        ) : Nil
          {% for col_name, col in columns %}
            @{{ col_name.id }} = {{ col_name.id }}
          {% end %}
        end

        # Creates and saves a record with the given attributes, returning
        # it even when validations fail.
        def self.create(
          {% for col_name, col in columns %}
            {% unless col[:primary] %}
              {{ col_name.id }} : {{ CRYSTAL_TYPE[col[:type]].id }}{% if col[:null] %}?{% end %} = {% if col[:null] %}nil{% else %}{{ DEFAULT_FOR[col[:type]].id }}{% end %},
            {% end %}
          {% end %}
        ) : self
          record = new(
            {% for col_name, col in columns %}
              {% unless col[:primary] %}{{ col_name.id }}: {{ col_name.id }}, {% end %}
            {% end %}
          )
          record.save
          record
        end

        # Updates the given attributes and saves. Attributes that are not
        # passed keep their current values.
        def update(
          {% for col_name, col in columns %}
            {% unless col[:primary] %}
              {{ col_name.id }} : {{ CRYSTAL_TYPE[col[:type]].id }}{% if col[:null] %}?{% end %} | Unset = Unset.new,
            {% end %}
          {% end %}
        ) : Bool
          {% for col_name, col in columns %}
            {% unless col[:primary] %}
              if !{{ col_name.id }}.is_a?(Unset)
                self.{{ col_name.id }} = {{ col_name.id }}
              end
            {% end %}
          {% end %}
          save
        end

        def self.from_row(rs : DB::ResultSet) : self
          record = new
          {% for col_name, col in columns %}
            {% type = col[:type] %}
            {% nullable = col[:primary] || col[:null] %}
            {% read_type = CRYSTAL_TYPE[type].id %}
            {% if type == :json %}
              value = connection.adapter.read_json(rs)
              record.{{ col_name.id }} = {% if nullable %}value{% else %}value.not_nil!{% end %}
            {% elsif type == :decimal %}
              value = connection.adapter.read_decimal(rs)
              record.{{ col_name.id }} = {% if nullable %}value{% else %}value.not_nil!{% end %}
            {% else %}
              record.{{ col_name.id }} = rs.read({{ read_type.id }}{% if nullable %}?{% end %})
            {% end %}
          {% end %}
          record.clear_dirty
          record
        end

        {% for col_name, col in columns %}
          {% type = col[:type] %}
          {% nullable = col[:primary] || col[:null] %}
          {% read_type = CRYSTAL_TYPE[type].id %}

          # Finds the record whose {{ col_name.id }} column equals the
          # value, or `nil`.
          def self.find_by_{{ col_name.id }}(value : {{ CRYSTAL_TYPE[type].id }}{% if nullable %}?{% end %}) : self?
            {% if nullable %}
              if value.nil?
                connection.query_one(
                  connection.sql_template("{{ @type.id }}#find_by_{{ col_name.id }}_null") {
                    "#{select_sql} WHERE #{connection.adapter.quote_identifier("{{ col_name.id }}")} IS NULL LIMIT 1"
                  }
                ) { |rs| from_row(rs) }
              else
                connection.query_one(
                  connection.sql_template("{{ @type.id }}#find_by_{{ col_name.id }}_value") {
                    "#{select_sql} WHERE #{connection.adapter.quote_identifier("{{ col_name.id }}")} = #{connection.adapter.placeholder(0)} LIMIT 1"
                  }, value
                ) { |rs| from_row(rs) }
              end
            {% else %}
              connection.query_one(
                connection.sql_template("{{ @type.id }}#find_by_{{ col_name.id }}") {
                  "#{select_sql} WHERE #{connection.adapter.quote_identifier("{{ col_name.id }}")} = #{connection.adapter.placeholder(0)} LIMIT 1"
                }, value
              ) { |rs| from_row(rs) }
            {% end %}
          rescue DB::NoResultsError
            nil
          end

          # Finds the record whose {{ col_name.id }} column equals the
          # value, raising `RecordNotFound` when there is none.
          def self.find_by_{{ col_name.id }}!(value : {{ CRYSTAL_TYPE[type].id }}{% if nullable %}?{% end %}) : self
            find_by_{{ col_name.id }}(value) || raise Altair::Record::RecordNotFound.new(
              "Couldn't find #{table_name} with {{ col_name.id }}=#{value.inspect}"
            )
          end
        {% end %}

        # Finds the record with the given id, or `nil`. The statement is a
        # cached template — the base implementation rebuilds the WHERE
        # clause on every call.
        def self.find(id : Int32 | Int64) : self?
          connection.query_one(
            connection.sql_template("{{ @type.id }}#find_pk") {
              "#{select_sql} WHERE #{connection.adapter.quote_identifier("{{ pk_name.id }}")} = #{connection.adapter.placeholder(0)} LIMIT 1"
            }, id
          ) { |rs| from_row(rs) }
        rescue DB::NoResultsError
          nil
        end

        # The values of a column, in row order. Raises on a column the
        # table does not have.
        def self.pluck(column : Symbol) : Array(Value)
          case column
          {% for col_name, col in columns %}
            {% read_type = CRYSTAL_TYPE[col[:type]].id %}
            when :{{ col_name.id }}
              values = [] of Value
              connection.query(
                "SELECT #{connection.adapter.quote_identifier("{{ col_name.id }}")} " \
                "FROM #{connection.adapter.quote_identifier(table_name)}"
              ) do |rs|
                rs.each { values << rs.read({{ read_type.id }}{% if col[:primary] || col[:null] %}?{% end %}) }
              end
              values
          {% end %}
          else
            raise ArgumentError.new("Unknown column :#{column} for #{table_name}")
          end
        end

        # The value of an attribute, for validation checks.
        private def attribute_value(attribute : Symbol) : Value
          case attribute
          {% for col_name, col in columns %}
          when :{{ col_name.id }}
            @{{ col_name.id }}
          {% end %}
          else
            raise ArgumentError.new("Unknown attribute :#{attribute}")
          end
        end

        # Inserts many rows in as few statements as possible and returns
        # the number of rows inserted. This is the bulk load path: it
        # bypasses validations, callbacks and dirty tracking, and binds
        # every value as a parameter. Rows may carry any subset of the
        # table's columns; keys missing from a row bind as `NULL`, while
        # timestamp columns absent from every row auto-fill like `create`
        # (one `Time.utc` shared by the whole call). A set too large for
        # one statement's bind limit is chunked inside a single
        # transaction, so the call stays all-or-nothing.
        #
        # ```
        # Post.insert_all([{title: "a", views: 1}, {title: "b", views: 2}])
        # ```
        def self.insert_all(rows : Enumerable(NamedTuple)) : Int64
          normalized = normalize_insert_rows(rows)
          return 0_i64 if normalized.empty?

          columns = [] of Symbol
          normalized.each do |attrs|
            attrs.each_key { |key| columns << key unless columns.includes?(key) }
          end

          chunk_size = {INSERT_ALL_MAX_BINDS // columns.size, 1}.max
          total = 0_i64
          execute = ->(chunk : Array(Hash(Symbol, Value))) do
            args = [] of Value
            chunk.each do |attrs|
              columns.each do |column|
                args << connection.adapter.encode_column(attrs[column]?, column_types[column])
              end
            end
            result = connection.exec(insert_all_sql(columns, chunk.size), args: args)
            result.rows_affected.to_i64
          end

          if normalized.size <= chunk_size
            total += execute.call(normalized)
          else
            connection.transaction do
              normalized.each_slice(chunk_size) do |chunk|
                total += execute.call(chunk)
              end
            end
          end
          total
        end

        # Validates and flattens caller-supplied rows: unknown columns and
        # primary-key keys raise, values must be storable types, and
        # missing timestamps fill with a single shared `Time.utc`.
        private def self.normalize_insert_rows(rows : Enumerable(NamedTuple)) : Array(Hash(Symbol, Value))
          stamps = timestamp_columns
          fill = stamps.empty? ? nil : Time.utc
          rows.map do |row|
            attrs = {} of Symbol => Value
            row.to_a.each do |pair|
              key = pair[0]
              if key == :{{ pk_name }}
                raise ArgumentError.new("insert_all does not set #{key} — primary keys are assigned by the database")
              end
              unless column_types.has_key?(key)
                raise ArgumentError.new("Unknown column :#{key} for #{table_name} (columns: #{column_types.keys.join(", ")})")
              end
              value = pair[1]
              unless value.is_a?(Value)
                raise ArgumentError.new("Unsupported value type #{value.class} for #{table_name}.#{key}")
              end
              attrs[key] = value.as(Value)
            end
            stamps.each do |stamp|
              next if attrs.has_key?(stamp)
              attrs[stamp] = fill.not_nil!
            end
            attrs
          end
        end

        # The cached multi-row INSERT for a given column set and row
        # count — bulk loads of a steady shape reuse one compiled string.
        # The column list is passed in so the placeholders always pair
        # with the values exactly as the caller bound them.
        private def self.insert_all_sql(columns : Array(Symbol), row_count : Int32) : String
          connection.sql_template("{{ @type.id }}#insert_all_#{columns.join("_")}_#{row_count}") do
            quoted = columns.map { |column| connection.adapter.quote_identifier(column.to_s) }
            row_groups = row_count.times.map do |row_index|
              "(#{columns.size.times.map { |col_index| connection.adapter.placeholder(row_index * columns.size + col_index) }.join(", ")})"
            end
            "INSERT INTO #{connection.adapter.quote_identifier(table_name)} " \
            "(#{quoted.join(", ")}) VALUES #{row_groups.join(", ")}"
          end
        end

        private def insert : Nil
          conn = connection
          {% if pk_type == :string %}
            unless @{{ pk_name.id }}
              @{{ pk_name.id }} = Random::Secure.uuid
            end
          {% end %}
          {% args = [] of String %}
          {% for col_name, col in columns %}
            {% unless col[:primary] && pk_type != :string %}
              {% args << "connection.adapter.encode_column(@#{col_name.id}, :#{col[:type].id})" %}
            {% end %}
          {% end %}
          {% if pk_type == :string %}
            conn.exec(self.class.insert_sql(false), {{ args.join(", ").id }})
          {% else %}
            if conn.adapter.supports_returning?(:insert)
              conn.query_one(
                self.class.insert_sql(true),
                {{ args.join(", ").id }}
              ) { |rs| @{{ pk_name.id }} = rs.read({{ CRYSTAL_TYPE[pk_type].id }}) }
            else
              result = conn.exec(
                self.class.insert_sql(false),
                {{ args.join(", ").id }}
              )
              @{{ pk_name.id }} = {% if pk_type == :bigint %}conn.last_insert_id(result){% else %}conn.last_insert_id(result).to_i32{% end %}
            end
          {% end %}
        end

        # The cached INSERT statement. `returning` selects the variant that
        # appends `RETURNING` for the primary key. Building the statement
        # once per connection keeps the write path off a dozen small string
        # allocations per insert. The build block must not call another
        # `sql_template` — template locks are not reentrant.
        def self.insert_sql(returning : Bool) : String
          if returning
            connection.sql_template("{{ @type.id }}#insert_returning") do
              build_insert_sql + " RETURNING #{connection.adapter.quote_identifier("{{ pk_name.id }}")}"
            end
          else
            connection.sql_template("{{ @type.id }}#insert") { build_insert_sql }
          end
        end

        private def self.build_insert_sql : String
          columns = column_names.reject { |column| column == primary_key_name }
          quoted = columns.map { |column| connection.adapter.quote_identifier(column) }
          placeholders = columns.each_index.map { |index| connection.adapter.placeholder(index) }
          "INSERT INTO #{connection.adapter.quote_identifier(table_name)} " \
          "(#{quoted.join(", ")}) VALUES (#{placeholders.join(", ")})"
        end

        protected def clear_dirty : Nil
          @dirty.clear
          @originals.clear
          {% for col_name, col in columns %}
            @originals[:{{ col_name.id }}] = @{{ col_name.id }}
          {% end %}
        end

        # Writes a restored baseline value back into its typed attribute.
        private def restore_column_value(name : Symbol, value : Value) : Nil
          case name
            {% for col_name, col in columns %}
            when :{{ col_name.id }}
              @{{ col_name.id }} = value.as({{ CRYSTAL_TYPE[col[:type]].id }}{% if col[:primary] || col[:null] %}?{% end %})
            {% end %}
          else
            raise ArgumentError.new("Unknown column :#{name} for #{self.class.table_name}")
          end
        end

        private def update_row : Nil
          conn = connection
          columns = @dirty.to_a
          return if columns.empty?
          set = columns.map_with_index do |column, index|
            "#{conn.adapter.quote_identifier(column.to_s)} = #{conn.adapter.placeholder(index)}"
          end
          args = columns.map { |column| bind_attribute(column) } + [@id]
          conn.exec(
            "UPDATE #{conn.adapter.quote_identifier(self.class.table_name)} " \
            "SET #{set.join(", ")} WHERE #{conn.adapter.quote_identifier(self.class.primary_key_name)} = #{conn.adapter.placeholder(columns.size)}",
            args: args
          )
        end

        # The bind-ready form of a dirty attribute, encoded by the adapter
        # (JSON columns are text on SQLite, native `JSON::Any` on
        # PostgreSQL).
        private def bind_attribute(attribute : Symbol) : Value
          case attribute
          {% for col_name, col in columns %}
            {% unless col[:primary] %}
            when :{{ col_name.id }}
              connection.adapter.encode_column(@{{ col_name.id }}, :{{ col[:type].id }})
            {% end %}
          {% end %}
          end
        end

        private def apply_create_timestamps : Nil
          {% for col_name, col in columns %}
            {% if col_name == :created_at %}
              self.created_at = Time.utc
            {% end %}
            {% if col_name == :updated_at %}
              self.updated_at = Time.utc
            {% end %}
          {% end %}
        end

        private def apply_update_timestamps : Nil
          {% for col_name, col in columns %}
            {% if col_name == :updated_at %}
              self.updated_at = Time.utc
            {% end %}
          {% end %}
        end
      end

      # Declares that a string column holds one of a fixed set of values,
      # exposed as a nested enum so only declared members type-check:
      #
      # ```
      # class Post < Altair::Record::Model
      #   table :posts
      #   enum_attribute :state, [:draft, :published]
      # end
      #
      # post.state = Post::State::Published # compiles
      # post.state = "published"            # compile error
      # ```
      #
      # The column stores the member name in snake_case ("published",
      # "in_review"), keeping the raw data readable; a stored value no
      # member claims reads back as `nil`. Validations, `find_by_*` and
      # bulk paths keep operating on the underlying string.
      macro enum_attribute(name, values)
        {% enum_name = name.id.stringify.camelcase.id %}

        # The fixed set of {{ name.id }} values this column accepts.
        enum {{ enum_name }}
          {% for value in values %}
            {{ value.id.stringify.camelcase.id }}
          {% end %}
        end

        def {{ name.id }} : {{ enum_name }}?
          raw = @{{ name.id }}
          return nil if raw.nil?
          {{ enum_name }}.values.find do |member|
            member.to_s.underscore == raw || member.to_s == raw
          end
        end

        def {{ name.id }}=(value : {{ enum_name }}?) : Nil
          @dirty << :{{ name.id }}
          @{{ name.id }} = value.nil? ? nil : value.to_s.underscore
        end

        def self.find_by_{{ name.id }}(value : {{ enum_name }}) : self?
          find_by_{{ name.id }}(value.to_s.underscore)
        end
      end

      # Declares a reusable named query fragment, callable as a class
      # method and chainable with other scopes and Relation methods:
      #
      # ```
      # class Post < Altair::Record::Model
      #   table :posts
      #   scope :published, published: true
      #   scope :recent { |query| query.order(:created_at).limit(10) }
      # end
      #
      # Post.published.recent.to_a
      # ```
      #
      # The static form takes `key: value` pairs passed to `where`; the
      # block form receives the relation and returns whatever chain it
      # builds. The block must take exactly one parameter. Two scopes
      # compose through `Relation#merge`
      # (`Post.published.merge(Post.recent)`), since Crystal has no
      # dynamic dispatch to chain them directly.
      macro scope(name, **conditions, &block)
        {% if conditions.empty? && !block %}
          {% raise "scope :#{name.id} needs either key: value conditions or a block" %}
        {% end %}
        {% if block && block.args.size != 1 %}
          {% raise "scope :#{name.id} block must take exactly one parameter, e.g. |r|" %}
        {% end %}
        def self.{{ name.id }} : Altair::Record::Relation(self)
          {% if block %}
            {% var = block.args[0].id %}
            {{ var }} = all
            {{ block.body }}
          {% else %}
            all.where(**{{ conditions }})
          {% end %}
        end
      end

      # The connection the model queries through.
      def self.connection : Connection
        Altair::Record.connection
      end

      # The `SELECT` prefix over every column, in schema order.
      def self.select_sql : String
        quoted = column_names.map { |column| connection.adapter.quote_identifier(column) }
        "SELECT #{quoted.join(", ")} FROM #{connection.adapter.quote_identifier(table_name)}"
      end

      # Finds the record with the given id, or `nil`.
      def self.find(id : Int32 | Int64) : self?
        connection.query_one(
          select_sql + " WHERE #{connection.adapter.quote_identifier(primary_key_name)} = #{connection.adapter.placeholder(0)} LIMIT 1", id
        ) { |rs| from_row(rs) }
      rescue DB::NoResultsError
        nil
      end

      # Bulk-insert hook; the `table` macro provides the real
      # implementation for models backed by a schema.
      def self.insert_all(rows : Enumerable(NamedTuple)) : Int64
        raise Altair::Error.new("#{self} has no table — declare one with `table :name`")
      end

      # Finds the record with the given id, raising `RecordNotFound` when
      # there is none.
      def self.find!(id : Int32 | Int64) : self
        find(id) || raise RecordNotFound.new("Couldn't find #{table_name} with id=#{id}")
      end

      # Every record, lazily loaded on iteration. `includes` schedules
      # batched eager loading of associations.
      def self.all : Relation(self)
        Relation(self).new
      end

      # The primary-key column name (`"id"`).
      def self.primary_key_name : String
        "id"
      end

      # Loads every record whose primary key appears in `ids`, in one
      # batched query. The polymorphic loader's typed entry point: calling
      # through a concrete subclass keeps `from_row`'s id accessors
      # compile-time visible.
      def self.select_all(ids : Array(Int64 | Int32)) : Array(self)
        return [] of self if ids.empty?
        normalized = ids.map(&.to_i64)
        rows = [] of self
        placeholders = normalized.each_index.map { |index| connection.adapter.placeholder(index) }
        connection.query(
          "#{select_sql} WHERE #{connection.adapter.quote_identifier(primary_key_name)} " \
          "IN (#{placeholders.join(", ")})",
          values: normalized
        ) do |rs|
          rs.each { rows << from_row(rs) }
        end
        rows
      end

      # The number of records.
      def self.count : Int64
        connection.query_one(
          "SELECT COUNT(*) FROM #{connection.adapter.quote_identifier(table_name)}"
        ) { |rs| rs.read(Int64) }
      end

      # Whether any record exists.
      def self.exists? : Bool
        connection.query_one(
          "SELECT 1 FROM #{connection.adapter.quote_identifier(table_name)} LIMIT 1"
        ) { |rs| rs.read(Int64) } == 1
      rescue DB::NoResultsError
        false
      end

      # Whether a record with the given id exists.
      def self.exists?(id : Int32 | Int64) : Bool
        connection.query_one(
          "SELECT 1 FROM #{connection.adapter.quote_identifier(table_name)} " \
          "WHERE #{connection.adapter.quote_identifier(primary_key_name)} = #{connection.adapter.placeholder(0)} LIMIT 1",
          id
        ) { |rs| rs.read(Int64) } == 1
      rescue DB::NoResultsError
        false
      end

      # Runs the block inside a database transaction; a raise rolls it
      # back.
      def self.transaction(&block : Proc(Nil)) : Nil
        connection.transaction { block.call }
      end

      # Validates the record, clearing previous errors. Returns whether the
      # record is valid.
      def valid? : Bool
        @errors.clear
        _run_validations
        @errors.empty?
      end

      # Persists the record: inserts when the id is `nil`, updates
      # otherwise. Runs validations and the save callbacks first, and
      # returns `false` when validations fail. A model with callbacks saves
      # inside a transaction so a raise rolls everything back; a
      # callback-free model saves with a single statement, skipping the
      # transaction wrapper.
      def save : Bool
        return false unless valid?
        if self.class.__callbacks?
          save_transactional
        else
          save_plain
        end
      end

      # Persists a callback-free record with a single statement. Without
      # callbacks there is nothing to make atomic with the insert or update,
      # so the transaction wrapper would only cost two extra round trips.
      private def save_plain : Bool
        if @id.nil?
          apply_create_timestamps
          insert
        else
          unless @dirty.empty?
            apply_update_timestamps
            update_row
          end
        end
        clear_dirty
        true
      end

      # Persists a record with save callbacks, wrapping them and the insert
      # or update in a transaction so a raise rolls everything back. The
      # commit hooks fire after the transaction lands; a rollback fires
      # them on the way out and re-raises.
      private def save_transactional : Bool
        persisted = false
        begin
          self.class.transaction do
            _run_callbacks(:before_save)
            if @id.nil?
              _run_callbacks(:before_create)
              apply_create_timestamps
              insert
              _run_callbacks(:after_create)
            else
              _run_callbacks(:before_update)
              unless @dirty.empty?
                apply_update_timestamps
                update_row
              end
              _run_callbacks(:after_update)
            end
            _run_callbacks(:after_save)
            persisted = true
          end
        rescue e
          _run_callbacks(:after_rollback)
          raise e
        end
        _run_callbacks(:after_commit)
        clear_dirty if persisted
        persisted
      end

      # Like `save`, raising `RecordInvalid` when validations fail.
      def save! : self
        raise RecordInvalid.new(self) unless save
        self
      end

      # Deletes the row, running the destroy callbacks inside a transaction
      # and the commit hooks once it lands. Returns whether a row was
      # deleted.
      def delete : Bool
        return false if @id.nil?
        deleted = false
        begin
          self.class.transaction do
            _run_callbacks(:before_destroy)
            result = connection.exec(
              "DELETE FROM #{connection.adapter.quote_identifier(self.class.table_name)} " \
              "WHERE #{connection.adapter.quote_identifier(self.class.primary_key_name)} = #{connection.adapter.placeholder(0)}",
              @id
            )
            deleted = result.rows_affected > 0
            _run_callbacks(:after_destroy)
          end
        rescue e
          _run_callbacks(:after_rollback)
          raise e
        end
        _run_callbacks(:after_commit)
        deleted
      end

      # Bumps `updated_at` — plus any explicitly listed columns — to now
      # with one direct UPDATE. Callbacks, validations and dirty tracking
      # are bypassed; the touched attributes are refreshed from the row.
      #
      # ```
      # post.touch
      # audit.touch(:reviewed_at)
      # ```
      def touch(*columns : Symbol) : self
        touch_columns(columns.to_a)
      end

      # No-column form: bumps `updated_at` only.
      def touch : self
        touch_columns([] of Symbol)
      end

      private def touch_columns(columns : Array(Symbol)) : self
        if @id.nil?
          raise Altair::Error.new("cannot touch #{self.class.table_name} before it is saved")
        end
        names = [:updated_at] + columns.to_a
        assignments = [] of String
        binds = [] of Value
        adapter = connection.adapter
        names.each do |column|
          unless self.class.column_names.includes?(column.to_s)
            raise Altair::Error.new("unknown column :#{column} on #{self.class.table_name}")
          end
          assignments << "#{adapter.quote_identifier(column.to_s)} = #{adapter.placeholder(0)}"
          binds << Time.utc
        end
        assignments << "#{adapter.quote_identifier(self.class.primary_key_name)} = #{adapter.placeholder(0)}"
        binds << @id
        connection.exec(
          "UPDATE #{adapter.quote_identifier(self.class.table_name)} " \
          "SET #{assignments.join(", ")}",
          args: binds
        )
        reload
      end

      # Adds `by` to an integer column atomically (`col = col + ?`) and
      # refreshes `updated_at`. Direct write — no callbacks.
      def increment!(column : Symbol, by : Int32 | Int64 = 1) : self
        bump_counter(column, by)
      end

      # Subtracts `by` from an integer column atomically.
      def decrement!(column : Symbol, by : Int32 | Int64 = 1) : self
        bump_counter(column, -by)
      end

      private def bump_counter(column : Symbol, delta : Int32 | Int64) : self
        if @id.nil?
          raise Altair::Error.new("cannot bump #{self.class.table_name} before it is saved")
        end
        unless self.class.column_names.includes?(column.to_s)
          raise Altair::Error.new("unknown column :#{column} on #{self.class.table_name}")
        end
        adapter = connection.adapter
        assignments = ["#{adapter.quote_identifier(column.to_s)} = " \
                       "#{adapter.quote_identifier(column.to_s)} + #{adapter.placeholder(0)}"]
        binds = [] of Value
        binds << delta
        if self.class.column_names.includes?("updated_at")
          assignments << "#{adapter.quote_identifier("updated_at")} = #{adapter.placeholder(1)}"
          binds << Time.utc
          pk_placeholder = adapter.placeholder(2)
        else
          pk_placeholder = adapter.placeholder(1)
        end
        connection.exec(
          "UPDATE #{adapter.quote_identifier(self.class.table_name)} SET #{assignments.join(", ")} " \
          "WHERE #{adapter.quote_identifier(self.class.primary_key_name)} = #{pk_placeholder}",
          args: binds + [@id]
        )
        reload
      end

      # The connection this record queries through.
      protected def connection : Connection
        self.class.connection
      end

      # The default no-ops below are overridden per subclass by the
      # `inherited` hook.

      # Runs the declared callbacks for the given kind.
      def _run_callbacks(kind : Symbol) : Nil
      end

      # Runs the declared validation rules.
      def _run_validations : Nil
      end

      macro inherited
        Altair::Record.polymorphic_klasses[{{ @type.name.stringify }}] = {{ @type }}

        @@callbacks = {} of Symbol => Array(Proc({{@type.id}}, Nil))
        @@validations = [] of Rule
        @@custom_validations = [] of Proc({{@type.id}}, Nil)
        @@conditions = {} of Symbol => Proc(Altair::Record::Model, Bool)
        @@confirmations = {} of String => Proc({{@type.id}}, Value?)
        @@preloaders = {} of Symbol => Proc(Array(Altair::Record::Model), Array(Altair::Record::Model))
        @@association_metas = {} of Symbol => NamedTuple(kind: Symbol, target_class: String, foreign_key: String, through: String, source: String)

        # Whether the model registers any save callbacks; a callback-free
        # model saves without the transaction wrapper.
        def self.__callbacks? : Bool
          @@callbacks.values.any?(&.any?)
        end

        # Whether the model declares destroy lifecycle callbacks — batched
        # dependent deletes honor them instead of one DELETE statement.
        def self.__destroy_callbacks? : Bool
          @@callbacks.fetch(:before_destroy, [] of Proc({{@type.id}}, Nil)).any? ||
            @@callbacks.fetch(:after_destroy, [] of Proc({{@type.id}}, Nil)).any?
        end

        # The eager loader for an association, or a clear error. The
        # signature matches the base class exactly, so runtime metaclass
        # dispatch reaches the subclass override.
        def self.__preloader_for(name : Symbol) : Proc(Array(Altair::Record::Model), Array(Altair::Record::Model))
          @@preloaders[name]? || raise ArgumentError.new(
            "Unknown association :#{name} for #{self}"
          )
        end

        # The association metadata for `joins`, or a clear error.
        def self.__association_meta_for(name : Symbol) : NamedTuple(kind: Symbol, target_class: String, foreign_key: String, through: String, source: String)
          @@association_metas[name]? || raise ArgumentError.new(
            "Unknown association :#{name} for #{self}"
          )
        end

        def _run_callbacks(kind : Symbol) : Nil
          @@callbacks.fetch(kind, [] of Proc({{@type.id}}, Nil)).each do |callback|
            callback.call(self)
          end
        end

        def _run_validations : Nil
          @@custom_validations.each do |callback|
            callback.call(self)
          end
          @@validations.each do |rule|
            if if_method = rule.if_method
              next unless condition?(if_method)
            end
            if unless_method = rule.unless_method
              next if condition?(unless_method)
            end
            if rule.allow_nil? && (attribute = rule.attribute) && attribute_value(attribute).nil?
              next
            end
            case rule.kind
            when :presence     then check_presence(rule)
            when :length       then check_length(rule)
            when :numericality then check_numericality(rule)
            when :uniqueness   then check_uniqueness(rule)
            when :inclusion    then check_inclusion(rule)
            when :exclusion    then check_exclusion(rule)
            when :format       then check_format(rule)
            when :confirmation then check_confirmation(rule)
            end
          end
        end

        private def condition?(name : Symbol) : Bool
          predicate = @@conditions[name]?
          raise Altair::Error.new("unknown validation condition :#{name} on #{self.class}") unless predicate
          predicate.call(self)
        end
      end

      macro before_save(*methods)
        {% for method in methods %}
          (@@callbacks[:before_save] ||= [] of Proc({{@type.id}}, Nil)) << ->(record : {{@type.id}}) { record.{{method.id}} }
        {% end %}
      end

      macro after_save(*methods)
        {% for method in methods %}
          (@@callbacks[:after_save] ||= [] of Proc({{@type.id}}, Nil)) << ->(record : {{@type.id}}) { record.{{method.id}} }
        {% end %}
      end

      macro before_create(*methods)
        {% for method in methods %}
          (@@callbacks[:before_create] ||= [] of Proc({{@type.id}}, Nil)) << ->(record : {{@type.id}}) { record.{{method.id}} }
        {% end %}
      end

      macro after_create(*methods)
        {% for method in methods %}
          (@@callbacks[:after_create] ||= [] of Proc({{@type.id}}, Nil)) << ->(record : {{@type.id}}) { record.{{method.id}} }
        {% end %}
      end

      macro before_update(*methods)
        {% for method in methods %}
          (@@callbacks[:before_update] ||= [] of Proc({{@type.id}}, Nil)) << ->(record : {{@type.id}}) { record.{{method.id}} }
        {% end %}
      end

      macro after_update(*methods)
        {% for method in methods %}
          (@@callbacks[:after_update] ||= [] of Proc({{@type.id}}, Nil)) << ->(record : {{@type.id}}) { record.{{method.id}} }
        {% end %}
      end

      macro before_destroy(*methods)
        {% for method in methods %}
          (@@callbacks[:before_destroy] ||= [] of Proc({{@type.id}}, Nil)) << ->(record : {{@type.id}}) { record.{{method.id}} }
        {% end %}
      end

      macro after_destroy(*methods)
        {% for method in methods %}
          (@@callbacks[:after_destroy] ||= [] of Proc({{@type.id}}, Nil)) << ->(record : {{@type.id}}) { record.{{method.id}} }
        {% end %}
      end

      # Runs after the record's save transaction has committed. Enqueue
      # jobs and invalidate caches here — `after_save` fires inside the
      # transaction, before the data is visible to other connections.
      macro after_commit(*methods)
        {% for method in methods %}
          (@@callbacks[:after_commit] ||= [] of Proc({{@type.id}}, Nil)) << ->(record : {{@type.id}}) { record.{{method.id}} }
        {% end %}
      end

      # Runs when the record's save or delete transaction rolled back.
      macro after_rollback(*methods)
        {% for method in methods %}
          (@@callbacks[:after_rollback] ||= [] of Proc({{@type.id}}, Nil)) << ->(record : {{@type.id}}) { record.{{method.id}} }
        {% end %}
      end

      # Every `validates_*` macro accepts `if:` / `unless:` predicate
      # method names and `allow_nil:` — a nil attribute skips the rule.
      # `validates_uniqueness_of` also takes `case_sensitive: false` to
      # match through LOWER on both sides.

      macro register_condition(name)
        {% if name %}
          @@conditions[{{ name.id.symbolize }}] ||= ->(record : Altair::Record::Model) { record.as({{@type.id}}).{{ name.id }} }
        {% end %}
      end

      macro validates_presence_of(*attributes, message = nil, **opts)
        register_condition({{ opts[:if] }})
        register_condition({{ opts[:unless] }})
        {% for attribute in attributes %}
          @@validations << Rule.new(:presence, attribute: {{ attribute }}, message: {{ message }}, if_method: {{ opts[:if] }}, unless_method: {{ opts[:unless] }}, allow_nil: {{ opts[:allow_nil] || false }})
        {% end %}
      end

      macro validates_length_of(*attributes, minimum = nil, maximum = nil, message = nil, **opts)
        register_condition({{ opts[:if] }})
        register_condition({{ opts[:unless] }})
        {% for attribute in attributes %}
          @@validations << Rule.new(:length, attribute: {{ attribute }}, minimum: {{ minimum }}, maximum: {{ maximum }}, message: {{ message }}, if_method: {{ opts[:if] }}, unless_method: {{ opts[:unless] }}, allow_nil: {{ opts[:allow_nil] || false }})
        {% end %}
      end

      macro validates_numericality_of(*attributes, greater_than = nil, integer = nil, message = nil, **opts)
        register_condition({{ opts[:if] }})
        register_condition({{ opts[:unless] }})
        {% for attribute in attributes %}
          @@validations << Rule.new(:numericality, attribute: {{ attribute }}, greater_than: {{ greater_than }}, integer: {{ integer }}, message: {{ message }}, if_method: {{ opts[:if] }}, unless_method: {{ opts[:unless] }}, allow_nil: {{ opts[:allow_nil] || false }})
        {% end %}
      end

      macro validates_uniqueness_of(*attributes, scope = nil, message = nil, case_sensitive = true, **opts)
        register_condition({{ opts[:if] }})
        register_condition({{ opts[:unless] }})
        {% for attribute in attributes %}
          @@validations << Rule.new(:uniqueness, attribute: {{ attribute }}, scope: {{ scope }}, message: {{ message }}, case_sensitive: {{ case_sensitive }}, if_method: {{ opts[:if] }}, unless_method: {{ opts[:unless] }}, allow_nil: {{ opts[:allow_nil] || false }})
        {% end %}
      end

      macro validates_inclusion_of(*attributes, message = nil, **options)
        register_condition({{ options[:if] }})
        register_condition({{ options[:unless] }})
        {% for attribute in attributes %}
          @@validations << Rule.new(:inclusion, attribute: {{ attribute }}, possibilities: {{ options[:in] }}, message: {{ message }}, if_method: {{ options[:if] }}, unless_method: {{ options[:unless] }}, allow_nil: {{ options[:allow_nil] || false }})
        {% end %}
      end

      macro validates_exclusion_of(*attributes, message = nil, **options)
        register_condition({{ options[:if] }})
        register_condition({{ options[:unless] }})
        {% for attribute in attributes %}
          @@validations << Rule.new(:exclusion, attribute: {{ attribute }}, possibilities: {{ options[:in] }}, message: {{ message }}, if_method: {{ options[:if] }}, unless_method: {{ options[:unless] }}, allow_nil: {{ options[:allow_nil] || false }})
        {% end %}
      end

      macro validates_format_of(*attributes, message = nil, **options)
        register_condition({{ options[:if] }})
        register_condition({{ options[:unless] }})
        {% for attribute in attributes %}
          @@validations << Rule.new(:format, attribute: {{ attribute }}, format: {{ options[:with] }}, message: {{ message }}, if_method: {{ options[:if] }}, unless_method: {{ options[:unless] }}, allow_nil: {{ options[:allow_nil] || false }})
        {% end %}
      end

      macro validates_confirmation_of(*attributes, message = nil, **opts)
        register_condition({{ opts[:if] }})
        register_condition({{ opts[:unless] }})
        {% for attribute in attributes %}
          @@validations << Rule.new(:confirmation, attribute: {{ attribute }}, message: {{ message }}, if_method: {{ opts[:if] }}, unless_method: {{ opts[:unless] }}, allow_nil: {{ opts[:allow_nil] || false }})
          @@confirmations[{{ attribute.id.stringify }}] = ->(record : {{ @type.id }}) : Value? { record.{{ attribute.id }}_confirmation }
        {% end %}
      end

      macro validate(*methods)
        {% for method in methods %}
          @@custom_validations << ->(record : {{@type.id}}) { record.{{method.id}} }
        {% end %}
      end

      # The default no-ops below are overridden per subclass by the
      # `table` macro when the schema has timestamp columns.

      # Sets the create timestamps. Overridden per table.
      private def apply_create_timestamps : Nil
      end

      # Sets the update timestamps. Overridden per table.
      private def apply_update_timestamps : Nil
      end

      private def check_presence(rule : Rule) : Nil
        attribute = rule.attribute.not_nil!
        value = attribute_value(attribute)
        present = !value.nil? && !(value.responds_to?(:empty?) && value.empty?)
        errors.add(attribute, rule.message || "can't be blank") unless present
      end

      private def check_length(rule : Rule) : Nil
        attribute = rule.attribute.not_nil!
        value = attribute_value(attribute)
        return unless value.is_a?(String)
        if minimum = rule.minimum
          errors.add(attribute, rule.message || "is too short (minimum is #{minimum} characters)") if value.size < minimum
        end
        if maximum = rule.maximum
          errors.add(attribute, rule.message || "is too long (maximum is #{maximum} characters)") if value.size > maximum
        end
      end

      private def check_numericality(rule : Rule) : Nil
        attribute = rule.attribute.not_nil!
        value = attribute_value(attribute)
        unless value.is_a?(Int32) || value.is_a?(Int64) || value.is_a?(Float64)
          errors.add(attribute, rule.message || "is not a number")
          return
        end
        if greater_than = rule.greater_than
          errors.add(attribute, rule.message || "must be greater than #{greater_than}") unless value.to_f64 > greater_than
        end
        if rule.integer
          errors.add(attribute, rule.message || "must be an integer") unless value.is_a?(Int32) || value.is_a?(Int64) || value.to_f64.round == value.to_f64
        end
      end

      private def check_uniqueness(rule : Rule) : Nil
        attribute = rule.attribute.not_nil!
        value = attribute_value(attribute)
        return if value.nil?
        adapter = connection.adapter
        where = [] of String
        args = [] of Value
        if rule.case_sensitive?
          where << "#{adapter.quote_identifier(attribute.to_s)} = #{adapter.placeholder(args.size)}"
          args << value
        else
          where << "LOWER(#{adapter.quote_identifier(attribute.to_s)}) = LOWER(#{adapter.placeholder(args.size)})"
          args << value
        end
        if id = @id
          where << "#{adapter.quote_identifier("id")} != #{adapter.placeholder(args.size)}"
          args << id
        end
        if scope = rule.scope
          where << "#{adapter.quote_identifier(scope.to_s)} = #{adapter.placeholder(args.size)}"
          args << attribute_value(scope)
        end
        duplicate = false
        connection.query(
          "SELECT 1 FROM #{adapter.quote_identifier(self.class.table_name)} WHERE #{where.join(" AND ")}",
          values: args
        ) do |rs|
          duplicate = rs.move_next
        end
        errors.add(attribute, rule.message || "has already been taken") if duplicate
      end

      private def check_inclusion(rule : Rule) : Nil
        attribute = rule.attribute.not_nil!
        value = attribute_value(attribute)
        return if value.nil?
        possibilities = rule.possibilities.not_nil!
        included = case possibilities
                   when Array(String)       then possibilities.includes?(value.to_s)
                   when Range(Int32, Int32) then value.is_a?(Int32) && possibilities.includes?(value)
                   else                          false
                   end
        errors.add(attribute, rule.message || "is not included in the list") unless included
      end

      private def check_exclusion(rule : Rule) : Nil
        attribute = rule.attribute.not_nil!
        value = attribute_value(attribute)
        return if value.nil?
        possibilities = rule.possibilities.not_nil!
        excluded = case possibilities
                   when Array(String)       then possibilities.includes?(value.to_s)
                   when Range(Int32, Int32) then value.is_a?(Int32) && possibilities.includes?(value)
                   else                          false
                   end
        errors.add(attribute, rule.message || "is reserved") if excluded
      end

      private def check_format(rule : Rule) : Nil
        attribute = rule.attribute.not_nil!
        value = attribute_value(attribute)
        return unless value.is_a?(String)
        pattern = rule.format.not_nil!
        errors.add(attribute, rule.message || "is invalid") unless pattern.matches?(value)
      end

      private def check_confirmation(rule : Rule) : Nil
        attribute = rule.attribute.not_nil!
        value = attribute_value(attribute)
        return if value.nil?
        if getter = @@confirmations[attribute.to_s]?
          confirmed = getter.call(self)
          errors.add(attribute, rule.message || "isn't the same as the confirmation") unless confirmed == value
        end
      end
    end
  end
end
