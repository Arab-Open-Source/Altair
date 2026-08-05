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
      @preloaders = [] of Proc(Array(T), Nil)
      @where = [] of String
      @binds = [] of Model::Value
      @order : String?
      @limit : Int32?
      @offset : Int32?

      # Iterates the records, running the query on first access.
      def each(& : T ->) : Nil
        to_a.each { |record| yield record }
      end

      # Materializes the records, running the scheduled eager loads.
      def to_a : Array(T)
        @records ||= begin
          rows = [] of T
          T.connection.query(T.select_sql + clause_sql, values: @binds) do |rs|
            rs.each { rows << T.from_row(rs) }
          end
          @preloaders.each(&.call(rows))
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

      # Yields every record in bounded batches ordered by primary key,
      # running one query per batch. Unlike `to_a`, memory stays bounded
      # regardless of the table size.
      #
      # ```
      # Post.all.find_each do |post|
      #   post.touch
      # end
      # ```
      def find_each(batch_size : Int32 = 64, &block : T ->) : Nil
        pk = T.primary_key_name
        last_id = nil
        loop do
          scoped = Relation(T).new
          scoped.order(pk, :asc).limit(batch_size)
          scoped.where(pk, :>, last_id) if last_id
          batch = scoped.to_a
          break if batch.empty?
          batch.each(&block)
          last_id = batch.last.id.not_nil!.to_i64
        end
      end

      # Schedules eager loading of the given associations — one batched
      # query per association regardless of the number of records. Raises
      # for an association the model does not declare:
      #
      # ```
      # Post.all.includes(:comments)
      # ```
      def includes(*associations : Symbol) : self
        associations.each do |name|
          @preloaders << T.__preloader_for(name)
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
