# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Record::Adapters::SQLite3`, the first adapter
# implementation. SQLite stores values dynamically, so the migration DSL is
# the source of truth for column types — the adapter only translates logical
# types to SQLite type names and keeps parameter binding positional (`?`).
module Altair
  module Record
    module Adapters
      class SQLite3
        include Altair::Record::Adapter

        # The single shared adapter instance.
        def self.instance : SQLite3
          @@instance ||= new
        end

        # Opens a database pool, encoding the pool options and the
        # per-connection pragmas into the URI. WAL journaling keeps readers
        # unblocked while writers commit, and the busy timeout makes
        # concurrent writers wait instead of failing with `SQLITE_BUSY`.
        def connect(url : String, pool_options : DB::Pool::Options) : DB::Database
          uri = URI.parse(url)
          params = uri.query_params
          params["initial_pool_size"] = pool_options.initial_pool_size.to_s
          params["max_pool_size"] = pool_options.max_pool_size.to_s
          params["max_idle_pool_size"] = pool_options.max_idle_pool_size.to_s
          params["checkout_timeout"] = pool_options.checkout_timeout.to_s
          params["journal_mode"] = "WAL"
          params["busy_timeout"] = "5000"
          uri.query = params.to_s
          DB.open(uri)
        end

        def quote_identifier(name : String) : String
          "\"#{name}\""
        end

        def placeholder(index : Int32) : String
          "?"
        end

        def limit_offset_clause(limit : Int32?, offset : Int32?) : String
          clauses = [] of String
          clauses << "LIMIT #{limit}" if limit
          clauses << "OFFSET #{offset}" if offset
          clauses.join(" ")
        end

        def autoincrement_pk_sql(type : Symbol) : String
          sql_type = type == :bigint ? "BIGINT" : "INTEGER"
          "\"id\" #{sql_type} PRIMARY KEY AUTOINCREMENT"
        end

        def last_insert_id(result : DB::ExecResult) : Int64
          result.last_insert_id
        end

        def supports_returning?(statement : Symbol) : Bool
          false
        end

        def column_type_sql(logical_type : Symbol) : String
          case logical_type
          when :string, :text then "TEXT"
          when :integer       then "INTEGER"
          when :bigint        then "BIGINT"
          when :float         then "REAL"
          when :boolean       then "BOOLEAN"
          when :datetime      then "DATETIME"
          when :json          then "JSON"
          when :decimal       then "TEXT"
          else
            raise Altair::Error.new("Unknown column type: #{logical_type}")
          end
        end

        # SQLite has no `JSON::Any` cursor, so JSON columns are stored as text
        # and parsed on read.
        def read_json(rs : DB::ResultSet) : JSON::Any?
          if text = rs.read(String?)
            JSON.parse(text)
          end
        end

        # SQLite stores decimals as text; parse them back from the stored
        # form (`BigDecimal.new` also accepts a string).
        def read_decimal(rs : DB::ResultSet) : BigDecimal?
          if text = rs.read(String?)
            BigDecimal.new(text)
          end
        end

        private def initialize
        end
      end
    end
  end
end
