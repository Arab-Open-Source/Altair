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
      macro belongs_to(name, class_name = nil, foreign_key = nil)
        {% assoc = name.id %}
        {% model = class_name ? class_name.id : name.id.stringify.camelcase %}
        {% fk = foreign_key ? foreign_key.id : "#{name.id}_id" %}

        @{{ assoc.id }} : {{ model.id }}?

        # The associated record, loaded lazily and cached.
        def {{ assoc.id }} : {{ model.id }}?
          @{{ assoc.id }} ||= @{{ fk.id }}.try { |id| {{ model.id }}.find(id) }
        end

        # Assigns the associated record and its foreign key.
        def {{ assoc.id }}=(owner : {{ model.id }}?) : Nil
          @{{ assoc.id }} = owner
          @{{ fk.id }} = owner.try(&.id)
        end

        # Sets the cached record during eager loading.
        protected def __set_preloaded_{{ assoc.id }}(owner : {{ model.id }}?) : Nil
          @{{ assoc.id }} = owner
        end

        # Loads every associated record in one batched query, grouped by
        # foreign key.
        private def self.__load_{{ assoc.id }}(records : Array({{ @type.id }})) : Nil
          ids = records.compact_map(&.{{ fk.id }}).uniq
          return if ids.empty?
          placeholders = ids.each_index.map { |index| connection.adapter.placeholder(index) }
          rows = [] of {{ model.id }}
          connection.query(
            "#{{{ model.id }}.select_sql} WHERE #{connection.adapter.quote_identifier("id")} " \
            "IN (#{placeholders.join(", ")})",
            values: ids
          ) do |rs|
            rs.each { rows << {{ model.id }}.from_row(rs) }
          end
          by_id = rows.to_h { |owner| {owner.id.not_nil!, owner} }
          records.each { |record| record.__set_preloaded_{{ assoc.id }}(by_id[record.{{ fk.id }}]?) }
        end

        @@preloaders[:{{ assoc.id }}] = ->(records : Array({{ @type.id }})) { __load_{{ assoc.id }}(records) }
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
      macro has_many(name, class_name = nil, foreign_key = nil, dependent = nil)
        {% assoc = name.id %}
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
        {% fk = foreign_key ? foreign_key.id : "#{@type.name.id.underscore}_id" %}

        @{{ assoc.id }} : Array({{ model.id }})?

        # The associated records, loaded lazily in id order and cached.
        def {{ assoc.id }} : Array({{ model.id }})
          @{{ assoc.id }} ||= if id = @id
            rows = [] of {{ model.id }}
            connection.query(
              "#{{{ model.id }}.select_sql} WHERE #{connection.adapter.quote_identifier("{{ fk.id }}")} = #{connection.adapter.placeholder(0)} " \
              "ORDER BY #{connection.adapter.quote_identifier("id")}",
              id
            ) do |rs|
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

        # Loads every associated record in one batched query, grouped by
        # foreign key.
        private def self.__load_{{ assoc.id }}(records : Array({{ @type.id }})) : Nil
          ids = records.compact_map(&.id)
          return if ids.empty?
          placeholders = ids.each_index.map { |index| connection.adapter.placeholder(index) }
          rows = [] of {{ model.id }}
          connection.query(
            "#{{{ model.id }}.select_sql} WHERE #{connection.adapter.quote_identifier("{{ fk.id }}")} " \
            "IN (#{placeholders.join(", ")}) ORDER BY #{connection.adapter.quote_identifier("id")}",
            values: ids
          ) do |rs|
            rs.each { rows << {{ model.id }}.from_row(rs) }
          end
          grouped = rows.group_by(&.{{ fk.id }})
          records.each do |record|
            record.__set_preloaded_{{ assoc.id }}(grouped[record.id]? || [] of {{ model.id }})
          end
        end

        @@preloaders[:{{ assoc.id }}] = ->(records : Array({{ @type.id }})) { __load_{{ assoc.id }}(records) }

        {% if dependent && dependent.id.stringify == "destroy" %}
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
              "WHERE #{connection.adapter.quote_identifier("{{ fk.id }}")} = #{connection.adapter.placeholder(0)}",
              @id
            )
          end
        {% elsif dependent && dependent.id.stringify == "nullify" %}
          @@callbacks[:before_destroy] ||= [] of Proc({{ @type.id }}, Nil)
          @@callbacks[:before_destroy] << ->(record : {{ @type.id }}) { record.__nullify_{{ assoc.id }} }

          def __nullify_{{ assoc.id }} : Nil
            connection.exec(
              "UPDATE #{connection.adapter.quote_identifier({{ model.id }}.table_name)} " \
              "SET #{connection.adapter.quote_identifier("{{ fk.id }}")} = NULL " \
              "WHERE #{connection.adapter.quote_identifier("{{ fk.id }}")} = #{connection.adapter.placeholder(0)}",
              @id
            )
          end
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
        {% fk = foreign_key ? foreign_key.id : "#{@type.name.id.underscore}_id" %}

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
        private def self.__load_{{ assoc.id }}(records : Array({{ @type.id }})) : Nil
          ids = records.compact_map(&.id)
          return if ids.empty?
          placeholders = ids.each_index.map { |index| connection.adapter.placeholder(index) }
          rows = [] of {{ model.id }}
          connection.query(
            "#{{{ model.id }}.select_sql} WHERE #{connection.adapter.quote_identifier("{{ fk.id }}")} " \
            "IN (#{placeholders.join(", ")}) ORDER BY #{connection.adapter.quote_identifier("id")}",
            values: ids
          ) do |rs|
            rs.each { rows << {{ model.id }}.from_row(rs) }
          end
          grouped = rows.group_by(&.{{ fk.id }})
          records.each { |record| record.__set_preloaded_{{ assoc.id }}(grouped[record.id]?.try(&.first)) }
        end

        @@preloaders[:{{ assoc.id }}] = ->(records : Array({{ @type.id }})) { __load_{{ assoc.id }}(records) }

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
              "WHERE #{connection.adapter.quote_identifier("{{ fk.id }}")} = #{connection.adapter.placeholder(0)}",
              @id
            )
          end
        {% elsif dependent && dependent.id.stringify == "nullify" %}
          @@callbacks[:before_destroy] ||= [] of Proc({{ @type.id }}, Nil)
          @@callbacks[:before_destroy] << ->(record : {{ @type.id }}) { record.__nullify_{{ assoc.id }} }

          def __nullify_{{ assoc.id }} : Nil
            connection.exec(
              "UPDATE #{connection.adapter.quote_identifier({{ model.id }}.table_name)} " \
              "SET #{connection.adapter.quote_identifier("{{ fk.id }}")} = NULL " \
              "WHERE #{connection.adapter.quote_identifier("{{ fk.id }}")} = #{connection.adapter.placeholder(0)}",
              @id
            )
          end
        {% end %}
      end
    end
  end
end
