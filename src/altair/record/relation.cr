# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Record::Relation`, the lazy query result
# `Model.all` returns. The query runs on first iteration; `includes`
# schedules the batched eager loading of associations before the records
# are materialized, so loading many records never degrades into one query
# per record.
module Altair
  module Record
    # A lazy collection of records. Iterating runs the query once and
    # caches the rows; `includes` schedules batched eager loading of the
    # given associations, executed before the first iteration.
    class Relation(T)
      include Enumerable(T)

      @records : Array(T)?
      @preloaders = [] of Proc(Array(T), Nil)

      # Iterates the records, running the query on first access.
      def each(& : T ->) : Nil
        to_a.each { |record| yield record }
      end

      # Materializes the records, running the scheduled eager loads.
      def to_a : Array(T)
        @records ||= begin
          rows = [] of T
          T.connection.query(T.select_sql) do |rs|
            rs.each { rows << T.from_row(rs) }
          end
          @preloaders.each { |preloader| preloader.call(rows) }
          rows
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
    end
  end
end
