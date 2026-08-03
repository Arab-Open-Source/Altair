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

        def initialize(@kind : Symbol, @attribute : Symbol? = nil, @method : Symbol? = nil,
                       @minimum : Int32? = nil, @maximum : Int32? = nil,
                       @greater_than : Float64? = nil, @integer : Bool? = nil,
                       @scope : Symbol? = nil, @message : String? = nil,
                       @possibilities : (Array(String) | Range(Int32, Int32))? = nil,
                       @format : Regex? = nil)
        end
      end

      # The set of attributes changed since the last load or save. Consumed
      # by `update_row` so a save only writes the columns that actually
      # changed.
      @dirty : Set(Symbol) = Set(Symbol).new

      # The errors of this record, populated by `valid?`.
      getter errors : Errors = Errors.new

      # The table backing this model. Overridden by the `table` macro.
      def self.table_name : String
        raise Altair::Error.new("#{self} has no table — declare one with `table :name`")
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
      macro table(name)
        {% unless Altair::Record::Schema::META.keys.any? { |key| key.stringify == name.id.stringify } %}
          {% raise "Unknown table :#{name.id} — db/schema.cr defines: #{Altair::Record::Schema::META.keys.map(&.id).join(", ")}. Run the migrations to regenerate it." %}
        {% end %}

        {% columns = Altair::Record::Schema::META[name] %}

        {% pk_name = "id" %}
        {% pk_type = :integer %}
        {% for col_name, col in columns %}
          {% if col[:primary] %}
            {% pk_name = col_name.id %}
            {% pk_type = col[:type] %}
          {% end %}
        {% end %}

        # The primary key; `nil` until the record is saved.
        @id : {{ CRYSTAL_TYPE[pk_type].id }}? = nil

        def self.table_name : String
          "{{ name.id }}"
        end

        def self.column_names : Array(String)
          [{% for col_name, col in columns %}"{{ col_name.id }}", {% end %}]
        end

        def self.timestamp_columns : Array(Symbol)
          [:created_at, :updated_at].select { |column| column_names.includes?(column.to_s) }
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
            quoted = connection.adapter.quote_identifier("{{ col_name.id }}")
            {% if nullable %}
              sql = select_sql + " WHERE #{quoted} " + (value.nil? ? "IS NULL" : "= #{connection.adapter.placeholder(0)}") + " LIMIT 1"
              value.nil? ? connection.query_one(sql) { |rs| from_row(rs) } : connection.query_one(sql, value) { |rs| from_row(rs) }
            {% else %}
              connection.query_one(select_sql + " WHERE #{quoted} = #{connection.adapter.placeholder(0)} LIMIT 1", value) { |rs| from_row(rs) }
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
            {{ col_name.id }}
          {% end %}
          else
            raise ArgumentError.new("Unknown attribute :#{attribute}")
          end
        end

        private def insert : Nil
          conn = connection
          columns = self.class.column_names.reject { |column| column == "id" }
          quoted = columns.map { |column| conn.adapter.quote_identifier(column) }
          placeholders = columns.each_index.map { |index| conn.adapter.placeholder(index) }
          sql = "INSERT INTO #{conn.adapter.quote_identifier(self.class.table_name)} " \
                "(#{quoted.join(", ")}) VALUES (#{placeholders.join(", ")})"
          {% args = [] of String %}
          {% for col_name, col in columns %}
            {% unless col[:primary] %}
              {% args << "connection.adapter.encode_column(@#{col_name.id}, :#{col[:type].id})" %}
            {% end %}
          {% end %}
          if conn.adapter.supports_returning?(:insert)
            conn.query_one(
              "#{sql} RETURNING #{conn.adapter.quote_identifier("id")}",
              {{ args.join(", ").id }}
            ) { |rs| @id = rs.read({{ CRYSTAL_TYPE[pk_type].id }}) }
          else
            result = conn.exec(
              sql,
              {{ args.join(", ").id }}
            )
            @id = {% if pk_type == :bigint %}conn.last_insert_id(result){% else %}conn.last_insert_id(result).to_i32{% end %}
          end
        end

        protected def clear_dirty : Nil
          @dirty.clear
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
            "SET #{set.join(", ")} WHERE #{conn.adapter.quote_identifier("id")} = #{conn.adapter.placeholder(columns.size)}",
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
          select_sql + " WHERE #{connection.adapter.quote_identifier("id")} = #{connection.adapter.placeholder(0)} LIMIT 1", id
        ) { |rs| from_row(rs) }
      rescue DB::NoResultsError
        nil
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
          "WHERE #{connection.adapter.quote_identifier("id")} = #{connection.adapter.placeholder(0)} LIMIT 1",
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
      # returns `false` when validations fail. The insert or update and its
      # callbacks run inside a transaction, so a raise rolls everything
      # back.
      def save : Bool
        return false unless valid?
        persisted = false
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
        clear_dirty if persisted
        persisted
      end

      # Like `save`, raising `RecordInvalid` when validations fail.
      def save! : self
        raise RecordInvalid.new(self) unless save
        self
      end

      # Deletes the row, running the destroy callbacks inside a transaction.
      # Returns whether a row was deleted.
      def delete : Bool
        return false if @id.nil?
        deleted = false
        self.class.transaction do
          _run_callbacks(:before_destroy)
          result = connection.exec(
            "DELETE FROM #{connection.adapter.quote_identifier(self.class.table_name)} " \
            "WHERE #{connection.adapter.quote_identifier("id")} = #{connection.adapter.placeholder(0)}",
            @id
          )
          deleted = result.rows_affected > 0
          _run_callbacks(:after_destroy)
        end
        deleted
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
        @@callbacks = {} of Symbol => Array(Proc({{@type.id}}, Nil))
        @@validations = [] of Rule
        @@custom_validations = [] of Proc({{@type.id}}, Nil)
        @@confirmations = {} of String => Proc({{@type.id}}, Value?)
        @@preloaders = {} of Symbol => Proc(Array({{@type.id}}), Nil)

        # The eager loader for an association, or a clear error.
        def self.__preloader_for(name : Symbol) : Proc(Array({{@type.id}}), Nil)
          @@preloaders[name]? || raise ArgumentError.new(
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

      macro validates_presence_of(*attributes, message = nil)
        {% for attribute in attributes %}
          @@validations << Rule.new(:presence, attribute: {{ attribute }}, message: {{ message }})
        {% end %}
      end

      macro validates_length_of(*attributes, minimum = nil, maximum = nil, message = nil)
        {% for attribute in attributes %}
          @@validations << Rule.new(:length, attribute: {{ attribute }}, minimum: {{ minimum }}, maximum: {{ maximum }}, message: {{ message }})
        {% end %}
      end

      macro validates_numericality_of(*attributes, greater_than = nil, integer = nil, message = nil)
        {% for attribute in attributes %}
          @@validations << Rule.new(:numericality, attribute: {{ attribute }}, greater_than: {{ greater_than }}, integer: {{ integer }}, message: {{ message }})
        {% end %}
      end

      macro validates_uniqueness_of(*attributes, scope = nil, message = nil)
        {% for attribute in attributes %}
          @@validations << Rule.new(:uniqueness, attribute: {{ attribute }}, scope: {{ scope }}, message: {{ message }})
        {% end %}
      end

      macro validates_inclusion_of(*attributes, message = nil, **options)
        {% for attribute in attributes %}
          @@validations << Rule.new(:inclusion, attribute: {{ attribute }}, possibilities: {{ options[:in] }}, message: {{ message }})
        {% end %}
      end

      macro validates_exclusion_of(*attributes, message = nil, **options)
        {% for attribute in attributes %}
          @@validations << Rule.new(:exclusion, attribute: {{ attribute }}, possibilities: {{ options[:in] }}, message: {{ message }})
        {% end %}
      end

      macro validates_format_of(*attributes, message = nil, **options)
        {% for attribute in attributes %}
          @@validations << Rule.new(:format, attribute: {{ attribute }}, format: {{ options[:with] }}, message: {{ message }})
        {% end %}
      end

      macro validates_confirmation_of(*attributes, message = nil)
        {% for attribute in attributes %}
          @@validations << Rule.new(:confirmation, attribute: {{ attribute }}, message: {{ message }})
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
        where << "#{adapter.quote_identifier(attribute.to_s)} = #{adapter.placeholder(args.size)}"
        args << value
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
