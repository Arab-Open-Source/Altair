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
      @order : String?
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
        @order = other.@order if other.@order
        @limit = other.@limit if other.@limit
        @offset = other.@offset if other.@offset
        other.@preloaders.each { |preloader| @preloaders << preloader }
        self
      end

      # Materializes the records, running the scheduled eager loads.
      def to_a : Array(T)
        @records ||= begin
          rows = [] of T
          T.connection.query(T.select_sql + clause_sql, values: @binds) do |rs|
            rs.each { rows << T.from_row(rs) }
          end
          unless @preloaders.empty?
            model_rows = rows.map(&.as(Altair::Record::Model))
            @preloaders.each(&.call(model_rows))
          end
          rows
        end
      end

      # Scopes the query to the rows where `column` equals the value:
      #
      # ```
      # Post.all.where(title: "Hello")
      # Post.all.where(published: true)
      # ```
      def where(column : Symbol, value : Model::Value) : self
        @where << "#{quoted(column)} = #{placeholder}"
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
          @where << "#{quoted(column.to_s)} = #{placeholder}"
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
        @where << "#{quoted(column.to_s)} #{operator} #{placeholder}"
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
        @where << "#{quoted(column)} #{operator} #{placeholder}"
        @binds << value
        self
      end

      # Orders the rows by a column, ascending by default:
      #
      # ```
      # Post.all.order(:created_at, :desc)
      # ```
      def order(column : Symbol | String, direction : Symbol = :asc) : self
        @order = "ORDER BY #{quoted(column.to_s)} #{direction == :desc ? "DESC" : "ASC"}"
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
          sql = "SELECT COUNT(*) FROM #{T.connection.adapter.quote_identifier(T.table_name)}"
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
        last_id = nil
        loop do
          scoped = scoped_state
          scoped.order(pk, :asc).limit(batch_size + 1)
          scoped.where(pk, :>, last_id) if last_id
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
        Relation(T).new.adopt_state(@where.dup, @binds.dup, @preloaders.dup)
      end

      # Copies the scoped state of another relation onto this one.
      protected def adopt_state(where : Array(String), binds : Array(Model::Value),
                                preloaders : Array(Proc(Array(Altair::Record::Model), Array(Altair::Record::Model)))) : self
        @where = where
        @binds = binds
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
        parts << @order.not_nil! if @order
        if @limit || @offset
          parts << T.connection.adapter.limit_offset_clause(@limit, @offset)
        end
        parts.empty? ? "" : " " + parts.join(" ")
      end

      private def quoted(name : String) : String
        T.connection.adapter.quote_identifier(name)
      end

      private def placeholder : String
        T.connection.adapter.placeholder(@binds.size)
      end
    end
  end
end
