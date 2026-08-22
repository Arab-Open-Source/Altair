# Altair — the batteries-included web framework for Crystal.
#
# This file defines the scaffold generator: `altair generate scaffold Post
# title:string body:text` writes the model, the `Create<Table>` migration
# and the RESTful controller+views, then inserts `resources :posts` into
# the routes block. It is the full vertical slice: new project, scaffold,
# server — and the demo works.
module Altair
  module CLI
    module Generators
      class Scaffold
        include Base

        # The resource name argument, e.g. `Post`.
        getter name : String

        # The columns of the scaffolded resource.
        getter columns : Array(Column)

        def initialize(@name : String, @columns : Array(Column))
        end

        # The resource path name, e.g. `posts`.
        def table : String
          tableize(classify(@name))
        end

        # Writes the model, migration and controller/views, registers the
        # `resources` route and seeds `db/schema.cr`. Returns the paths.
        def generate : Array(Path)
          paths = [] of Path

          model = Model.new(name)
          paths << model.generate

          migration = Migration.new("Create#{Altair::Inflector.pluralize(classify(@name))}", columns)
          paths << migration.generate

          controller = Controller.new(name, Controller::DEFAULT_ACTIONS, columns)
          paths << controller.generate

          seed_schema(table)
          register_routes(table)
          paths
        end

        # Appends the scaffolded table to `db/schema.cr` so the model
        # compiles before the first migration runs. Returns the path.
        def seed_schema(table : String) : Path
          Base.seed_schema(table, columns_with_id)
        end

        # The table's columns, the primary `id` first.
        private def columns_with_id : Array(Column)
          [Column.new("id", :integer)] + @columns
        end

        # Inserts `resources :posts` into the `routes do` block, respecting
        # indentation. Regenerating is idempotent. Returns the routes path.
        def register_routes(table : String) : Path
          path = Path.new("src/config/routes.cr")
          lines = File.read_lines(path)

          if lines.any?(&.includes?("resources :#{table}"))
            return path
          end

          open = lines.index(&.includes?("routes do"))
          close = open.try { |i| (i + 1...lines.size).find { |j| lines[j].strip == "end" } }
          unless open && close
            raise Altair::Error.new("Could not find a `routes do` block in #{path}")
          end

          body_indent = lines[open].gsub(/\S.*/, "").size + 2
          lines.insert(close, "#{" " * body_indent}resources :#{table}")
          write_file(path, lines.join('\n'))
        end
      end
    end
  end
end
