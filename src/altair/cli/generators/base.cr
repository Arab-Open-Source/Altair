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
      end
    end
  end
end
