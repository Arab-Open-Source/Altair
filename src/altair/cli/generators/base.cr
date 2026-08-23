# Altair — the batteries-included web framework for Crystal.
#
# This file defines the base helpers shared by every Altair generator: a
# tiny filesystem context (write files, create parent directories, echo the
# created path) and column-spec parsing (`"title:string"` → a column named
# `title` of type `:string`). Generators all run against a fresh project
# layout and never touch the network or a database — they only write text
# files, so the exact same code works on every operating system.
module Altair
  module CLI
    module Generators
      # One parsed column from a generator argument, e.g. `body:text`.
      struct Column
        # The column name, e.g. `title`.
        getter name : String

        # The logical type as a symbol, e.g. `:string`.
        getter type : Symbol

        def initialize(@name : String, @type : Symbol)
        end

        # The `t.<type> :name` invocation for a schema builder.
        def schema_line(indent : String = "        ") : String
          "#{indent}t.#{@type} :#{@name}"
        end
      end

      # Shared filesystem and naming helpers for generators.
      module Base
        extend self

        # The column types a generator argument accepts, mapped to the
        # schema `t.<type>` method.
        VALID_TYPES = %i[string text integer bigint float decimal boolean datetime json]

        # Echoes the file that was written to and returns it.
        def announce(path : Path) : Path
          puts "  create  #{path}"
          path
        end

        # Writes `content` to `path`, creating parent directories. Echoes
        # the created path. Returns the path.
        def write_file(path : Path, content : String) : Path
          Dir.mkdir_p(path.parent.to_s)
          File.write(path, content)
          announce(path)
        end

        # Parses `["title:string", "body:text"]` into columns. A name
        # without a type defaults to `:string`. Raises on an unknown type.
        def parse_columns(args : Array(String)) : Array(Column)
          args.reject(&.empty?).map do |spec|
            name, _, type_str = spec.partition(":")
            type = if type_str.empty?
                     :string
                   else
                     TYPES_MAP[type_str]? || raise Altair::Error.new(
                       "Unknown column type '#{type_str}' for #{name} — expected one of: " +
                       VALID_TYPES.join(", ")
                     )
                   end
            Column.new(name, type)
          end
        end

        # Maps a type name to its symbol (`"string"` → `:string`).
        private TYPES_MAP = VALID_TYPES.to_h { |type| {type.to_s, type} }

        # Converts a model name to its camelized class form (`BlogPost`).
        # Already-camelized names pass through untouched — `capitalize`
        # would otherwise lowercase the tail (`BlogPost` → `Blogpost`).
        def classify(name : String) : String
          if name =~ /\A[A-Z][A-Za-z0-9]*\z/
            name
          else
            Altair::Inflector.camelize(name)
          end
        end

        # Converts a model name to its singular attribute name (`blog_post`).
        def singular(name : String) : String
          Altair::Inflector.underscore(Altair::Inflector.singularize(classify(name)))
        end

        # Converts a model name to its plural table name (`blog_posts`).
        def tableize(name : String) : String
          Altair::Inflector.tableize(classify(name))
        end

        # The shared URL prefix for a table's resources, e.g. `blog_posts`.
        def resource_path(table : String) : String
          "/#{table}"
        end

        # Maps a schema type name to its symbol (`"integer"` → `:integer`),
        # for reading existing `db/schema.cr` files.
        TYPE_NAMES = VALID_TYPES.to_h { |type| {type.to_s, type} }

        # Appends `table` built from `columns` to `db/schema.cr` so models
        # compile before the first migration runs. Preserves any tables
        # already declared; regenerating is idempotent. Returns the path.
        def seed_schema(table : String, columns : Array(Column)) : Path
          path = Path.new("db/schema.cr")
          existing = read_tables(File.exists?(path) ? File.read(path) : "")

          if existing.any? { |name, _| name == table }
            return path
          end
          existing << {table, columns}
          write_file(path, render_schema(existing))
        end

        # Parses the declared tables out of an existing `db/schema.cr`
        # (`name`, columns) from its `Schema.define` block.
        def read_tables(content : String) : Array(Tuple(String, Array(Column)))
          tables = [] of Tuple(String, Array(Column))
          content.scan(/schema\.table\(:(\w+)\) do \|t\|\n((?:\s+\S.*\n)*?)\s+end/) do |match|
            name = match[1]
            cols = [] of Column
            match[2].split('\n').each do |line|
              if line =~ /\s+t\.column :(\w+), :(\w+)/
                cols << Column.new($1, TYPE_NAMES[$2])
              end
            end
            cols.unshift(Column.new("id", :integer)) unless cols.any?(&.name.==("id"))
            tables << {name, cols}
          end
          tables
        end

        # Renders `db/schema.cr`, matching the runner's own output so a
        # later `db:migrate` produces identical bytes.
        def render_schema(tables : Array(Tuple(String, Array(Column)))) : String
          String.build do |io|
            io << "# db/schema.cr — generated by Altair::Record, do not edit.\n"
            io << "# The source of truth is the migrations; rebuild with the runner.\n"
            io << "class Altair::Record::Schema\n"
            io << "  # Compile-time column metadata consumed by Altair::Record::Model macros.\n"
            io << "  META = {\n"
            tables.each do |table_name, cols|
              io << "    #{table_name}: {\n"
              max = cols.max_of(&.name.size)
              cols.each do |col|
                col_name = col.name + ":"
                meta = col.name == "id" ? "null: false, primary: true" : "null: true, primary: false"
                io << "      #{(col_name).ljust(max + 1)} {type: :#{col.type}, #{meta}},\n"
              end
              io << "    },\n"
            end
            io << "  }\n"
            io << "end\n"
            io << "\n"
            io << "Altair::Record::Schema.define do |schema|\n"
            tables.each do |table_name, cols|
              io << "  schema.table(:#{table_name}) do |t|\n"
              cols.each do |col|
                null = col.name == "id" ? "null: false, primary: true" : "null: true, primary: false"
                io << "    t.column :#{col.name}, :#{col.type}, #{null}\n"
              end
              io << "  end\n"
            end
            io << "end\n"
          end
        end

        # Inserts extra route lines into the project's `routes do` block,
        # respecting indentation. Regenerating is idempotent when any line
        # is already present. Returns the routes path.
        def register_route_lines(new_lines : Array(String)) : Path
          path = Path.new("src/config/routes.cr")
          lines = File.read_lines(path)

          return path if new_lines.first?.try { |first| lines.any? { |line| line.strip == first } }

          open = lines.index(&.includes?("routes do"))
          close = open.try { |i| (i + 1...lines.size).find { |j| lines[j].strip == "end" } }
          unless open && close
            raise Altair::Error.new("Could not find a `routes do` block in #{path}")
          end

          body_indent = lines[open].gsub(/\S.*/, "").size + 2
          new_lines.each_with_index do |route_line, offset|
            lines.insert(close + offset, "#{" " * body_indent}#{route_line}")
          end
          write_file(path, lines.join('\n'))
        end
      end
    end
  end
end
