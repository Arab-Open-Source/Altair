# Altair — the batteries-included web framework for Crystal.
#
# This file adds the association macros to `Altair::Record::Model`:
# `belongs_to`, `has_many` and `has_one`. Each declaration generates the
# lazy accessor and its cache, a batched class-level preloader, and — when
# `dependent:` is given — an internal `before_destroy` hook. The preloaders
# register into the class's `@@preloaders` registry so
# `Relation#includes` can dispatch by name at runtime.
module Altair
  module Record
    class Model
      # Declares a many-to-one association. The foreign key column is
      # named after the association (`post_id` for `belongs_to :post`);
      # pass `foreign_key:` to override, and `class_name:` when the
      # model class does not derive from the association name:
      #
      # ```
      # class Comment < Altair::Record::Model
      #   table :comments
      #   belongs_to :post
      # end
      #
      # comment.post        # lazy query, cached
      # comment.post = post # assigns the owner and the foreign key
      # ```
      macro belongs_to(name, class_name = nil, foreign_key = nil, polymorphic = false)
        {% assoc = name.id %}
        {% if polymorphic %}
          {% id_col = "#{name.id}_id" %}
          {% type_col = "#{name.id}_type" %}
          {% table_found = false %}
          {% for c in @type.constants %}
            {% if c.stringify == "TABLE_NAME" %}
              {% table_found = true %}
            {% end %}
          {% end %}
          {% unless table_found %}
            {% raise "belongs_to #{assoc.id} polymorphic: declare `table :x` before the association" %}
          {% end %}
          {% tbl = @type.constant(:TABLE_NAME).stringify.gsub(/"/, "").gsub(/\\/, "") %}
                    {% unless Altair::Record::Schema::META[tbl] && Altair::Record::Schema::META[tbl][id_col] %}
            {% raise "belongs_to #{assoc.id} polymorphic: table '#{tbl}' lacks #{id_col}_type/#{id_col} — add t.references :#{assoc.id}, polymorphic: true" %}
          {% end %}
          {% pk_meta = Altair::Record::Schema::META[tbl][id_col] %}
          {% col_crystal = CRYSTAL_TYPE[pk_meta[:type]] %}

          # Eager-load/dispatch cache; values live in the schema columns.
          @{{ assoc.id }} : Altair::Record::Model?
          @{{ assoc.id }}_loaded : Bool = false

          # The associated record, resolved from the stored type string at
          # runtime and cached. Unknown types raise a clear error.
          def {{ assoc.id }} : Altair::Record::Model?
            if @{{ assoc.id }}_loaded
              @{{ assoc.id }}
            else
              @{{ assoc.id }}_loaded = true
              type = self.{{ type_col.id }}
              id_value = self.{{ id_col.id }}
              if type && id_value
                Altair::Record.resolve_klass(type).find(id_value).as(Altair::Record::Model | Nil)
              else
                nil
              end
            end
          end

          # Assigns the associated record and both columns.
          def {{ assoc.id }}=(owner : Altair::Record::Model?) : Nil
            @{{ assoc.id }} = owner
            @{{ assoc.id }}_loaded = true
            if owner
              {% conv_to = pk_meta[:type] == :bigint ? "i64" : "i32" %}
              self.{{ id_col.id }} = owner.__pk.not_nil!.to_{{ conv_to.id }}
              self.{{ type_col.id }} = owner.class.name
            else
              self.{{ id_col.id }} = nil
              self.{{ type_col.id }} = nil
            end
          end

          protected def __set_preloaded_{{ assoc.id }}(owner : Altair::Record::Model?) : Nil
            @{{ assoc.id }} = owner
            @{{ assoc.id }}_loaded = true
          end

          # Loads associated owners batched per distinct type — one query
          # per type present in the collection, never one per record.
          private def self.__load_{{ assoc.id }}(records : Array({{ @type.id }})) : Array(Altair::Record::Model)
            pairs = records.compact_map do |record|
              next if record.{{ type_col.id }}.nil? || record.{{ id_col.id }}.nil?
              {record.{{ type_col.id }}.not_nil!, record.{{ id_col.id }}.not_nil!.to_i64}
            end.group_by(&.[0])
            loaded = Hash(String, Hash(Int64, Altair::Record::Model)).new { |h, k| h[k] = {} of Int64 => Altair::Record::Model }
            pairs.each do |type, group|
              klass = Altair::Record.resolve_klass(type)
              ids = group.map(&.[1]).uniq
              placeholders = ids.each_index.map { |index| connection.adapter.placeholder(index) }
              rows_for_type = klass.select_all(ids)
              rows_for_type.each do |row|
                loaded[type][row.__pk.not_nil!] = row.as(Altair::Record::Model)
              end
            end
            records.each do |record|
              if type = record.{{ type_col.id }}
                if id_value = record.{{ id_col.id }}
                  record.__set_preloaded_{{ assoc.id }}(loaded[type][id_value.to_i64]?)
                  next
                end
              end
              record.__set_preloaded_{{ assoc.id }}(nil)
            end
            loaded.values.flat_map(&.values)
          end

          @@preloaders[:{{ assoc.id }}] = ->(records : Array(Altair::Record::Model)) do
            __load_{{ assoc.id }}(records.map(&.as({{ @type.id }})))
          end

          @@association_metas[:{{ assoc.id }}] = {kind: :belongs_to_polymorphic, target_class: "", foreign_key: "{{ id_col.id }}", through: "", source: ""}
        {% else %}
        {% model = class_name ? class_name.id : name.id.stringify.camelcase %}
        {% fk = foreign_key ? foreign_key.id : "#{name.id}_id".id %}

        @{{ assoc.id }} : {{ model.id }}?
        @{{ assoc.id }}_loaded : Bool = false

        # The associated record, loaded lazily and cached. An explicitly
        # preloaded or assigned `nil` is memoized, so accessing it after
        # eager loading never issues another query — the loader must not
        # degrade into a per-record lookup when a foreign key is missing.
        def {{ assoc.id }} : {{ model.id }}?
          if @{{ assoc.id }}_loaded
            @{{ assoc.id }}
          else
            @{{ assoc.id }}_loaded = true
            @{{ assoc.id }} = @{{ fk.id }}.try { |id| {{ model.id }}.find(id) }
          end
        end

        # Assigns the associated record and its foreign key.
        def {{ assoc.id }}=(owner : {{ model.id }}?) : Nil
          @{{ assoc.id }} = owner
          @{{ assoc.id }}_loaded = true
          @{{ fk.id }} = owner.try(&.id)
        end

        # Sets the cached record during eager loading.
        protected def __set_preloaded_{{ assoc.id }}(owner : {{ model.id }}?) : Nil
          @{{ assoc.id }} = owner
          @{{ assoc.id }}_loaded = true
        end

        # Loads every associated owner in one batched query and returns
        # the rows it read (empty when there were no keys to look up).
        private def self.__load_{{ assoc.id }}(records : Array({{ @type.id }})) : Array({{ model.id }})
          ids = records.compact_map(&.{{ fk.id }}).uniq
          return [] of {{ model.id }} if ids.empty?
          rows = [] of {{ model.id }}
          Altair::Record::Model.each_preload_chunk(ids) do |chunk|
            placeholders = chunk.each_index.map { |index| connection.adapter.placeholder(index) }
            connection.query(
              "#{{{ model.id }}.select_sql} WHERE #{connection.adapter.quote_identifier("id")} " \
              "IN (#{placeholders.join(", ")})",
              values: chunk
            ) do |rs|
              rs.each { rows << {{ model.id }}.from_row(rs) }
            end
          end
          by_id = rows.to_h { |owner| {owner.id.not_nil!, owner} }
          records.each { |record| record.__set_preloaded_{{ assoc.id }}(by_id[record.{{ fk.id }}]?) }
          rows
        end

        @@preloaders[:{{ assoc.id }}] = ->(records : Array(Altair::Record::Model)) do
          __load_{{ assoc.id }}(records.map(&.as({{ @type.id }}))).map(&.as(Altair::Record::Model))
        end

        @@association_metas[:{{ assoc.id }}] = {kind: :belongs_to, target_class: "{{ model.id }}", foreign_key: {{ fk.stringify }}, through: "", source: ""}
        {% end %}
      end

      # Declares a one-to-many association. The foreign key column lives
      # on the target table and is named after this model (`post_id` for
      # `has_many :comments` on `Post`); pass `foreign_key:` to override,
      # `class_name:` when the model class does not derive from the
      # association name, and `dependent:` to react to this record's
      # deletion:
      #
      # ```
      # class Post < Altair::Record::Model
      #   table :posts
      #   has_many :comments, dependent: :destroy
      # end
      #
      # post.comments # the comments, in id order, cached
      # ```
      #
      # `dependent: :destroy` deletes the children through their own
      # callbacks, `dependent: :delete_all` deletes them with one query
      # and `dependent: :nullify` clears their foreign keys.
      #
      # The model class derives by singularizing the association name
      # with the inflector's constant tables — `has_many :categories`
      # resolves to `Category` and `has_many :children` to `Child`. The
      # loop cannot call the runtime `Inflector` (it expands at compile
      # time), so it replays the same lookup order here. Runtime
      # `Inflector.irregular` pairs are invisible to it; pass
      # `class_name:` for those.
      macro has_many(name, class_name = nil, foreign_key = nil, dependent = nil, through = nil, source = nil, **opts)
        {% assoc = name.id %}
        {% has_as = false %}
        {% for k in opts.keys %}
          {% if k.stringify == "as" %}
            {% has_as = true %}
          {% end %}
        {% end %}
        {% polymorphic_type = has_as ? opts[:as].id.stringify.gsub(/"/, "") : "" %}
                {% if class_name %}
          {% model = class_name.id %}
        {% else %}
          {% singular = name.id.stringify %}
          {% for s, p in Altair::Inflector::IRREGULAR_PLURALS %}
            {% if singular == p %}
              {% singular = s %}
            {% end %}
          {% end %}
          {% matched = singular != name.id.stringify %}
          {% unless matched %}
            {% for w in Altair::Inflector::UNCOUNTABLES %}
              {% if singular == w %}
                {% matched = true %}
              {% end %}
            {% end %}
          {% end %}
          {% unless matched %}
            {% for rule in Altair::Inflector::SINGULAR_RULES %}
              {% unless matched %}
                {% gsubbed = singular.gsub(rule[0], rule[1]) %}
                {% if gsubbed != singular %}
                  {% singular = gsubbed %}
                  {% matched = true %}
                {% end %}
              {% end %}
            {% end %}
          {% end %}
          {% model = singular.camelcase %}
        {% end %}
        {% if polymorphic_type != "" && foreign_key.nil? %}
          {% fk = "#{polymorphic_type}_id".id %}
        {% elsif foreign_key %}
          {% fk = foreign_key.id %}
        {% else %}
          {% fk = "#{@type.name.id.underscore}_id".id %}
        {% end %}

        {% if through %}
          # Normalize through/source to MacroIds so `.stringify` emits clean
          # quoted literals — interpolating a StringLiteral node into a
          # macro string re-embeds its source quotes.
          {% through_node = through.id %}
          {% source_node = source ? source.id : singular.id %}

          @{{ assoc.id }} : Array({{ model.id }})?

          # The associated records through the join model, loaded lazily
          # via an INNER JOIN and cached. Inferred `source:` defaults to
          # the singular of the association name; pass `source:` explicitly
          # when the inference is ambiguous.
          def {{ assoc.id }} : Array({{ model.id }})
            @{{ assoc.id }} ||= if id = @id
              rows = [] of {{ model.id }}
              target_table = {{ model.id }}.table_name
              join_table = {{ through_node.stringify }}
              source_fk = {{ "#{source_node}_id".id.stringify }}
              through_fk = Altair::Inflector.singularize(TABLE_NAME) + "_id"
              sql = "SELECT DISTINCT #{connection.adapter.quote_identifier(target_table)}.* FROM #{connection.adapter.quote_identifier(target_table)} " \
                    "INNER JOIN #{connection.adapter.quote_identifier(join_table)} ON #{connection.adapter.quote_identifier(target_table)}.#{connection.adapter.quote_identifier("id")} = #{connection.adapter.quote_identifier(join_table)}.#{connection.adapter.quote_identifier(source_fk)} " \
                    "WHERE #{connection.adapter.quote_identifier(join_table)}.#{connection.adapter.quote_identifier(through_fk)} = #{connection.adapter.placeholder(0)} " \
                    "ORDER BY #{connection.adapter.quote_identifier(target_table)}.#{connection.adapter.quote_identifier("id")}"
              connection.query(sql, id) do |rs|
                rs.each { rows << {{ model.id }}.from_row(rs) }
              end
              rows
            else
              [] of {{ model.id }}
            end
          end

          # Sets the cached records during eager loading.
          protected def __set_preloaded_{{ assoc.id }}(children : Array({{ model.id }})) : Nil
            @{{ assoc.id }} = children
          end

          # Loads every associated record through the join table in one
          # batched query with an extra owner-id column for grouping.
          private def self.__load_{{ assoc.id }}(records : Array({{ @type.id }})) : Array({{ model.id }})
            ids = records.compact_map(&.id)
            return [] of {{ model.id }} if ids.empty?
            placeholders = ids.each_index.map { |index| connection.adapter.placeholder(index) }
            rows = [] of {{ model.id }}
            grouped = Hash(Int64, Array({{ model.id }})).new { |h, k| h[k] = [] of {{ model.id }} }
            target_table = {{ model.id }}.table_name
            join_table = {{ through_node.stringify }}
            source_fk = {{ "#{source_node}_id".id.stringify }}
            through_fk = Altair::Inflector.singularize(TABLE_NAME) + "_id"
            sql2 = "SELECT DISTINCT #{connection.adapter.quote_identifier(target_table)}.*, #{connection.adapter.quote_identifier(join_table)}.#{connection.adapter.quote_identifier(through_fk)} FROM #{connection.adapter.quote_identifier(target_table)} " \
                   "INNER JOIN #{connection.adapter.quote_identifier(join_table)} ON #{connection.adapter.quote_identifier(target_table)}.#{connection.adapter.quote_identifier("id")} = #{connection.adapter.quote_identifier(join_table)}.#{connection.adapter.quote_identifier(source_fk)} " \
                   "WHERE #{connection.adapter.quote_identifier(join_table)}.#{connection.adapter.quote_identifier(through_fk)} IN (#{placeholders.join(", ")}) " \
                   "ORDER BY #{connection.adapter.quote_identifier(target_table)}.#{connection.adapter.quote_identifier("id")}"
            connection.query(sql2, values: ids) do |rs|
              rs.each do
                model = {{ model.id }}.from_row(rs)
                owner_id = rs.read(Int64)
                grouped[owner_id] << model
                rows << model
              end
            end
            records.each do |record|
              record.__set_preloaded_{{ assoc.id }}(grouped[record.id.not_nil!.to_i64]? || [] of {{ model.id }})
            end
            rows.uniq
          end

          @@preloaders[:{{ assoc.id }}] = ->(records : Array(Altair::Record::Model)) do
            __load_{{ assoc.id }}(records.map(&.as({{ @type.id }}))).map(&.as(Altair::Record::Model))
          end

          @@association_metas[:{{ assoc.id }}] = {kind: :has_many_through, target_class: "{{ model.id }}", foreign_key: "{{ fk.id }}", through: {{ through_node.stringify }}, source: {{ source_node.stringify }}}
        {% else %}
          @{{ assoc.id }} : Array({{ model.id }})?

          # The associated records, loaded lazily in id order and cached.
          def {{ assoc.id }} : Array({{ model.id }})
            @{{ assoc.id }} ||= if id = @id
              rows = [] of {{ model.id }}
              {% if polymorphic_type != "" %}
              fk_name = {{ fk.stringify }}.gsub('"', "")
              type_col_name = {{ "#{polymorphic_type}_type".id.stringify }}.gsub('"', "")
              type_filter = " AND #{connection.adapter.quote_identifier(type_col_name)} = #{connection.adapter.placeholder(1)}"
              connection.query(
                "#{{{ model.id }}.select_sql} WHERE #{connection.adapter.quote_identifier(fk_name)} = #{connection.adapter.placeholder(0)}" + type_filter + " " \
                "ORDER BY #{connection.adapter.quote_identifier("id")}",
                id, "{{ @type.name }}"
              ) do |rs|
                rs.each { rows << {{ model.id }}.from_row(rs) }
              end
              {% else %}
              connection.query(
                "#{{{ model.id }}.select_sql} WHERE #{connection.adapter.quote_identifier({{ fk.stringify }})} = #{connection.adapter.placeholder(0)} " \
                "ORDER BY #{connection.adapter.quote_identifier("id")}",
                id
              ) do |rs|
                rs.each { rows << {{ model.id }}.from_row(rs) }
              end
              {% end %}
              rows
            else
              [] of {{ model.id }}
            end
          end

          # Sets the cached records during eager loading.
          protected def __set_preloaded_{{ assoc.id }}(children : Array({{ model.id }})) : Nil
            @{{ assoc.id }} = children
          end

          # Loads every associated record in one batched query, grouped by
          # foreign key, and returns the rows it read.
          private def self.__load_{{ assoc.id }}(records : Array({{ @type.id }})) : Array({{ model.id }})
            ids = records.compact_map(&.id)
            return [] of {{ model.id }} if ids.empty?
            rows = [] of {{ model.id }}
            grouped = Hash(Int64, Array({{ model.id }})).new { |h, k| h[k] = [] of {{ model.id }} }
            {% if polymorphic_type != "" %}
            fk_name = {{ fk.stringify }}.gsub('"', "")
            type_col_name = {{ "#{polymorphic_type}_type".id.stringify }}.gsub('"', "")
            type_col_q = connection.adapter.quote_identifier(type_col_name)
            fk_q = connection.adapter.quote_identifier(fk_name)
            pk_q = connection.adapter.quote_identifier("id")
            Altair::Record::Model.each_preload_chunk(ids) do |chunk|
              placeholders = chunk.each_index.map { |index| connection.adapter.placeholder(index + 1) }
              connection.query(
                "#{{{ model.id }}.select_sql} WHERE #{type_col_q} = #{connection.adapter.placeholder(0)} AND #{fk_q} IN (#{placeholders.join(", ")}) " \
                "ORDER BY #{pk_q}",
                values: ["{{ @type.name }}"] + chunk
              ) do |rs|
                rs.each do
                  row = {{ model.id }}.from_row(rs)
                  grouped[row.{{ fk.id.stringify.gsub(/"/, "").id }}.not_nil!.to_i64] << row
                  rows << row
                end
              end
            end
            {% else %}
            placeholders = ids.each_index.map { |index| connection.adapter.placeholder(index) }
            connection.query(
              "#{{{ model.id }}.select_sql} WHERE #{connection.adapter.quote_identifier({{ fk.stringify }})} " \
              "IN (#{placeholders.join(", ")}) ORDER BY #{connection.adapter.quote_identifier("id")}",
              values: ids
            ) do |rs|
              rs.each { rows << {{ model.id }}.from_row(rs) }
            end
            grouped = rows.group_by(&.{{ fk.id }})
            {% end %}
            records.each do |record|
              record.__set_preloaded_{{ assoc.id }}(grouped[record.id]? || [] of {{ model.id }})
            end
            rows
          end

          @@preloaders[:{{ assoc.id }}] = ->(records : Array(Altair::Record::Model)) do
            __load_{{ assoc.id }}(records.map(&.as({{ @type.id }}))).map(&.as(Altair::Record::Model))
          end

          @@association_metas[:{{ assoc.id }}] = {kind: :has_many, target_class: "{{ model.id }}", foreign_key: {{ fk.stringify }}, through: "", source: ""}

          {% if dependent && dependent.id.stringify == "destroy" && polymorphic_type != "" %}
            @@callbacks[:before_destroy] ||= [] of Proc({{ @type.id }}, Nil)
            @@callbacks[:before_destroy] << ->(record : {{ @type.id }}) { record.__destroy_{{ assoc.id }} }

            def __destroy_{{ assoc.id }} : Nil
              children = {{ assoc.id }}
              children.each(&.delete)
            end

            # Batched load keeps this one query per call — deletes then run
            # per child so their own callbacks still fire.
          {% elsif dependent && dependent.id.stringify == "nullify" && polymorphic_type != "" %}
            @@callbacks[:before_destroy] ||= [] of Proc({{ @type.id }}, Nil)
            @@callbacks[:before_destroy] << ->(record : {{ @type.id }}) { record.__nullify_{{ assoc.id }} }
            def __nullify_{{ assoc.id }} : Nil
              fk_name = {{ fk.stringify }}.gsub('"', "")
              type_col_name = {{ "#{polymorphic_type}_type".id.stringify }}.gsub('"', "")
              return unless id = @id
              connection.exec(
                "UPDATE #{connection.adapter.quote_identifier({{ model.id }}.table_name)} " \
                "SET #{connection.adapter.quote_identifier(fk_name)} = NULL, #{connection.adapter.quote_identifier(type_col_name)} = NULL " \
                "WHERE #{connection.adapter.quote_identifier(fk_name)} = #{connection.adapter.placeholder(0)} " \
                "AND #{connection.adapter.quote_identifier(type_col_name)} = #{connection.adapter.placeholder(1)}",
                id, "{{ @type.name }}"
              )
            end
          {% elsif dependent && dependent.id.stringify == "destroy" %}
            @@callbacks[:before_destroy] ||= [] of Proc({{ @type.id }}, Nil)
            @@callbacks[:before_destroy] << ->(record : {{ @type.id }}) { record.__destroy_{{ assoc.id }} }

            def __destroy_{{ assoc.id }} : Nil
              {{ assoc.id }}.each(&.delete)
            end
          {% elsif dependent && dependent.id.stringify == "delete_all" %}
            @@callbacks[:before_destroy] ||= [] of Proc({{ @type.id }}, Nil)
            @@callbacks[:before_destroy] << ->(record : {{ @type.id }}) { record.__delete_all_{{ assoc.id }} }

            def __delete_all_{{ assoc.id }} : Nil
              connection.exec(
                "DELETE FROM #{connection.adapter.quote_identifier({{ model.id }}.table_name)} " \
                "WHERE #{connection.adapter.quote_identifier({{ fk.stringify }})} = #{connection.adapter.placeholder(0)}",
                @id
              )
            end
          {% elsif dependent && dependent.id.stringify == "nullify" %}
            @@callbacks[:before_destroy] ||= [] of Proc({{ @type.id }}, Nil)
            @@callbacks[:before_destroy] << ->(record : {{ @type.id }}) { record.__nullify_{{ assoc.id }} }

            def __nullify_{{ assoc.id }} : Nil
              connection.exec(
                "UPDATE #{connection.adapter.quote_identifier({{ model.id }}.table_name)} " \
                "SET #{connection.adapter.quote_identifier({{ fk.stringify }})} = NULL " \
                "WHERE #{connection.adapter.quote_identifier({{ fk.stringify }})} = #{connection.adapter.placeholder(0)}",
                @id
              )
            end
          {% end %}
        {% end %}
      end

      # Declares a one-to-one association on the child side. The foreign
      # key column lives on the target table and is named after this
      # model; `dependent:` and `class_name:` behave like in `has_many`:
      #
      # ```
      # class User < Altair::Record::Model
      #   table :users
      #   has_one :profile, dependent: :nullify
      # end
      #
      # user.profile # the profile, or nil
      # ```
      macro has_one(name, class_name = nil, foreign_key = nil, dependent = nil)
        {% assoc = name.id %}
        {% model = class_name ? class_name.id : name.id.stringify.camelcase %}
        {% fk = foreign_key ? foreign_key.id : "#{@type.name.id.underscore}_id".id %}

        @{{ assoc.id }} : {{ model.id }}?

        # The associated record, loaded lazily and cached.
        def {{ assoc.id }} : {{ model.id }}?
          @{{ assoc.id }} ||= @id.try { |id| {{ model.id }}.find_by_{{ fk.id }}(id) }
        end

        # Sets the cached record during eager loading.
        protected def __set_preloaded_{{ assoc.id }}(related : {{ model.id }}?) : Nil
          @{{ assoc.id }} = related
        end

        # Loads every associated record in one batched query, grouped by
        # foreign key.
        # Loads every related record in one batched query and returns the
        # rows it read (empty when there was nothing to look up).
        private def self.__load_{{ assoc.id }}(records : Array({{ @type.id }})) : Array({{ model.id }})
          ids = records.compact_map(&.id)
          return [] of {{ model.id }} if ids.empty?
          placeholders = ids.each_index.map { |index| connection.adapter.placeholder(index) }
          rows = [] of {{ model.id }}
          connection.query(
            "#{{{ model.id }}.select_sql} WHERE #{connection.adapter.quote_identifier({{ fk.stringify }})} " \
            "IN (#{placeholders.join(", ")}) ORDER BY #{connection.adapter.quote_identifier("id")}",
            values: ids
          ) do |rs|
            rs.each { rows << {{ model.id }}.from_row(rs) }
          end
          grouped = rows.group_by(&.{{ fk.id }})
          records.each { |record| record.__set_preloaded_{{ assoc.id }}(grouped[record.id]?.try(&.first)) }
          rows
        end

        @@preloaders[:{{ assoc.id }}] = ->(records : Array(Altair::Record::Model)) do
          __load_{{ assoc.id }}(records.map(&.as({{ @type.id }}))).map(&.as(Altair::Record::Model))
        end

        @@association_metas[:{{ assoc.id }}] = {kind: :has_one, target_class: "{{ model.id }}", foreign_key: {{ fk.stringify }}, through: "", source: ""}

        {% if dependent && dependent.id.stringify == "destroy" %}
          @@callbacks[:before_destroy] ||= [] of Proc({{ @type.id }}, Nil)
          @@callbacks[:before_destroy] << ->(record : {{ @type.id }}) { record.__destroy_{{ assoc.id }} }

          def __destroy_{{ assoc.id }} : Nil
            {{ assoc.id }}.try(&.delete)
          end
        {% elsif dependent && dependent.id.stringify == "delete_all" %}
          @@callbacks[:before_destroy] ||= [] of Proc({{ @type.id }}, Nil)
          @@callbacks[:before_destroy] << ->(record : {{ @type.id }}) { record.__delete_all_{{ assoc.id }} }

          def __delete_all_{{ assoc.id }} : Nil
            connection.exec(
              "DELETE FROM #{connection.adapter.quote_identifier({{ model.id }}.table_name)} " \
              "WHERE #{connection.adapter.quote_identifier({{ fk.stringify }})} = #{connection.adapter.placeholder(0)}",
              @id
            )
          end
        {% elsif dependent && dependent.id.stringify == "nullify" %}
          @@callbacks[:before_destroy] ||= [] of Proc({{ @type.id }}, Nil)
          @@callbacks[:before_destroy] << ->(record : {{ @type.id }}) { record.__nullify_{{ assoc.id }} }

          def __nullify_{{ assoc.id }} : Nil
            connection.exec(
              "UPDATE #{connection.adapter.quote_identifier({{ model.id }}.table_name)} " \
              "SET #{connection.adapter.quote_identifier({{ fk.stringify }})} = NULL " \
              "WHERE #{connection.adapter.quote_identifier({{ fk.stringify }})} = #{connection.adapter.placeholder(0)}",
              @id
            )
          end
        {% end %}
      end
    end
  end
end
