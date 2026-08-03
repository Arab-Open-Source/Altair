# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Record::Adapters::PostgreSQL`, the second
# adapter implementation. It is not required from `src/altair.cr`: a
# project opts in by requiring this file and declaring `crystal-pg`
# (this repo keeps it as a dev dependency). `Connection.for` picks it up
# automatically for `postgres://` URLs.
#
# PostgreSQL is stricter than SQLite: values travel through `$n` bind
# parameters, identity columns are `GENERATED ALWAYS AS IDENTITY`, and
# every statement can report its generated ids through `RETURNING`.
require "pg"

module Altair
  module Record
    module Adapters
      class PostgreSQL
        include Altair::Record::Adapter

        # The single shared adapter instance.
        def self.instance : PostgreSQL
          @@instance ||= new
        end

        # Opens a database pool, encoding the pool options into the URI
        # query. The `postgres://` scheme is registered by `crystal-pg`.
        def connect(url : String, pool_options : DB::Pool::Options) : DB::Database
          uri = URI.parse(url)
          params = uri.query_params
          params["initial_pool_size"] = pool_options.initial_pool_size.to_s
          params["max_pool_size"] = pool_options.max_pool_size.to_s
          params["max_idle_pool_size"] = pool_options.max_idle_pool_size.to_s
          params["checkout_timeout"] = pool_options.checkout_timeout.to_s
          uri.query = params.to_s
          DB.open(uri)
        end

        def quote_identifier(name : String) : String
          "\"#{name}\""
        end

        def placeholder(index : Int32) : String
          "$#{index + 1}"
        end

        def limit_offset_clause(limit : Int32?, offset : Int32?) : String
          clauses = [] of String
          clauses << "LIMIT #{limit}" if limit
          clauses << "OFFSET #{offset}" if offset
          clauses.join(" ")
        end

        def autoincrement_pk_sql(type : Symbol) : String
          sql_type = type == :bigint ? "BIGINT" : "INTEGER"
          "\"id\" #{sql_type} GENERATED ALWAYS AS IDENTITY"
        end

        def last_insert_id(result : DB::ExecResult) : Int64
          raise Altair::Error.new(
            "PostgreSQL has no last_insert_id — inserts use RETURNING"
          )
        end

        def supports_returning?(statement : Symbol) : Bool
          true
        end

        def column_type_sql(logical_type : Symbol) : String
          case logical_type
          when :string, :text then "TEXT"
          when :integer       then "INTEGER"
          when :bigint        then "BIGINT"
          when :float         then "DOUBLE PRECISION"
          when :boolean       then "BOOLEAN"
          when :datetime      then "TIMESTAMP"
          when :json          then "JSONB"
          when :decimal       then "NUMERIC"
          else
            raise Altair::Error.new("Unknown column type: #{logical_type}")
          end
        end

        # PostgreSQL reports `NUMERIC` values as `PG::Numeric`, whose text
        # form round-trips into a `BigDecimal`.
        def read_decimal(rs : DB::ResultSet) : BigDecimal?
          if (numeric = rs.read(PG::Numeric?))
            BigDecimal.new(numeric.to_s)
          end
        end

        private def initialize
        end
      end
    end
  end
end
