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
      # `create_table`.
      abstract def autoincrement_pk_sql : String

      # Returns the last auto-generated id of an insert result.
      abstract def last_insert_id(result : DB::ExecResult) : Int64

      # Whether the database supports `... RETURNING` for the given
      # statement kind (`:insert`, `:update` or `:delete`).
      abstract def supports_returning?(statement : Symbol) : Bool

      # The SQL type for a logical column type (`:string`, `:integer`,
      # `:boolean`, ...).
      abstract def column_type_sql(logical_type : Symbol) : String
    end
  end
end
