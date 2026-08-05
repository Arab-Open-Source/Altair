# Altair — the batteries-included web framework for Crystal.
#
# This file defines the project generator: `altair new blog` writes a
# complete, runnable Altair application into a new `blog/` directory — an
# application subclass, an entry point, the standard `app/`, `config/`,
# `db/` layout, static files, a `bin/altair` launcher (plus `bin/altair.cr`
# and `bin/altair.cmd` for `crystal run` and Windows) and the shard
# metadata pointing at the framework. The generated `config/routes.cr`
# starts with an empty `routes do` block so `g scaffold` can drop a
# `resources :posts` line straight in.
#
# Everything generated is a text file written through `Base`, so the exact
# same output lands on Linux and Windows. No server, no database and no
# network round-trip are involved.
module Altair
  module CLI
    module Generators
      class New
        include Base

        # Runs `altair new <name> [--framework-path <path>]`. Reads the
        # framework path from a `--framework-path` flag or the
        # `ALTAIR_PATH` environment variable, defaulting to `nil` (GitHub).
        # Returns the process exit code.
        def self.run(args : Array(String)) : Int32
          name = args.first?
          if name.nil? || name.empty?
            abort "Missing application name for `new` — e.g. `altair new blog`"
          end

          framework_path = nil
          if index = args.index("--framework-path")
            framework_path = args[index + 1]?
          elsif flag = args.find(&.starts_with?("--framework-path="))
            framework_path = flag.split("=", 2)[1]?
          elsif env = ENV["ALTAIR_PATH"]?
            framework_path = env
          end
          framework_path = File.expand_path(framework_path.not_nil!) if framework_path && Dir.exists?(framework_path)

          New.new(name, framework_path).generate
          0
        end

        # The application name argument, e.g. `blog`.
        getter name : String

        # The path the framework shard resolves to. When creating a
        # project for a not-yet-published framework this is a local
        # directory, otherwise the shard is fetched from GitHub.
        getter framework_path : String?

        def initialize(@name : String, @framework_path : String? = nil)
        end

        # The application's module / class name, e.g. `Blog`.
        def app_class : String
          classify(@name)
        end

        # The root directory of the new project, e.g. `blog/`.
        def project_dir : Path
          Path.new(@name)
        end

        # Whether `project_dir` already exists. Refuses to overwrite it.
        def exists? : Bool
          Dir.exists?(project_dir)
        end

        # Writes the whole project. Returns the project directory.
        def generate : Path
          raise Altair::Error.new("Directory #{project_dir} already exists") if exists?
          Dir.mkdir_p(project_dir.to_s)

          generated.each do |relative, content|
            write_file(project_dir.join(relative), content)
          end
          make_executable(project_dir.join("bin/altair"))

          puts "\nCreated #{@name} — navigate in and run:"
          puts "  bin/altair server"
          project_dir
        end

        # Marks `path` executable on Unix; a no-op on Windows (the
        # `bin/altair.cmd` wrapper is the Windows launcher).
        private def make_executable(path : Path) : Nil
          unless {{ flag?(:win32) }}
            File.chmod(path, 0o755)
          end
        end

        # Every generated file's relative path and exact contents.
        private def generated : Array(Tuple(String, String))
          [
            {"shard.yml", shard_yml},
            {"bin/altair", bin_altair_wrapper},
            {"bin/altair.cr", bin_altair},
            {"bin/altair.cmd", bin_altair_cmd},
            {"src/#{@name}.cr", source_entry},
            {"src/config/application.cr", application},
            {"src/config/routes.cr", routes},
            {"src/app/controllers/application_controller.cr", application_controller},
            {"src/app/views/layouts/application.ecr", application_layout},
            {"src/app/models/.gitkeep", ""},
            {"db/schema.cr", schema},
            {"db/migrations/.gitkeep", ""},
            {"public/css/app.css", app_css},
            {".gitignore", regex_gitignore},
            {"README.md", readme},
          ]
        end

        # The shard metadata. `framework_path` pins a local checkout;
        # otherwise the framework is a GitHub dependency.
        private def shard_yml : String
          framework = if path = @framework_path
                        "    path: #{path}"
                      else
                        "    github: Arab-Open-Source/Altair"
                      end
          String.build do |io|
            io << "name: #{@name}\n"
            io << "version: 0.1.0\n"
            io << "\n"
            io << "crystal: \">= 1.21.0\"\n"
            io << "\n"
            io << "dependencies:\n"
            io << "  altair:\n"
            io << framework << "\n"
          end
        end

        # A POSIX sh wrapper so `./bin/altair server` runs without a
        # prebuilt binary: it execs `crystal run` against `bin/altair.cr`,
        # forwarding all arguments. `crystal run` cannot be the shebang
        # interpreter directly (`env` would treat "crystal run" as one word),
        # hence the `sh` indirection. Made executable in `generate`; a no-op
        # on Windows, where `bin/altair.cmd` is the launcher.
        private def bin_altair_wrapper : String
          "#!/usr/bin/env sh\n" \
          "# #{app_class} — the project command wrapper.\n" \
          "#\n" \
          "# Shims `crystal run` so `bin/altair server` runs directly.\n" \
          "exec crystal run \"$(dirname \"$0\")/altair.cr\" -- \"$@\"\n"
        end

        # The per-project CLI wrapper: `server`, `routes`, `db:*`, and the
        # generator commands. It requires the application files in order,
        # then dispatches on the first argument. Invoked by `bin/altair` /
        # `bin/altair.cmd` (or directly via `crystal run bin/altair.cr`).
        private def bin_altair : String
          String.build do |io|
            io << "require \"altair\"\n"
            io << "require \"../db/schema\"\n"
            io << "require \"../db/migrations/**\"\n"
            io << "require \"../src/app/models/**\"\n"
            io << "require \"../src/app/controllers/**\"\n"
            io << "require \"../src/config/application\"\n"
            io << "require \"../src/config/routes\"\n"
            io << "\n"
            io << "case ARGV[0]?\n"
            io << "when \"server\"\n"
            io << "  #{app_class}.run!\n"
            io << "when \"routes\"\n"
            io << "  Altair::CLI::Project.print_routes(#{app_class})\n"
            io << "when \"db:migrate\"\n"
            io << "  exit Altair::CLI::Project.migrate(#{app_class})\n"
            io << "when \"db:rollback\"\n"
            io << "  exit Altair::CLI::Project.rollback(#{app_class})\n"
            io << "else\n"
            io << "  exit Altair::CLI.run(ARGV)\n"
            io << "end\n"
          end
        end

        # The Windows convenience wrapper: `bin\altair cmd`. The `--` stops
        # `crystal run` from treating the sub-command as a source file.
        private def bin_altair_cmd : String
          "@crystal run bin\\altair.cr -- %*"
        end

        # The application entry point — the file Crystal runs.
        private def source_entry : String
          String.build do |io|
            io << "# #{app_class} — #{@name}. Run it with `crystal run src/#{@name}.cr`.\n"
            io << "require \"altair\"\n"
            io << "require \"../db/schema\"\n"
            io << "require \"../db/migrations/**\"\n"
            io << "require \"./app/models/**\"\n"
            io << "require \"./app/controllers/**\"\n"
            io << "require \"./config/application\"\n"
            io << "require \"./config/routes\"\n"
            io << "\n"
            io << "#{app_class}.run!\n"
          end
        end

        # The application subclass and its configuration.
        private def application : String
          String.build do |io|
            io << "# #{app_class} — the application configuration.\n"
            io << "class #{app_class} < Altair::Application\n"
            io << "  config.name = \"#{app_class}\"\n"
            io << "  config.port = 3000\n"
            io << "  config.db_url = ENV[\"DATABASE_URL\"]? || \"sqlite3://./db/#{@name}.db\"\n"
            io << "end\n"
            io << "\n"
            io << "# Predefined so `config/routes.cr` can include the helpers\n"
            io << "# even before the first route is declared.\n"
            io << "module #{app_class}::RouteHelpers\n"
            io << "end\n"
          end
        end

        # The routes file. Starts with an empty `routes do` block so
        # `g scaffold` can drop a resource line straight in, and reopens
        # `ApplicationController` to inject the generated path helpers
        # (which only exist once the routes have been declared).
        private def routes : String
          String.build do |io|
            io << "# #{app_class} — the route table.\n"
            io << "class #{app_class}\n"
            io << "  routes do\n"
            io << "  end\n"
            io << "end\n"
            io << "\n"
            io << "abstract class ApplicationController < Altair::Controller\n"
            io << "  include #{app_class}::RouteHelpers\n"
            io << "end\n"
          end
        end

        # The shared controller base. `ApplicationController` is reopened
        # (and given the path helpers) in `config/routes.cr`, so scaffolds
        # can always subclass it.
        private def application_controller : String
          String.build do |io|
            io << "# #{app_class} — the shared controller base. Every generated\n"
            io << "# controller subclasses it; the generated path helpers are\n"
            io << "# mixed in when `config/routes.cr` reopens the class.\n"
            io << "abstract class ApplicationController < Altair::Controller\n"
            io << "end\n"
          end
        end

        # The default page layout.
        private def application_layout : String
          title = "#{@name} — #{app_class}"
          <<-ECR
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>#{title}</title>
              <link rel="stylesheet" href="/css/app.css">
            </head>
            <body>
              <main><% yield %></main>
            </body>
            </html>
            ECR
        end

        # The compiled schema skeleton. `META` starts empty but explicitly
        # typed so a fresh project compiles before any migration runs.
        private def schema : String
          String.build do |io|
            io << "# db/schema.cr — generated by Altair::Record, do not edit.\n"
            io << "class Altair::Record::Schema\n"
            io << "  # Compile-time column metadata consumed by Altair::Record::Model macros.\n"
            io << "  META = {} of Symbol => Hash(Symbol, Hash(Symbol, String))\n"
            io << "end\n"
            io << "\n"
            io << "Altair::Record::Schema.define do |schema|\n"
            io << "end\n"
          end
        end

        # A small default stylesheet.
        private def app_css : String
          String.build do |io|
            io << "body { font-family: sans-serif; max-width: 40rem; margin: 3rem auto; padding: 0 1rem; }\n"
          end
        end

        private def regex_gitignore : String
          "/lib/\n/.altair/\n/tmp/\n/db/*.db\n"
        end

        # The project readme, pointing at the two commands.
        private def readme : String
          String.build do |io|
            io << "# #{app_class}\n"
            io << "\n"
            io << "A new Altair application.\n"
            io << "\n"
            io << "```\n"
            io << "shards install\n"
            io << "bin/altair server\n"
            io << "```\n"
            io << "\n"
            io << "then open http://localhost:3000.\n"
            io << "\n"
            io << "## Tasks\n"
            io << "\n"
            io << "```\n"
            io << "bin/altair routes        # print the route table\n"
            io << "bin/altair db:migrate   # run migrations\n"
            io << "bin/altair g scaffold Post title:string\n"
            io << "```\n"
          end
        end
      end
    end
  end
end
