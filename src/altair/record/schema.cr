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

        def initialize(@adapter : Adapter, @table : Table)
          @table.columns << Column.new("id", :integer, null: false, primary: true)
        end

        # Declares a column of the given logical type.
        def column(name : Symbol, type : Symbol, null : Bool = true, primary : Bool = false) : Nil
          @table.columns << Column.new(name.to_s, type, null, primary)
        end

        {% for type in [:string, :text, :integer, :bigint, :float, :boolean, :datetime, :json] %}
          # Declares a `{{ type.id }}` column: `t.{{ type.id }} :title`.
          def {{ type.id }}(name : Symbol, null : Bool = true) : Nil
            column(name, {{ type.id.symbolize }}, null)
          end
        {% end %}

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
      # a generated `db/schema.cr`.
      def table(name : Symbol, & : TableBuilder ->) : Nil
        builder = TableBuilder.new(@adapter, Table.new(name.to_s))
        yield builder
        @tables << builder.table
      end

      # Creates a table: records the definition and executes the DDL.
      def create_table(name : Symbol, & : TableBuilder ->) : Nil
        table(name) { |t| yield t }
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

      # Toggles a column's nullability.
      def change_column_null(table : Symbol, name : Symbol, null : Bool) : Nil
        @connection.try(&.exec(
          "ALTER TABLE #{@adapter.quote_identifier(table.to_s)} " \
          "ALTER COLUMN #{@adapter.quote_identifier(name.to_s)} " \
          "#{null ? "DROP" : "SET"} NOT NULL"
        ))
        found = @tables.find(&.name.==(table.to_s))
        found.try { |t| t.columns.find(&.name.==(name.to_s)).try(&.null=(null)) }
      end

      private def builder_sql(table : Table) : String
        parts = [@adapter.autoincrement_pk_sql]
        table.columns.each do |column|
          next if column.primary? && column.name == "id"
          parts << "#{@adapter.quote_identifier(column.name)} #{@adapter.column_type_sql(column.type)}#{column.null? ? "" : " NOT NULL"}"
        end
        "CREATE TABLE #{@adapter.quote_identifier(table.name)} (#{parts.join(", ")})"
      end
    end
  end
end
