# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Record::Schema`, the in-memory shape of the
# database. Migrations build it table by table, and the schema generator
# serializes it to `db/schema.cr`. The DSL methods both record the change
# on the schema state and execute the matching SQL against the connection
# (when one is attached) — the same calls serve migration execution and
# schema reconstruction, and every identifier goes through
# `Adapter#quote_identifier`.
module Altair
  module Record
    class Schema
      # One table's column.
      class Column
        # The column name.
        getter name : String

        # The logical type (`:string`, `:integer`, ...).
        getter type : Symbol

        # `false` when the column has a `NOT NULL` constraint.
        getter? null : Bool

        # Whether this column is the primary key.
        getter? primary : Bool

        def initialize(@name : String, @type : Symbol, @null : Bool = true, @primary : Bool = false)
        end

        # Updates the nullability after a `change_column_null`.
        def null=(null : Bool) : Nil
          @null = null
        end
      end

      # One index.
      class Index
        # The index name.
        getter name : String

        # The indexed columns, in order.
        getter columns : Array(String)

        # Whether the index enforces uniqueness.
        getter? unique : Bool

        def initialize(@name : String, @columns : Array(String), @unique : Bool = false)
        end
      end

      # One table.
      class Table
        # The table name.
        getter name : String

        # The table's columns, in declaration order.
        getter columns : Array(Column)

        # The table's indexes.
        getter indexes : Array(Index)

        def initialize(@name : String, @columns : Array(Column) = [] of Column, @indexes : Array(Index) = [] of Index)
        end

        # Returns the column with the given name, or `nil`.
        def column(name : String) : Column?
          @columns.find(&.name.==(name))
        end
      end

      # Builds a table definition from a `create_table` block.
      class TableBuilder
        # The table being built.
        getter table : Table

        def initialize(@adapter : Adapter, @table : Table, id_type : Symbol = :integer)
          @table.columns << Column.new("id", id_type, null: false, primary: true)
        end

        # Declares a column of the given logical type.
        def column(name : Symbol, type : Symbol, null : Bool = true, primary : Bool = false) : Nil
          @table.columns << Column.new(name.to_s, type, null, primary)
        end

        {% for type in [:string, :text, :integer, :bigint, :float, :decimal, :boolean, :datetime, :json] %}
          # Declares a `{{ type.id }}` column: `t.{{ type.id }} :title`.
          def {{ type.id }}(name : Symbol, null : Bool = true) : Nil
            column(name, {{ type.id.symbolize }}, null)
          end
        {% end %}

        # Declares a foreign-key column pair plus its index:
        # `t.references :post` adds `post_id` + `index_posts_on_post_id`.
        # With `polymorphic: true`, also adds `<name>_type` and a composite
        # `(type, id)` index instead.
        def references(name : Symbol, polymorphic : Bool = false, type : Symbol = :integer,
                       null : Bool = true, index : Bool = true) : Nil
          if polymorphic
            column("#{name.id}_id", type, null)
            column("#{name.id}_type", :string, null)
            if index
              self.index(["#{name.id}_type", "#{name.id}_id"], unique: false)
            end
          else
            column("#{name.id}_id", type, null)
            if index
              self.index(["#{name.id}_id"], unique: false)
            end
          end
        end

        # Declares an index on the given columns.
        def index(columns : Symbol | Array(Symbol), unique : Bool = false, name : String? = nil) : Nil
          names = columns.is_a?(Array) ? columns.map(&.to_s) : [columns.to_s]
          @table.indexes << Index.new(name || "index_#{@table.name}_on_#{names.join("_")}", names, unique)
        end
      end

      # The latest schema built by `Schema.define` — what a generated
      # `db/schema.cr` registers on load.
      class_property defined : Schema? = nil

      # The tables in the schema, in creation order.
      getter tables : Array(Table) = [] of Table

      def initialize(@adapter : Adapter, @connection : Connection? = nil)
      end

      # Returns the table with the given name, or `nil`.
      def table(name : String) : Table?
        @tables.find(&.name.==(name))
      end

      # Builds a schema from a block, without touching a connection — the
      # shape of a generated `db/schema.cr`:
      #
      # ```
      # Altair::Record::Schema.define do |schema|
      #   schema.table(:posts) do |t|
      #     t.column :id, :integer, null: false, primary: true
      #     t.string :title
      #   end
      # end
      # ```
      def self.define(adapter : Adapter = Adapters::SQLite3.instance, & : Schema ->) : Schema
        schema = new(adapter)
        yield schema
        self.defined = schema
        schema
      end

      # Registers a table definition without executing SQL — the shape of
      # a generated `db/schema.cr`. `id` selects the primary-key type.
      def table(name : Symbol, id : Symbol = :integer, & : TableBuilder ->) : Nil
        builder = TableBuilder.new(@adapter, Table.new(name.to_s), id)
        yield builder
        @tables << builder.table
      end

      # Creates a table: records the definition and executes the DDL. `id`
      # selects the primary-key type, defaulting to `:integer`.
      def create_table(name : Symbol, id : Symbol = :integer, & : TableBuilder ->) : Nil
        table(name, id) { |t| yield t }
        @connection.try(&.exec(builder_sql(@tables.last)))
      end

      # Drops a table.
      def drop_table(name : Symbol) : Nil
        @connection.try(&.exec("DROP TABLE #{@adapter.quote_identifier(name.to_s)}"))
        @tables.reject!(&.name.==(name.to_s))
      end

      # Adds a column to an existing table.
      def add_column(table : Symbol, name : Symbol, type : Symbol, null : Bool = true) : Nil
        column = Column.new(name.to_s, type, null)
        constraint = null ? "" : " NOT NULL"
        @connection.try(&.exec(
          "ALTER TABLE #{@adapter.quote_identifier(table.to_s)} " \
          "ADD COLUMN #{@adapter.quote_identifier(column.name)} " \
          "#{@adapter.column_type_sql(column.type)}#{constraint}"
        ))
        found = @tables.find(&.name.==(table.to_s))
        found.try { |t| t.columns << column }
      end

      # Removes a column from an existing table.
      def remove_column(table : Symbol, name : Symbol) : Nil
        @connection.try(&.exec(
          "ALTER TABLE #{@adapter.quote_identifier(table.to_s)} " \
          "DROP COLUMN #{@adapter.quote_identifier(name.to_s)}"
        ))
        found = @tables.find(&.name.==(table.to_s))
        found.try { |t| t.columns.reject!(&.name.==(name.to_s)) }
      end

      # Adds an index.
      def add_index(table : Symbol, columns : Symbol | Array(Symbol), unique : Bool = false, name : String? = nil) : Nil
        names = columns.is_a?(Array) ? columns.map(&.to_s) : [columns.to_s]
        index = Index.new(name || "index_#{table}_on_#{names.join("_")}", names, unique)
        quoted = names.map { |column| @adapter.quote_identifier(column) }.join(", ")
        @connection.try(&.exec(
          "CREATE #{unique ? "UNIQUE " : ""}INDEX #{@adapter.quote_identifier(index.name)} " \
          "ON #{@adapter.quote_identifier(table.to_s)} (#{quoted})"
        ))
        found = @tables.find(&.name.==(table.to_s))
        found.try { |t| t.indexes << index }
      end

      # Removes an index.
      def remove_index(name : Symbol) : Nil
        @connection.try(&.exec("DROP INDEX #{@adapter.quote_identifier(name.to_s)}"))
        @tables.each(&.indexes.reject!(&.name.==(name.to_s)))
      end

      # Toggles a column's nullability. Adapters that can alter a column
      # in place issue one `ALTER TABLE` statement; the rest rebuild the
      # table (create-copy-drop-rename), preserving rows and indexes.
      def change_column_null(table : Symbol, name : Symbol, null : Bool) : Nil
        if conn = @connection
          if @adapter.supports_alter_column_null?
            conn.exec(
              "ALTER TABLE #{@adapter.quote_identifier(table.to_s)} " \
              "ALTER COLUMN #{@adapter.quote_identifier(name.to_s)} " \
              "#{null ? "DROP" : "SET"} NOT NULL"
            )
          else
            rebuild_for_column_null(conn, table.to_s, name.to_s, null)
          end
        end
        found = @tables.find(&.name.==(table.to_s))
        found.try { |t| t.columns.find(&.name.==(name.to_s)).try(&.null=(null)) }
      end

      # SQLite has no `ALTER COLUMN`, so nullability changes rebuild the
      # table: read the live shape with `PRAGMA table_info` (the schema
      # state may not know this table — each migration runs against a
      # fresh `Schema`), create a temp copy with the flipped constraint,
      # copy the rows over, swap and recreate the explicit indexes.
      private def rebuild_for_column_null(conn : Connection, table_name : String, column_name : String, null : Bool) : Nil
        quoted_table = @adapter.quote_identifier(table_name)
        columns = [] of NamedTuple(name: String, type: String, notnull: Bool, pk: Bool)
        conn.query("PRAGMA table_info(#{quoted_table})") do |rs|
          rs.each do
            rs.read(Int64)
            name = rs.read(String)
            type = rs.read(String)
            notnull = rs.read(Int64) != 0
            rs.read(DB::Any)
            pk = rs.read(Int64) != 0
            columns << {name: name, type: type, notnull: notnull, pk: pk}
          end
        end
        raise Altair::Error.new("change_column_null: no such table #{table_name}") if columns.empty?
        unless columns.any? { |column| column[:name] == column_name }
          raise Altair::Error.new("change_column_null: no column #{column_name} on #{table_name}")
        end

        autoincrement = conn.query_one(
          "SELECT COALESCE(instr(sql, 'AUTOINCREMENT'), 0) FROM sqlite_master " \
          "WHERE type = 'table' AND name = #{quoted_table}"
        ) { |rs| rs.read(Int64) } != 0
        explicit_indexes = explicit_indexes_for(conn, quoted_table)

        definitions = columns.map do |column|
          enforce = column[:name] == column_name ? !null : column[:notnull]
          ddl = "#{@adapter.quote_identifier(column[:name])} #{column[:type]}"
          ddl += " NOT NULL" if enforce
          if column[:pk]
            ddl += " PRIMARY KEY"
            ddl += " AUTOINCREMENT" if autoincrement && column[:type].upcase == "INTEGER"
          end
          ddl
        end
        quoted_columns = columns.map { |column| @adapter.quote_identifier(column[:name]) }.join(", ")
        temp = @adapter.quote_identifier("altair_alter_#{table_name}")

        conn.exec("DROP TABLE IF EXISTS #{temp}")
        conn.exec("CREATE TABLE #{temp} (#{definitions.join(", ")})")
        conn.exec("INSERT INTO #{temp} (#{quoted_columns}) SELECT #{quoted_columns} FROM #{quoted_table}")
        conn.exec("DROP TABLE #{quoted_table}")
        conn.exec("ALTER TABLE #{temp} RENAME TO #{quoted_table}")

        recreate_indexes(conn, quoted_table, explicit_indexes)
      end

      # The explicitly-created indexes (`origin = 'c'`) of a table, with
      # their column lists — both must be captured before a rebuild drops
      # them along with the table. The listing is drained before the
      # per-index lookups: nested queries would deadlock a single-
      # connection pool.
      private def explicit_indexes_for(conn : Connection, quoted_table : String)
        entries = [] of NamedTuple(name: String, unique: Bool)
        conn.query("PRAGMA index_list(#{quoted_table})") do |rs|
          rs.each do
            rs.read(Int64)
            index_name = rs.read(String)
            unique = rs.read(Int64) != 0
            origin = rs.read(String)
            rs.read(Int64)
            next unless origin == "c"
            entries << {name: index_name, unique: unique}
          end
        end
        indexes = [] of NamedTuple(name: String, unique: Bool, columns: Array(String))
        entries.each do |entry|
          cols = [] of String
          conn.query("PRAGMA index_info(#{@adapter.quote_identifier(entry[:name])})") do |rs|
            rs.each do
              rs.read(Int64)
              rs.read(Int64?)
              cols << rs.read(String)
            end
          end
          indexes << {name: entry[:name], unique: entry[:unique], columns: cols}
        end
        indexes
      end

      # Recreates the captured explicit indexes on the rebuilt table.
      # Indexes born from constraints (`u`, `pk`) live in the column
      # definitions and are carried by the rebuild itself.
      private def recreate_indexes(conn : Connection, quoted_table : String,
                                   indexes : Array(NamedTuple(name: String, unique: Bool, columns: Array(String)))) : Nil
        indexes.each do |index|
          quoted = index[:columns].map { |column| @adapter.quote_identifier(column) }.join(", ")
          conn.exec(
            "CREATE #{index[:unique] ? "UNIQUE " : ""}INDEX " \
            "#{@adapter.quote_identifier(index[:name])} ON #{quoted_table} (#{quoted})"
          )
        end
      end

      private def builder_sql(table : Table) : String
        pk = table.columns.find(&.primary?)
        parts = [@adapter.autoincrement_pk_sql(pk.try(&.type) || :integer)]
        table.columns.each do |column|
          next if column.primary? && column.name == "id"
          parts << "#{@adapter.quote_identifier(column.name)} #{@adapter.column_type_sql(column.type)}#{column.null? ? "" : " NOT NULL"}"
        end
        "CREATE TABLE #{@adapter.quote_identifier(table.name)} (#{parts.join(", ")})"
      end
    end
  end
end
