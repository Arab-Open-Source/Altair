# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Record::Relation`, the lazy query result
# `Model.all` returns. The query runs on first iteration; `includes`
# schedules the batched eager loading of associations before the records
# are materialized, so loading many records never degrades into one query
# per record. `where`, `order`, `limit` and `offset` scope the query with
# bound parameters, and `find_each` streams rows in bounded batches.
module Altair
  module Record
    # A lazy collection of records. Iterating runs the query once and
    # caches the rows; `includes` schedules batched eager loading of the
    # given associations, executed before the first iteration.
    class Relation(T)
      include Enumerable(T)

      @records : Array(T)?
      @preloaders = [] of Proc(Array(Altair::Record::Model), Array(Altair::Record::Model))
      @where = [] of String
      @binds = [] of Model::Value
      @joins = [] of String
      @distinct = false
      @orders = [] of String
      @limit : Int32?
      @offset : Int32?

      # Iterates the records, running the query on first access.
      def each(& : T ->) : Nil
        to_a.each { |record| yield record }
      end

      # Combines another relation's scope into this one: their `where`
      # clauses AND together (binds included), and an `order`, `limit` or
      # `offset` on `other` replaces the one here. This is how two scopes
      # compose — Crystal has no dynamic dispatch, so
      # `Post.published.merge(Post.popular)` is the chaining form:
      #
      # ```
      # Post.published.merge(Post.popular).to_a
      # ```
      def merge(other : self) : self
        @where.concat(other.@where)
        @binds.concat(other.@binds)
        @joins.concat(other.@joins)
        @distinct = true if other.@distinct
        @orders.concat(other.@orders)
        @limit = other.@limit if other.@limit
        @offset = other.@offset if other.@offset
        other.@preloaders.each { |preloader| @preloaders << preloader }
        self
      end

      # Materializes the records, running the scheduled eager loads.
      def to_a : Array(T)
        @records ||= begin
          rows = [] of T
          sql = select_sql_with_distinct + join_sql + clause_sql
          T.connection.query(sql, values: @binds) do |rs|
            rs.each { rows << T.from_row(rs) }
          end
          unless @preloaders.empty?
            model_rows = rows.map(&.as(Altair::Record::Model))
            @preloaders.each(&.call(model_rows))
          end
          rows
        end
      end

      # Adds an INNER JOIN for each association:
      #
      # ```
      # Post.all.joins(:comments).where("comments.body": "hi")
      # ```
      def joins(*associations : Symbol) : self
        associations.each do |assoc|
          @joins << build_join(assoc, "INNER JOIN")
          @distinct = true if association_needs_distinct?(assoc)
        end
        self
      end

      # Adds a LEFT OUTER JOIN for each association.
      def left_joins(*associations : Symbol) : self
        associations.each do |assoc|
          @joins << build_join(assoc, "LEFT OUTER JOIN")
        end
        self
      end

      # Clears the cached records so the next access re-runs the query.
      def reload : self
        @records = nil
        self
      end

      # Ensures the result contains no duplicate rows. Automatically
      # enabled by `joins` on `has_many` associations.
      def distinct : self
        @distinct = true
        self
      end

      # Whether this relation will use `SELECT DISTINCT`.
      def distinct? : Bool
        @distinct
      end

      # Scopes the query to the rows where `column` equals the value:
      #
      # ```
      # Post.all.where(title: "Hello")
      # Post.all.where(published: true)
      # ```
      def where(column : Symbol, value : Model::Value) : self
        @where << "#{quoted_qualified(column.to_s)} = #{placeholder}"
        @binds << value
        self
      end

      # Scopes the query to the rows where a qualified column equals the
      # value:
      #
      # ```
      # Post.all.joins(:comments).where("comments.body", "hi")
      # ```
      def where(column : String, value : Model::Value) : self
        @where << "#{quoted_qualified(column)} = #{placeholder}"
        @binds << value
        self
      end

      # Scopes the query to the rows matching every keyword pair:
      #
      # ```
      # Post.all.where(title: "Hello", published: true)
      # ```
      def where(**pairs) : self
        pairs.each do |column, value|
          @where << "#{quoted_qualified(column.to_s)} = #{placeholder}"
          @binds << value
        end
        self
      end

      # Scopes the query with a comparison or pattern operator (`:>`,
      # `:>=`, `:<`, `:<=`, `:!=`, `:like`):
      #
      # ```
      # Post.all.where(:views, :>=, 10)
      # Post.all.where(:title, :like, "%altair%")
      # ```
      def where(column : Symbol, operator : Symbol, value : Model::Value) : self
        clause, bind = operator_condition(quoted_qualified(column.to_s), operator, value)
        @where << clause
        @binds << bind
        self
      end

      # Scopes the query with a comparison operator on a string column
      # name:
      #
      # ```
      # Post.all.where("views", :>=, 10)
      # ```
      def where(column : String, operator : Symbol, value : Model::Value) : self
        clause, bind = operator_condition(quoted_qualified(column), operator, value)
        @where << clause
        @binds << bind
        self
      end

      # Excludes rows matching every keyword pair:
      #
      # ```
      # Post.all.where_not(published: true)
      # ```
      def where_not(**pairs) : self
        pairs.each do |column, value|
          @where << "NOT (#{quoted_qualified(column.to_s)} = #{placeholder})"
          @binds << value
        end
        self
      end

      # Excludes the rows where a column equals the value.
      def where_not(column : Symbol | String, value : Model::Value) : self
        @where << "NOT (#{quoted_qualified(column.to_s)} = #{placeholder})"
        @binds << value
        self
      end

      # Adds alternatives to the most recent condition instead of
      # ANDing with the whole scope — every keyword pair becomes an OR
      # branch folded into the preceding clause:
      #
      # ```
      # Post.all.where(views: 30).or_where(views: 45)
      # # WHERE (views = ? OR views = ?)
      # ```
      def or_where(**pairs) : self
        clauses = [] of String
        pairs.each do |column, value|
          clauses << "#{quoted_qualified(column.to_s)} = #{placeholder}"
          @binds << value
        end
        fold_alternatives(clauses.join(" OR "))
        self
      end

      # Adds an alternative to the most recent condition.
      def or_where(column : Symbol | String, value : Model::Value) : self
        group = "#{quoted_qualified(column.to_s)} = #{placeholder}"
        @binds << value
        fold_alternatives(group)
        self
      end

      # Adds an alternative comparison (`:>`, `:>=`, `:<`, `:<=`, `:!=`,
      # `:like`) to the most recent condition.
      def or_where(column : Symbol | String, operator : Symbol, value : Model::Value) : self
        clause, bind = operator_condition(quoted_qualified(column.to_s), operator, value)
        @binds << bind
        fold_alternatives(clause)
        self
      end

      # Scopes the query with an operator that needs no bound value:
      # `:null` / `:not_null`.
      #
      # ```
      # Post.all.where(:user_id, :null)
      # ```
      def where(column : Symbol | String, operator : Symbol) : self
        @where << null_condition(quoted_qualified(column.to_s), operator)
        self
      end

      # Filters membership in a bound list:
      #
      # ```
      # Post.all.where(:views, :in, [3, 12])
      # ```
      # An empty list matches nothing without touching the database's
      # variable limit.
      def where(column : Symbol | String, operator : Symbol, values : Array(Model::Value)) : self
        raise ArgumentError.new(":in is the only list operator") unless operator == :in
        clause, binds = membership_condition(quoted_qualified(column.to_s), values)
        @where << clause
        @binds.concat(binds)
        self
      end

      # Orders the rows by a column, ascending by default:
      #
      # ```
      # Post.all.order(:created_at, :desc)
      # ```
      def order(column : Symbol | String, direction : Symbol = :asc) : self
        @orders << "#{quoted_qualified(column.to_s)} #{direction == :desc ? "DESC" : "ASC"}"
        self
      end

      # Replaces all existing `ORDER BY` clauses:
      #
      # ```
      # Post.all.order(:created_at).reorder(:title) # ORDER BY title only
      # ```
      def reorder(column : Symbol | String, direction : Symbol = :asc) : self
        @orders.clear
        order(column, direction)
      end

      # Removes all `ORDER BY` clauses.
      def unscope_order : self
        @orders.clear
        self
      end

      # Limits the number of rows returned.
      def limit(limit : Int32) : self
        @limit = limit
        self
      end

      # Offsets the number of rows skipped.
      def offset(offset : Int32) : self
        @offset = offset
        self
      end

      # The number of rows the scoped query returns, without materializing
      # them. Uses the cached records once the relation has been loaded.
      # `limit` and `offset` bound what is counted, so a bounded relation
      # counts exactly the rows `to_a` would return.
      def count : Int64
        if records = @records
          records.size.to_i64
        else
          adapter = T.connection.adapter
          table = adapter.quote_identifier(T.table_name)
          pk = adapter.quote_identifier(T.primary_key_name)
          collapse = @distinct || !@joins.empty?
          inner = String.build do |sql|
            sql << "SELECT "
            if collapse
              sql << "DISTINCT #{table}.#{pk} "
            else
              sql << "1 "
            end
            sql << "FROM #{table}#{join_sql}"
            sql << " WHERE #{@where.join(" AND ")}" unless @where.empty?
            if @limit || @offset
              sql << " ORDER BY #{@orders.join(", ")}" unless @orders.empty?
              sql << " #{adapter.limit_offset_clause(@limit, @offset)}"
            end
          end
          sql = "SELECT COUNT(*) FROM (#{inner}) AS altair_count"
          count = 0_i64
          T.connection.query(sql, values: @binds) do |rs|
            rs.move_next
            count = rs.read(Int64)
          end
          count
        end
      end

      # The number of records: the cached rows once loaded, otherwise a
      # `COUNT(*)` query — never materializes the table.
      def size : Int32
        count.to_i32
      end

      # Yields every record in bounded batches ordered by primary key,
      # running one query per batch, fetching one extra row per batch to
      # detect the end of the scan. Unlike `to_a`, memory stays bounded
      # regardless of the table size. The scoped `where` filters, bound
      # values and `includes` preloaders carry over to every batch.
      #
      # ```
      # Post.all.where(published: true).includes(:comments).find_each do |post|
      #   post.update(views: post.views + 1)
      # end
      # ```
      def find_each(batch_size : Int32 = 64, &block : T ->) : Nil
        pk = T.primary_key_name
        qualified_pk = "#{T.table_name}.#{pk}"
        last_id = nil
        loop do
          scoped = scoped_state
          scoped.order(qualified_pk, :asc).limit(batch_size + 1)
          scoped.where(qualified_pk, :>, last_id) if last_id
          rows = scoped.to_a
          break if rows.empty?
          more = rows.size > batch_size
          rows = rows.first(batch_size) if more
          rows.each(&block)
          break unless more
          last_id = rows.last.id.not_nil!.to_i64
        end
      end

      # The first scoped row, primary key ascending unless the scope
      # already orders. Raises `RecordNotFound` when the scope is empty:
      #
      # ```
      # Post.all.where(published: true).first
      # ```
      def first : T
        first? || raise RecordNotFound.new("Couldn't find #{T.table_name} with that scope")
      end

      # The first scoped row, or `nil` when the scope is empty.
      def first? : T?
        scoped_state.order(qualified_pk, :asc).limit(1).to_a.first?
      end

      # The last scoped row: the scope's explicit ordering reversed, or
      # primary key descending when unordered. Raises `RecordNotFound`
      # when the scope is empty.
      def last : T
        last? || raise RecordNotFound.new("Couldn't find #{T.table_name} with that scope")
      end

      # The last scoped row, or `nil` when the scope is empty.
      def last? : T?
        flipped = flip_orders
        scoped_state
          .assign_orders(flipped.empty? ? ["#{qualified_pk} DESC"] : flipped)
          .limit(1).to_a.first?
      end

      # The first `count` scoped rows without changing their order.
      def take(count : Int32) : Array(T)
        scoped_state.limit(count).to_a
      end

      # The scoped primary keys, honoring order and bounds.
      #
      # ```
      # Post.all.where(published: true).ids
      # ```
      def ids : Array(Model::Value)
        adapter = T.connection.adapter
        scalar_values(
          "#{adapter.quote_identifier(T.table_name)}.#{adapter.quote_identifier(T.primary_key_name)}",
          limit_to_one: false
        )
      end

      # A single column value from the leading scoped row, honoring
      # order — `nil` when the scope matches nothing.
      #
      # ```
      # Post.all.order(:views).pick(:title)
      # ```
      def pick(column : Symbol | String) : Model::Value?
        scalar_values(quoted_qualified(column.to_s), limit_to_one: true).first?
      end

      # Whether the scope matches at least one row — a `SELECT 1 ... LIMIT 1`
      # probe, never a materialization.
      def exists? : Bool
        sql = "SELECT 1 FROM #{T.connection.adapter.quote_identifier(T.table_name)}"
        sql += " WHERE #{@where.join(" AND ")}" unless @where.empty?
        sql += " LIMIT 1"
        found = false
        T.connection.query(sql, values: @binds) do |rs|
          found = rs.move_next
        end
        found
      end

      # Whether the scope matches at least one row.
      def any? : Bool
        exists?
      end

      # Whether the scope matches no rows.
      def none? : Bool
        !exists?
      end

      # Updates every scoped row in one `UPDATE` statement and returns
      # the number of rows changed. Callbacks, validations and timestamps
      # are bypassed — this writes columns directly. Joins cannot carry
      # into an `UPDATE` and raise; `order`, `limit` and `offset` have no
      # portable meaning across engines and are ignored.
      #
      # ```
      # Post.all.where(published: false).update_all(published: true)
      # ```
      def update_all(**fields) : Int64
        raise ArgumentError.new("update_all does not support joined relations") unless @joins.empty?
        raise ArgumentError.new("update_all requires at least one field") if fields.empty?
        assignments = [] of String
        binds = [] of Model::Value
        fields.each do |column, value|
          assignments << "#{T.connection.adapter.quote_identifier(column.to_s)} = #{placeholder_for(binds)}"
          binds << value
        end
        sql = String.build do |part|
          part << "UPDATE #{T.connection.adapter.quote_identifier(T.table_name)} SET #{assignments.join(", ")}"
          part << " WHERE #{@where.join(" AND ")}" unless @where.empty?
        end
        T.connection.exec(sql, args: binds + @binds).rows_affected
      end

      # Deletes every scoped row in one `DELETE` statement and returns
      # the number of rows removed. Destroy callbacks and dependent
      # associations are bypassed — rows go without ceremony. Joins,
      # `order`, `limit` and `offset` raise or are ignored exactly as in
      # `update_all`.
      #
      # ```
      # Post.all.where(published: false).delete_all
      # ```
      def delete_all : Int64
        raise ArgumentError.new("delete_all does not support joined relations") unless @joins.empty?
        sql = "DELETE FROM #{T.connection.adapter.quote_identifier(T.table_name)}"
        sql += " WHERE #{@where.join(" AND ")}" unless @where.empty?
        T.connection.exec(sql, args: @binds).rows_affected
      end

      # A fresh relation carrying this relation's scoped filters, bound
      # values and scheduled preloaders, used by `find_each` batches.
      private def scoped_state : Relation(T)
        Relation(T).new.adopt_state(@where.dup, @binds.dup, @joins.dup, @distinct, @orders.dup, @preloaders.dup)
      end

      # Copies the scoped state of another relation onto this one.
      protected def adopt_state(where : Array(String), binds : Array(Model::Value),
                                joins : Array(String), distinct : Bool, orders : Array(String),
                                preloaders : Array(Proc(Array(Altair::Record::Model), Array(Altair::Record::Model)))) : self
        @where = where
        @binds = binds
        @joins = joins
        @distinct = distinct
        @orders = orders
        @preloaders = preloaders
        self
      end

      # Replaces this relation's order clauses (used by `last?` to run
      # the scope reversed).
      protected def assign_orders(orders : Array(String)) : self
        @orders = orders
        self
      end

      # Every order clause with its direction flipped.
      private def flip_orders : Array(String)
        @orders.map do |clause|
          if clause.upcase.ends_with?(" DESC")
            "#{clause[0...-5]} ASC"
          elsif clause.upcase.ends_with?(" ASC")
            "#{clause[0...-4]} DESC"
          else
            "#{clause} DESC"
          end
        end
      end

      # Schedules eager loading of the given associations — one batched
      # query per association regardless of the number of records. Raises
      # for an association the model does not declare:
      #
      # ```
      # Post.all.includes(:comments)
      # ```
      # Schedules batched eager loading of the given associations before
      # the first iteration. Plain names load one level:
      #
      # ```
      # Post.all.includes(:comments).to_a
      # ```
      #
      # Named pairs nest further, applying each subsequent level to the
      # rows the previous one loaded — still one batched query per level,
      # never per record. Nesting recurses through NamedTuple values too
      # (`includes(posts: {comments: :post})`).
      def includes(*associations, **nested) : self
        associations.each do |name|
          @preloaders << T.__preloader_for(name)
        end
        nested.each do |name, sub_spec|
          base = T.__preloader_for(name)
          @preloaders << ->(records : Array(Altair::Record::Model)) do
            children = base.call(records)
            Altair::Record.__apply_nested(children, sub_spec) unless children.empty?
            children
          end
        end
        self
      end

      private def clause_sql : String
        parts = [] of String
        parts << "WHERE #{@where.join(" AND ")}" unless @where.empty?
        parts << "ORDER BY #{@orders.join(", ")}" unless @orders.empty?
        if @limit || @offset
          parts << T.connection.adapter.limit_offset_clause(@limit, @offset)
        end
        parts.empty? ? "" : " " + parts.join(" ")
      end

      private def join_sql : String
        @joins.empty? ? "" : " " + @joins.join(" ")
      end

      private def effective_select_sql : String
        if @joins.empty?
          @distinct ? T.select_sql.sub("SELECT", "SELECT DISTINCT") : T.select_sql
        else
          table = T.connection.adapter.quote_identifier(T.table_name)
          cols = T.column_names.map { |col| "#{table}.#{T.connection.adapter.quote_identifier(col)}" }.join(", ")
          @distinct ? "SELECT DISTINCT #{cols} FROM #{table}" : "SELECT #{cols} FROM #{table}"
        end
      end

      private def select_sql_with_distinct : String
        effective_select_sql
      end

      private def quoted(name : String) : String
        quoted_qualified(name)
      end

      private def quoted_qualified(name : String) : String
        name.split(".").map { |part| T.connection.adapter.quote_identifier(part) }.join(".")
      end

      private def placeholder : String
        T.connection.adapter.placeholder(@binds.size)
      end

      private def placeholder_for(binds : Array(Model::Value)) : String
        T.connection.adapter.placeholder(binds.size)
      end

      private def operator_condition(qualified : String, operator : Symbol, value : Model::Value) : Tuple(String, Model::Value)
        case operator
        when :like
          {"#{qualified} LIKE #{placeholder}", value}
        when :<, :<=, :>, :>=, :!=
          {"#{qualified} #{operator} #{placeholder}", value}
        else
          raise ArgumentError.new("unsupported operator :#{operator}")
        end
      end

      private def null_condition(qualified : String, operator : Symbol) : String
        case operator
        when :null     then "#{qualified} IS NULL"
        when :not_null then "#{qualified} IS NOT NULL"
        else
          raise ArgumentError.new("unsupported operator :#{operator}")
        end
      end

      private def membership_condition(qualified : String, values : Array(Model::Value)) : Tuple(String, Array(Model::Value))
        # A fresh, explicitly-typed list: the incoming array arrives
        # narrowed to the caller's literal element type, which would
        # violate the declared return type.
        binds = [] of Model::Value
        values.each { |value| binds << value }
        marks = binds.map { placeholder }.join(", ")
        {"#{qualified} IN (#{marks})", binds}
      end

      # Folds an OR group into the most recent condition — `(last OR
      # group)` — so alternatives extend one clause instead of ANDing
      # against the entire scope. Bind order is preserved: existing
      # placeholders keep their indices, the new ones append.
      private def fold_alternatives(group : String) : Nil
        if @where.empty?
          @where << "(#{group})"
        else
          last = @where.pop
          @where << "(#{last} OR #{group})"
        end
      end

      private def qualified_pk : String
        "#{T.table_name}.#{T.primary_key_name}"
      end

      private def scalar_values(select_expr : String, limit_to_one : Bool) : Array(Model::Value)
        adapter = T.connection.adapter
        sql = String.build do |part|
          part << "SELECT #{select_expr} FROM #{adapter.quote_identifier(T.table_name)}"
          part << " WHERE #{@where.join(" AND ")}" unless @where.empty?
          part << " ORDER BY #{@orders.join(", ")}" unless @orders.empty?
          if limit_to_one
            part << " LIMIT 1"
          elsif @limit || @offset
            part << " #{adapter.limit_offset_clause(@limit, @offset)}"
          end
        end
        values = [] of Model::Value
        T.connection.query(sql, values: @binds) do |rs|
          rs.each { values << rs.read(Model::Value) }
        end
        values
      end

      private def build_join(association : Symbol, join_type : String) : String
        meta = T.__association_meta_for(association)
        owner_table = T.table_name
        owner_quoted = T.connection.adapter.quote_identifier(owner_table)
        pk_quoted = T.connection.adapter.quote_identifier("id")
        if meta[:kind] == :has_many_through
          through_table = T.connection.adapter.quote_identifier(meta[:through].to_s)
          source_fk = T.connection.adapter.quote_identifier(meta[:source] + "_id")
          through_fk = T.connection.adapter.quote_identifier(Altair::Inflector.singularize(T::TABLE_NAME) + "_id")
          target_table = Altair::Inflector.tableize(Altair::Inflector.underscore(meta[:target_class]))
          target_quoted = T.connection.adapter.quote_identifier(target_table)
          "#{join_type} #{through_table} ON #{through_table}.#{through_fk} = #{owner_quoted}.#{pk_quoted} " \
          "#{join_type} #{target_quoted} ON #{target_quoted}.#{pk_quoted} = #{through_table}.#{source_fk}"
        else
          target_table = Altair::Inflector.tableize(Altair::Inflector.underscore(meta[:target_class]))
          target_quoted = T.connection.adapter.quote_identifier(target_table)
          fk_quoted = T.connection.adapter.quote_identifier(meta[:foreign_key].to_s)
          if meta[:kind] == :belongs_to
            "#{join_type} #{target_quoted} ON #{target_quoted}.#{pk_quoted} = #{owner_quoted}.#{fk_quoted}"
          else
            "#{join_type} #{target_quoted} ON #{target_quoted}.#{fk_quoted} = #{owner_quoted}.#{pk_quoted}"
          end
        end
      end

      private def association_needs_distinct?(association : Symbol) : Bool
        meta = T.__association_meta_for(association)
        meta[:kind] == :has_many || meta[:kind] == :has_many_through
      end
    end
  end
end
