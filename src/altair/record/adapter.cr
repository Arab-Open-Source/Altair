# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Record::Adapter`, the interface every database
# adapter implements. Migrations, schema generation and finders talk to
# this interface — never to a driver directly — so a new database (Postgres
# next) means writing one adapter, not touching the ORM.
module Altair
  module Record
    module Adapter
      # Opens a `DB::Database` pool for the given connection URL.
      abstract def connect(url : String, pool_options : DB::PoolOptions) : DB::Database

      # Quotes an identifier (table or column name) for SQL, e.g. `"posts"`.
      abstract def quote_identifier(name : String) : String

      # The parameter placeholder for the given bind index, e.g. `?` for
      # SQLite and `$1` for Postgres.
      abstract def placeholder(index : Int32) : String

      # The `LIMIT`/`OFFSET` clause, e.g. `LIMIT 10 OFFSET 20`.
      abstract def limit_offset_clause(limit : Int32?, offset : Int32?) : String

      # The SQL for the auto-incrementing primary-key column of
      # `create_table`, rendered for the column's logical type.
      abstract def autoincrement_pk_sql(type : Symbol) : String

      # Returns the last auto-generated id of an insert result.
      abstract def last_insert_id(result : DB::ExecResult) : Int64

      # Whether the database supports `... RETURNING` for the given
      # statement kind (`:insert`, `:update` or `:delete`).
      abstract def supports_returning?(statement : Symbol) : Bool

      # Whether a single `ALTER TABLE ... ALTER COLUMN ... SET/DROP NOT NULL`
      # statement can toggle nullability in place. When `false`, the schema
      # layer rebuilds the table (create-copy-drop-rename) instead.
      def supports_alter_column_null? : Bool
        false
      end

      # The SQL type for a logical column type (`:string`, `:integer`,
      # `:boolean`, ...).
      abstract def column_type_sql(logical_type : Symbol) : String

      # Encodes an attribute value into its bind-ready form. JSON values are
      # bound as their text form on both backends: PostgreSQL casts the text
      # into `JSONB`, and SQLite stores it in its `JSON`-typed TEXT column.
      # Decimal values travel the same way, cast into `NUMERIC` and parsed
      # back on read.
      def encode_column(value : Altair::Record::Model::Value, type : Symbol) : Altair::Record::Model::Value
        case type
        when :json
          value.is_a?(JSON::Any) ? value.to_json : value
        when :decimal
          value.is_a?(BigDecimal) ? value.to_s : value
        else
          value
        end
      end

      # Reads a JSON column from a result set, or `nil` when it is null.
      # PostgreSQL returns `JSON::Any` natively; SQLite returns the stored
      # text and parses it.
      def read_json(rs : DB::ResultSet) : JSON::Any?
        rs.read(JSON::Any?)
      end

      # Reads a decimal column from a result set, or `nil` when it is null.
      abstract def read_decimal(rs : DB::ResultSet) : BigDecimal?
    end
  end
end
