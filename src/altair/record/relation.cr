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

      # Scopes the query with a comparison operator (`:>`, `:>=`, `:<`,
      # `:<=`, `:!=`):
      #
      # ```
      # Post.all.where(:views, :>=, 10)
      # ```
      def where(column : Symbol, operator : Symbol, value : Model::Value) : self
        raise ArgumentError.new("unsupported operator :#{operator}") unless {:<, :<=, :>, :>=, :!=}.includes?(operator)
        @where << "#{quoted_qualified(column.to_s)} #{operator} #{placeholder}"
        @binds << value
        self
      end

      # Scopes the query with a comparison operator on a string column
      # name:
      #
      # ```
      # Post.all.where("views", :>=, 10)
      # ```
      def where(column : String, operator : Symbol, value : Model::Value) : self
        raise ArgumentError.new("unsupported operator :#{operator}") unless {:<, :<=, :>, :>=, :!=}.includes?(operator)
        @where << "#{quoted_qualified(column)} #{operator} #{placeholder}"
        @binds << value
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
      # `order`, `limit` and `offset` do not affect the count.
      def count : Int64
        if records = @records
          records.size.to_i64
        else
          table = T.connection.adapter.quote_identifier(T.table_name)
          pk = T.connection.adapter.quote_identifier(T.primary_key_name)
          sql = if @distinct || !@joins.empty?
                  "SELECT COUNT(DISTINCT #{table}.#{pk}) FROM #{table}#{join_sql}"
                else
                  "SELECT COUNT(*) FROM #{table}"
                end
          sql += " WHERE #{@where.join(" AND ")}" unless @where.empty?
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
      #   post.touch
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

      private def build_join(association : Symbol, join_type : String) : String
        meta = T.__association_meta_for(association)
        owner_table = T.table_name
        owner_quoted = T.connection.adapter.quote_identifier(owner_table)
        pk_quoted = T.connection.adapter.quote_identifier("id")
        if meta[:kind] == :has_many_through
          through_table = T.connection.adapter.quote_identifier(meta[:through].to_s)
          source_fk = T.connection.adapter.quote_identifier(meta[:source] + "_id")
          through_fk = T.connection.adapter.quote_identifier(Altair::Inflector.underscore(T.name) + "_id")
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
