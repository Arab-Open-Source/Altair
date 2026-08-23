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

        # Runs `altair new <name> [--api] [--framework-path <path>]`. Reads the
        # framework path from a `--framework-path` flag or the
        # `ALTAIR_PATH` environment variable, defaulting to `nil` (GitHub).
        # The name may include a path, e.g. `altair new a/b` or
        # `/tmp/my_app`; only its basename becomes the application name.
        # Returns the process exit code.
        def self.run(args : Array(String)) : Int32
          framework_path, api, remaining = parse_args(args)
          framework_path = resolve_framework_path(framework_path)

          name = remaining.first?
          if name.nil? || name.empty?
            abort "Missing application name for `new` — e.g. `altair new blog`"
          end
          if remaining.size > 1
            abort "Too many arguments for `new` — expected one name, got: #{remaining.join(" ")}"
          end

          begin
            New.new(name, framework_path, api).generate
          rescue ex : Altair::Error
            abort ex.message || ex.to_s
          end
          0
        end

        private def self.parse_args(args : Array(String)) : {String?, Bool, Array(String)}
          framework_path = nil
          api = false
          remaining = [] of String
          index = 0
          while index < args.size
            arg = args[index]
            if arg == "--framework-path"
              framework_path = args[index + 1]?
              index += 2
            elsif arg.starts_with?("--framework-path=")
              framework_path = arg.split("=", 2)[1]? || ""
              index += 1
            elsif arg == "--api"
              api = true
              index += 1
            else
              remaining << arg
              index += 1
            end
          end
          {framework_path, api, remaining}
        end

        private def self.resolve_framework_path(path : String?) : String?
          if path.nil? || path.empty?
            if env = ENV["ALTAIR_PATH"]?
              path = env
            end
          end
          if path && !path.empty? && Dir.exists?(path)
            File.expand_path(path)
          else
            path
          end
        end

        # The raw argument as passed to `new`, e.g. `a/b` or `/tmp/my_app`.
        getter raw_name : String

        # The application name derived from the basename, e.g. `my_app`.
        getter name : String

        # The path the framework shard resolves to. When creating a
        # project for a not-yet-published framework this is a local
        # directory, otherwise the shard is fetched from GitHub.
        getter framework_path : String?

        # Whether this project exposes only JSON endpoints.
        getter? api : Bool

        def initialize(raw_name : String, @framework_path : String? = nil, @api : Bool = false)
          @raw_name = raw_name
          @name = Path.new(raw_name).basename.to_s
          if @name.empty? || @name == "." || @name == ".."
            raise Altair::Error.new("Invalid application name `#{raw_name}` — provide a name like `blog`")
          end
          if @name.includes?("-")
            suggested = @name.gsub("-", "_")
            raise Altair::Error.new("Invalid application name `#{@name}` — use only lowercase letters, digits and underscores, starting with a letter (e.g. `#{suggested}`)")
          end
          unless @name =~ /\A[a-z][a-z0-9_]*\z/
            raise Altair::Error.new("Invalid application name `#{@name}` — use only lowercase letters, digits and underscores, starting with a letter (e.g. `my_app`)")
          end
        end

        # The application's module / class name, e.g. `Blog`.
        def app_class : String
          classify(@name)
        end

        # The root directory of the new project, e.g. `blog/` or `a/b`.
        def project_dir : Path
          raw_path = Path.new(@raw_name)
          parent = raw_path.parent
          if parent == Path.new(".") || parent.to_s.empty?
            Path.new(@name)
          else
            parent / @name
          end
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

          puts post_create_message
          project_dir
        end

        # The next-steps message printed after a successful scaffold.
        # Resolving the framework dependency is an explicit first step —
        # installed users without network pass `--framework-path`.
        def post_create_message : String
          <<-TXT

            Created #{project_dir} — navigate in and run:
              shards install      # fetch the Altair framework (or re-run altair new with --framework-path for an offline copy)
              bin/altair server
            TXT
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
            {"config/database.yml", database_yml},
            {".env.example", env_example},
            {".env", env_default},
            {"src/app/controllers/application_controller.cr", application_controller},
            {"src/app/views/layouts/application.ecr", application_layout},
            {"src/app/models/.gitkeep", ""},
            {"db/schema.cr", schema},
            {"db/migrations/.gitkeep", ""},
            {"db/seeds.cr", seeds},
            {"public/css/app.css", app_css},
            {".gitignore", regex_gitignore},
            {"README.md", readme},
            {"AGENTS.md", agents_md},
            {".opencode/skills/altair/SKILL.md", agent_skill},
            {".opencode/skills/altair/reference/routing.md", ref_routing},
            {".opencode/skills/altair/reference/controllers.md", ref_controllers},
            {".opencode/skills/altair/reference/views.md", ref_views},
            {".opencode/skills/altair/reference/record.md", ref_record},
            {".opencode/skills/altair/reference/auth.md", ref_auth},
            {".opencode/skills/altair/reference/jobs.md", ref_jobs},
            {".opencode/skills/altair/reference/assets.md", ref_assets},
            {".opencode/skills/altair/reference/testing.md", ref_testing},
            {".opencode/skills/altair/reference/config.md", ref_config},
            {".opencode/skills/altair/reference/middleware.md", ref_middleware},
            {".opencode/skills/altair/reference/cli.md", ref_cli},
            {".opencode/skills/altair/reference/gotchas.md", ref_gotchas},
            {".opencode/skills/altair/reference/cache.md", ref_cache},
            {".opencode/skills/altair/reference/storage.md", ref_storage},
            {".opencode/skills/altair/reference/cable.md", ref_cable},
            {".opencode/skills/altair/reference/redis.md", ref_redis},
          ].reject { |path, _| api? && (path.starts_with?("src/app/views/") || path.starts_with?("public/") || path == ".opencode/skills/altair/reference/views.md" || path == ".opencode/skills/altair/reference/assets.md") }
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
            io << "require \"../db/seeds\"\n"
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
            io << "when \"db:seed\"\n"
            io << "  exit Altair::CLI::Project.seed\n"
            io << "when \"assets:precompile\"\n"
            io << "  exit Altair::CLI::Project.precompile_assets(#{app_class})\n"
            io << "when \"jobs:work\"\n"
            io << "  exit Altair::CLI::Project.jobs_work(#{app_class})\n"
            io << "when \"jobs:stats\"\n"
            io << "  exit Altair::CLI::Project.jobs_stats(#{app_class})\n"
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

        # The seed registry file. Blocks register at require time and run
        # only through `bin/altair db:seed`.
        private def seeds : String
          String.build do |io|
            io << "# #{@name} — seed data. Run it with `bin/altair db:seed`.\n"
            io << "# Blocks registered here stay dormant until that command runs,\n"
            io << "# so booting the server never plants data. Re-runs execute every\n"
            io << "# block again; guard with `unless Model.exists?` to stay idempotent.\n"
            io << "\n"
            io << "Altair::CLI::Project.seeds do\n"
            io << "  # Post.create(title: \"Hello\") unless Post.exists?\n"
            io << "end\n"
          end
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
            io << "  config.cors.origins = [\"*\"]\n" if api?
            io << "end\n"
            io << "\n"
            io << "# Database and secrets come from `config/database.yml` and\n"
            io << "# `.env` — edit those, not this file. `ENV[\"DATABASE_URL\"]`\n"
            io << "# overrides the file when set.\n"
            io << "\n"
            io << "# Predefined so `config/routes.cr` can include the helpers\n"
            io << "# even before the first route is declared.\n"
            io << "module #{app_class}::RouteHelpers\n"
            io << "end\n"
          end
        end

        # Per-environment database settings, consumed by
        # `Altair::Config::Database` at boot. `ENV["DATABASE_URL"]`
        # overrides the `url` here when set.
        private def database_yml : String
          String.build do |io|
            io << "# #{app_class} — the database configuration.\n"
            io << "# The active environment's section is applied at boot by\n"
            io << "# `Altair::Config::Database`; `ENV[\"DATABASE_URL\"]` overrides `url`.\n"
            io << "#\n"
            io << "development:\n"
            io << "  url: \"sqlite3://./db/#{@name}.db\"\n"
            io << "\n"
            io << "test:\n"
            io << "  url: \"sqlite3://./db/#{@name}_test.db\"\n"
            io << "\n"
            io << "production:\n"
            io << "  url: \"sqlite3://./db/#{@name}_production.db\"\n"
          end
        end

        # The shipped, committed list of environment variables the project
        # honours. Copy it to `.env` and fill in real values; `.env` is
        # git-ignored so secrets never land in the repository.
        private def env_example : String
          String.build do |io|
            io << "# Copy to `.env` and edit — `.env` is gitignored.\n"
            io << "# Leave unset to use the defaults in `config/database.yml`.\n"
            io << "# DATABASE_URL=postgres://user:pass@localhost/#{@name}_production\n"
            io << "# SECRET_KEY_BASE=<generate with: openssl rand -hex 64>\n"
            io << "# PORT=3000\n"
          end
        end

        # A working starting value of `.env`: every variable commented out,
        # so the project runs on the `database.yml` defaults immediately.
        private def env_default : String
          env_example
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
          "/lib/\n/.altair/\n/tmp/\n/db/*.db\n/.env\n"
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
            io << "bin/altair db:seed      # run db/seeds.cr\n"
            io << "bin/altair g scaffold Post title:string\n"
            io << "```\n"
          end
        end

        # Agent guide for the generated project — consumed by OpenCode,
        # Muse, Cursor, Copilot and any tool that reads AGENTS.md.
        private def agents_md : String
          <<-MD
          # AGENTS.md — #{app_class} (Altair)

          This is an **Altair** application (`#{@name}`) — a batteries-included
          Crystal web framework. Every `altair new` project follows the same
          conventions below. Read this before touching code.

          ## Quick start

          ```bash
          shards install
          bin/altair db:migrate   # create/update schema
          bin/altair server       # http://localhost:3000
          bin/altair routes       # print route table
          ```

          ## Project layout

          ```
          src/#{@name}.cr               # entry — requires everything, calls #{app_class}.run!
          src/config/application.cr  # #{app_class} < Altair::Application, config.name/port
          src/config/routes.cr       # routes do ... end + ApplicationController helpers
          src/app/models/*.cr        # Altair::Record models (table :posts)
          src/app/controllers/*.cr   # per-request controller instances
          src/app/views/<resource>/*.ecr  # ECR templates, layouts in views/layouts/
          src/app/jobs/*.cr          # background jobs (params macro)
          assets/                    # pipeline sources → public/assets/ after precompile
          public/                    # static files (Static middleware serves from here)
          db/migrations/*.cr         # timestamped migrations
          db/schema.cr               # generated — never hand-edit
          db/seeds.cr                # Altair::CLI::Project.seeds blocks
          config/database.yml        # per-env DB URLs (ENV["DATABASE_URL"] wins)
          .env / .env.example        # secrets (gitignored)
          bin/altair(.cr/.cmd)       # project launcher — forwards to Altair::CLI
          ```

          ## Routing — `src/config/routes.cr`

          ```crystal
          class #{app_class}
            routes do
              root to: HomeController.index          # GET /
              get "/about", to: HomeController.about
              resources :posts do                     # 7 REST routes + helpers
                member do
                  get :preview
                end
                collection do
                  get :search
                end
                resources :comments, only: :create
              end
              namespace :admin do
                resources :posts
              end
              get "/files/*path", to: FilesController.show  # glob — must be last segment
              redirect "/old", to: "/new"                    # 301 for every method
            end
          end
          ```

          Helpers are type-checked: `post_path(5)`, `new_post_path`, `edit_post_path(5)`.
          Constraints: `get "/users/:id", constraints: {id: /\\d+/}`. Format suffix is implicit: `/posts/5.json` → `params["format"]=="json"`.

          ## Controllers — `src/app/controllers/*_controller.cr`

          ```crystal
          class PostsController < ApplicationController
            before_action :require_login, only: [:create, :update, :destroy]
            templates "posts", root: __DIR__ + "/../views", layout: "application",
              index: {posts: Array(Post)}, show: {post: Post}, new: {post: Post}, edit: {post: Post}

            def index : Nil
              render :index, locals: {posts: Post.all.includes(:comments).to_a}
            end

            def create : Nil
              post = Post.new(title: params["title"]?.to_s)
              if post.save
                PostPublishedJob.enqueue(post_id: post.id.not_nil!.to_i64, title: post.title.to_s)
                redirect_to post_path(post.id.not_nil!)
              else
                response.status = ::HTTP::Status::UNPROCESSABLE_ENTITY
                render :new, locals: {post: post}
              end
            end

            def show : Nil
              if post = Post.find(params["id"].to_i?)
                render :show, locals: {post: post}
              else
                render text: "Not found", status: ::HTTP::Status::NOT_FOUND
              end
            end
          end
          ```

          See `reference/controllers.md` for `redirect_back`, `request.format`, `respond_to`, `head`, `stream`, `rescue_from`.

          ## Views — `src/app/views/`

          ```crystal
          # templates macro — typed locals, auto-escaped <%= %>, raw <%== %>
          # In controller: render :index, locals: {posts: posts}
          # In template:  <% posts.each do |post| %> <%= post.title %> <% end %>
          # Layouts use <% yield %>; partials via render "form", locals: {post: post}
          # Helpers: link_to, content_tag, button_to, form_for, stylesheet_link_tag
          # htmx:  content_tag(:div, hx_post: "/posts") → hx-post="/posts"
          ```

          ## ORM — `Altair::Record`

          ```crystal
          class Post < Altair::Record::Model
            table :posts
            has_many :comments, dependent: :destroy
            validates_presence_of :title
            validates_uniqueness_of :title
            scope :published, published: true
            enum_attribute :state, [:draft, :published]
            password_auth  # if User model with password_digest
          end

          Post.create(title: "Hi")              # validations + timestamps
          Post.find(1)                          # typed, nil if missing
          Post.find_by_title("Hi")              # IS NULL handled
          Post.all.where(published: true).order(:created_at, :desc).limit(10).to_a
          Post.all.includes(:comments).find_each { |p| p.comments.size }
          Post.insert_all([{title: "a"}, {title: "b"}])
          ```

          Migrations: `altair g migration CreatePosts title:string body:text` then `bin/altair db:migrate`.

          ## Auth

          ```bash
          altair g auth              # User + sessions/registrations + routes
          ```
          Model gets `password_auth` (PBKDF2-SHA256), `authenticate_password(candidate)`.
          Controller helpers: `sign_in(user.id.to_s)`, `sign_out`, `current_user_id`, `require_login`, `authenticate!`.

          ## Jobs

          ```crystal
          class SendEmailJob < Altair::Jobs::Job
            params user_id : Int64, subject : String
            def perform : Nil
              # work here
            end
          end
          SendEmailJob.enqueue(user_id: 1_i64, subject: "Hi")
          SendEmailJob.enqueue_in(2.hours, user_id: 1_i64, subject: "Hi")
          # bin/altair jobs:work  /  jobs:stats
          ```

          ## Assets

          ```bash
          bin/altair assets:precompile   # assets/ → public/assets/<name>-<digest>.<ext> + manifest.json
          ```
          In views: `stylesheet_link_tag "app"`, `javascript_asset_tag "app"`, `asset_url "logo.png"`.

          ## Testing

          ```crystal
          Altair::Test.boot(#{app_class}, configure: ->(app : #{app_class}) { app.config.secret_key_base = "test" }) do |port|
            client = Altair::Test::Client.new(port, follow_redirects: true)
            client.post("/login", form: "email=a@b.com&password=secret")
            client.get("/me").body.should contain("a@b.com")
          end
          Altair::Test.transactional { Post.create(title: "ephemeral") } # rolled back
          ```

          ## Gotchas

          - Every value is a bind param — never interpolate into SQL.
          - `HEAD` matches `GET` routes, body dropped automatically.
          - `_method` override only on POST forms.
          - New files must be required in dependency order via `src/#{@name}.cr`.

          ## Cache, Storage, Cable, Redis

          ```crystal
          Altair.cache.fetch("key") { compute }
          Altair.storage.upload(file)
          Altair::Cable.broadcast("ch", "event", data)
          client = Altair::Redis::Client.new(uri)
          ```

          Full reference: `.opencode/skills/altair/reference/*.md`
          MD
        end

        private def agent_skill : String
          <<-MD
          ---
          name: altair
          description: Altair batteries-included web framework for Crystal. Use when building or modifying an Altair project — routing (resources, constraints, glob, redirect), controllers (render/redirect/callbacks/rescue_from/respond_to), views (ECR templates, helpers, htmx), ORM Altair::Record (migrations, validations, associations, scopes, dirty tracking, enums), auth (password_auth, sessions), background jobs (params, enqueue, worker), asset pipeline (precompile, manifest), testing (Test.boot, Test::Client, transactional), CLI generators (new, g model/migration/controller/scaffold/auth, db:migrate) and middleware. Triggers on altair, Altair::*, routes, resources, controller, Record, altair g.
          compatibility: opencode
          metadata:
            framework: altair
            language: crystal
            category: web-framework
          ---

          # Altair — Batteries-Included Web Framework for Crystal

          > Generated for `#{@name}` (`#{app_class}`). This skill is embedded at `altair new` time — no network needed.

          ## When to use this skill

          - Adding routes, controllers, models, views, jobs, or assets
          - Debugging 404/405, validation errors, N+1 queries, or session/auth flows
          - Writing specs with `Altair::Test`

          ## Quick reference

          | Task | Command |
          |------|---------|
          | New app | `altair new #{@name} && shards install` |
          | Scaffold | `altair g scaffold Post title:string` |
          | Migrate | `bin/altair db:migrate` / `db:rollback` / `db:seed` |
          | Routes | `bin/altair routes` |
          | Server | `bin/altair server` |
          | Assets | `bin/altair assets:precompile` |
          | Jobs | `bin/altair jobs:work` / `jobs:stats` |

          ## Reference index — read the file matching your task

          - `reference/routing.md` — DSL, helpers, constraints, glob, redirect
          - `reference/controllers.md` — rendering, redirects, callbacks, rescue_from, CSRF
          - `reference/views.md` — ECR, layouts, partials, helpers, htmx
          - `reference/record.md` — models, CRUD, validations, associations, migrations
          - `reference/auth.md` — password_auth, sessions, JWT, CSRF
          - `reference/jobs.md` — typed jobs, queue, worker
          - `reference/assets.md` — pipeline, manifest, helpers
          - `reference/testing.md` — Test.boot, Client, transactional
          - `reference/config.md` — database.yml, .env, environments
          - `reference/middleware.md` — stack, factories, security headers
          - `reference/cli.md` — all generators and project commands
          - `reference/gotchas.md` — pitfalls that cost real debugging time

          ## 60-second app

          ```bash
          altair new #{@name} && cd #{@name} && shards install
          altair g scaffold Post title:string body:text
          bin/altair db:migrate
          bin/altair server  # http://localhost:3000/posts
          ```

          ## Conventions

          - Compile-time safety first — `post_path(5)` is a method, wrong arity fails to compile.
          - Segment-based routing, not regex.
          - Middleware via factories `Proc(Application, Middleware)`.
          - One `Application` subclass per project (`#{app_class}`).
          - Escape by default (`<%= %>` escaped, `<%== %>` raw).

          ## Further reading

          Project `README.md`, root `AGENTS.md`, and `examples/blog` (full vertical slice).
          MD
        end

        private def ref_routing : String
          <<-MD
          # Routing — Altair

          Segment-based, compile-time checked. No regex.

          ```crystal
          class #{app_class}
            routes do
              root to: HomeController.index
              get "/about", to: HomeController.about
              post "/posts", to: PostsController.create
              get "/posts/:id", to: PostsController.show
              resources :posts do
                member do
                  get :preview          # GET /posts/:id/preview → preview_post_path(id)
                end
                collection do
                  get :search           # GET /posts/search → search_posts_path
                end
                resources :comments, only: :create
              end
              namespace :admin do
                resources :posts
              end
              get "/files/*path", to: FilesController.show
              redirect "/old", to: "/new"
            end
          end
          ```

          - Helpers are methods: `post_path(5)`, `edit_post_path(5)`, `admin_posts_path`.
          - `resources :posts, only: [:index, :show]` / `except:` to filter.
          - Constraints: `get "/u/:id", constraints: {id: /\\d+/}, to: UsersController.show` — whole-value anchored.
          - Implicit format: `/posts/5.json` → `params["format"]=="json"` and `request.format==:json`.
          - Glob must be last segment; format suffix not stripped from glob.
          - Redirects match every method, never appear in `Allow`.

          **Pitfall:** `HEAD` matches `GET` routes; body dropped.
          MD
        end

        private def ref_controllers : String
          <<-MD
          # Controllers — Altair

          Per-request instances: `PostsController.new(request, response).show`.

          ```crystal
          class PostsController < ApplicationController
            before_action :require_login, only: [:create]
            after_action :log_view, only: [:show]
            rescue_from RecordNotFound, handle_with: :not_found

            def index : Nil
              posts = Post.all.includes(:comments).to_a
              render :index, locals: {posts: posts}
            end

            def create : Nil
              post = Post.new(title: params["title"]?.to_s)
              if post.save
                redirect_to post_path(post.id.not_nil!)
              else
                response.status = ::HTTP::Status::UNPROCESSABLE_ENTITY
                render :new, locals: {post: post}
              end
            end

            def show : Nil
              render json: Post.find!(params["id"].to_i)
            end

            private def not_found(ex : RecordNotFound) : Nil
              render text: "Not found", status: ::HTTP::Status::NOT_FOUND
            end
          end
          ```

          - `redirect_to`, `redirect_back(fallback: "/")` (same-host guard), `head :no_content`, `stream(content_type) { |io| }`.
          - `request.format`, `respond_to { |f| f.html { }; f.json { }; }` → 406 if unmatched.
          - CSRF: `protect_from_forgery` in controller; forms get `_csrf` via `form_for`.
          MD
        end

        private def ref_views : String
          <<-MD
          # Views — Altair

          ECR transpiled at compile time via `templates` macro.

          ```crystal
          class PostsController < ApplicationController
            templates "posts", root: __DIR__ + "/../views", layout: "application",
              index: {posts: Array(Post)}, show: {post: Post}, new: {post: Post}, edit: {post: Post}
          end
          # render :index, locals: {posts: posts}  → views/posts/index.ecr inside layouts/application.ecr
          # render :index, layout: false           → fragment (htmx)
          # render "form", locals: {post: post}    → partial views/posts/_form.ecr
          ```

          Escaping: `<%= post.title %>` escaped, `<%== raw_html %>` raw, `<%%` literal.
          Helpers: `link_to`, `content_tag(:div, "hi", class: "card")`, `button_to` (handles `_method`), `form_for(post, "/posts") do |f|; f.text_field :title; end`, `stylesheet_link_tag "app"`, `javascript_asset_tag "app"`, `javascript_include_tag :htmx`.
          htmx: `hx_post: "/posts"` → `hx-post="/posts"`, `request.hx_request?`, `hx_trigger` headers.
          MD
        end

        private def ref_record : String
          <<-MD
          # ORM — Altair::Record

          Schema is compile-time: `db/schema.cr` META drives `table` macro — wrong column is a compile error.

          ```crystal
          class Post < Altair::Record::Model
            table :posts
            has_many :comments, dependent: :destroy
            belongs_to :author, class_name: "User"
            validates_presence_of :title
            validates_uniqueness_of :slug, scope: :tenant_id
            validates_length_of :title, minimum: 3, maximum: 100
            scope :published, published: true
            scope :recent { |q| q.order(:created_at, :desc).limit(10) }
            enum_attribute :state, [:draft, :published]
          end

          Post.create(title: "Hi")
          Post.find(1)                    # nil if missing
          Post.find!(1)                   # raises RecordNotFound
          Post.find_by_title("Hi")        # typed finder per column
          Post.all.where(published: true).where(:views, :>, 10).order(:title).limit(5).to_a
          Post.all.includes(:comments).find_each(batch_size: 100) { |p| }
          post.changed?; post.changed_attributes; post.restore_attributes(:title)
          Post.insert_all([{title: "a"}, {title: "b"}])
          Post.transaction { post.save!; Comment.create!(post_id: post.id) }

          # Joins — filter parents by children in one SQL query:
          Post.all.joins(:comments).where("comments.body", "altair")   # INNER JOIN + DISTINCT
          Post.all.left_joins(:comments)                                # keep childless owners
          Post.all.joins(:comments).count                               # COUNT(DISTINCT posts.id)

          # has_many :through — source inferred from the singular name:
          has_many :tags, through: :post_tags       # add source: :tag if ambiguous
          post.tags                                 # lazy: one JOIN query
          Post.all.includes(:tags)                  # eager: one batched JOIN

          # Polymorphic:
          belongs_to :commentable, polymorphic: true   # commentable_id + commentable_type
          has_many :comments, as: :commentable, dependent: :destroy
          comment.commentable                          # Post or Video, by type column

          # Ordering accumulates:
          Post.all.order(:created_at).order(:title)    # ORDER BY created_at, title
          Post.all.reorder(:title)                     # replaces existing orders
          post.reload                                  # re-reads from database
          ```

          Custom primary keys: `table :posts, primary_key: :uuid` — string PKs auto-generate UUID.

          Cache: `Altair.cache.fetch("key", expires_in: 5.minutes) { compute }`.
          Storage: `Altair.storage.upload(file)` / `Altair.storage.url(key)` (Disk or S3).
          Attachments: `has_one_attached :avatar` → `model.attach_avatar(upload)` / `model.avatar` / `model.purge_avatar`.
          WebSocket: `Altair::Cable.broadcast("channel", message)`; endpoint at `/cable`.

          API mode: `altair new app --api` generates JSON-only project with CORS.

          Migrations: `t.references :commentable, polymorphic: true` generates the id/type pair + composite index; `bin/altair db:migrate` regenerates `db/schema.cr`. Never hand-edit schema.

          Validations: presence/length/numericality/uniqueness/inclusion/exclusion/format/confirmation + `validate :custom`.
          Callbacks: `before_save/after_save/before_create/.../after_destroy` — `save` wraps in TX when callbacks exist.

          Performance: every value is a bind param; `find_each` keeps filters; `count` uses `COUNT(*)`; N+1 detector warns past threshold in dev.
          MD
        end

        private def ref_auth : String
          <<-MD
          # Auth — Altair

          ```bash
          altair g auth            # User + sessions/registrations controllers/views/routes
          ```

          ```crystal
          class User < Altair::Record::Model
            table :users
            validates_presence_of :email
            validates_uniqueness_of :email
            password_auth min_length: 8
          end

          user = User.new(email: "a@b.com")
          user.password = "secret12"
          user.password_confirmation = "secret12"
          user.save  # hashes via PBKDF2-SHA256 into password_digest
          user.authenticate_password("secret12") # => true
          ```

          Controller helpers: `sign_in(user.id.to_s)`, `sign_out`, `current_user_id`, `logged_in?`, `require_login` (302 to `login_path`), `authenticate!` (401), `protect_from_forgery`.
          JWT: `Altair::Auth::JWT.sign({user_id: "1"}, secret)` / `.verify(token, secret)`.
          MD
        end

        private def ref_jobs : String
          <<-MD
          # Background Jobs — Altair

          ```crystal
          class SendEmailJob < Altair::Jobs::Job
            params user_id : Int64, subject : String
            def perform : Nil
              User.find!(user_id) # work
            end
          end
          SendEmailJob.enqueue(user_id: 1_i64, subject: "Welcome")
          SendEmailJob.enqueue_in(2.hours, user_id: 1_i64, subject: "Hi")
          SendEmailJob.enqueue_at(Time.utc + 1.day, user_id: 1_i64, subject: "Hi")
          ```

          Table `altair_jobs` created lazily. Worker claims atomically:

          ```bash
          bin/altair jobs:work   # poll interval from config.jobs_poll_interval
          bin/altair jobs:stats  # pending/running/done/failed counts
          ```

          Retry: exponential backoff (2s doubling, cap 5m) until `jobs_max_attempts` (default 5); `max_attempts` overridable per job.
          Test mode: `Altair::Jobs::Queue.test_mode = true` collects enqueues; drain via `Worker#execute`.
          MD
        end

        private def ref_assets : String
          <<-MD
          # Asset Pipeline — Altair

          ```
          assets/css/app.css  →  bin/altair assets:precompile  →  public/assets/css/app-<digest>.css + manifest.json
          ```

          Helpers prefer manifest:
          ```crystal
          stylesheet_link_tag "app"      # <link rel="stylesheet" href="/assets/css/app-abc123.css">
          javascript_asset_tag "app"     # <script src="/assets/js/app-abc123.js" defer>
          asset_url "logo.png"           # /assets/logo-abc123.png
          javascript_include_tag :htmx   # CDN or local via config.htmx_src/version
          ```

          Fingerprinted responses carry `Cache-Control: immutable`. Plain copies stay cache-neutral for dev without precompile.
          Re-running rotates digests and prunes stale fingerprints of rebuilt paths.
          MD
        end

        private def ref_testing : String
          <<-MD
          # Testing — Altair

          ```crystal
          describe "posts" do
            it "lists posts" do
              Altair::Test.boot(Blog, configure: ->(app : Blog) { app.config.secret_key_base = "test" }) do |port|
                client = Altair::Test::Client.new(port, follow_redirects: true)
                client.post("/login", form: "email=a@b.com&password=secret")
                client.get("/posts").body.should contain("Hello")
              end
            end

            it "isolates data" do
              Altair::Test.transactional do
                Post.create(title: "ephemeral") # rolled back after block
              end
            end
          end
          ```

          `boot` saves/restores `application_instance`, binds ephemeral port, waits ready. `Client` keeps cookie jar. `migrate!` prepares DB. `transactional` joins outer TX via savepoints when nested.
          MD
        end

        private def ref_config : String
          <<-MD
          # Configuration — Altair

          ```crystal
          class Blog < Altair::Application
            config.name = "Blog"
            config.port = 3000
            config.secret_key_base = ENV["SECRET_KEY_BASE"]? || "dev-secret"
            config.db_url = ENV["ALTAIR_DB_URL"]? || "sqlite3://./db/blog.db"
          end
          ```

          `config/database.yml` per-env URLs; `.env` (real ENV wins; `.env.<env>` overrides `.env`) merged at boot via `Altair::Config::DotEnv` / `Database`.
          Pool: `db_max_pool_size` 10, `db_initial_pool_size` 2, `db_max_idle_pool_size` 2, `db_checkout_timeout` 5s, `db_query_timeout` 5s.
          Jobs: `jobs_poll_interval`, `jobs_max_attempts`, `jobs_queues`. Router: `router_cache_size` 1024.
          MD
        end

        private def ref_middleware : String
          <<-MD
          # Middleware — Altair

          Factories `Proc(Application, Middleware)` — not `Middleware.new(app)` (widens type).

          ```crystal
          class Blog < Altair::Application
            use Altair::Middleware::Logger
          end
          # Default stack: Logger → RequestId → SecurityHeaders → Cors → Static
          ```

          `SecurityHeaders` (nosniff/SAMEORIGIN/referrer), `RequestId` (X-Request-Id echo), `Cors` (opt-in via `config.cors.origins`), `Static` (serves `public/` with traversal protection; immutable cache on fingerprints).
          Custom: `def call(request, response, chain : Proc(Nil)) : Nil; chain.call; end`.
          MD
        end

        private def ref_cli : String
          <<-MD
          # CLI — Altair

          ```bash
          altair new blog [--framework-path DIR]     # scaffold (ALTAIR_PATH env too)
          altair g model Post title:string
          altair g migration CreatePosts title:string
          altair g controller Posts
          altair g scaffold Post title:string body:text
          altair g auth [User]
          altair install [--dir DIR] [--force]        # copy binary to PATH
          altair update [--check] [--force]
          bin/altair server | routes | db:migrate | db:rollback | db:seed | assets:precompile | jobs:work | jobs:stats
          ```

          `new` prints `shards install` reminder. Standalone `altair` auto-forwards app-context commands by walking up to `bin/altair.cr`.

          The `jobs` table and `assets` manifest are lazy — no extra migration needed.
          MD
        end

        private def ref_cache : String
          <<-MD
          # Cache — Altair

          MemoryStore (dev) and RedisStore (production).

          ```crystal
          Altair.cache.write("key", "value", expires_in: 5.minutes)
          Altair.cache.read("key")
          Altair.cache.fetch("key") { compute_expensive }
          ```
          MD
        end

        private def ref_storage : String
          <<-MD
          # Storage & Attachments — Altair

          ```crystal
          config.storage = Altair::Storage::DiskStore.new(Path.new("public/uploads"))
          stored = Altair.storage.upload(upload)
          Altair.storage.url(stored.key)
          has_one_attached :avatar
          user.attach_avatar(upload); user.avatar; user.purge_avatar
          ```

          Migration: `t.references :name, polymorphic: true`.
          MD
        end

        private def ref_cable : String
          <<-MD
          # WebSocket Cable — Altair

          Channel-based broadcaster with auth hook and heartbeat.

          ```crystal
          config.cable_auth = ->(req, ctx) {
            !request.session["user_id"]?.nil?
          }
          Altair::Cable.broadcast("room:1", "message", {"text" => "hello"})
          ```
          MD
        end

        private def ref_redis : String
          <<-MD
          # Redis Client — Altair (pure Crystal, no external shard)

          ```crystal
          client = Altair::Redis::Client.new(URI.parse("redis://localhost:6379"))
          client.set("k", "v", ex: 60.seconds)
          client.get("k")
          client.publish("ch", "msg")
          client.pipeline do |pipe|
            pipe.set("a", "1"); pipe.incr("c")
          end
          client.multi do |txn|
            txn.set("k", "v"); txn.expire("k", 60)
          end
          ```
          MD
        end

        private def ref_gotchas : String
          <<-MD
          # Gotchas — Altair

          - Every value is a bind param — never interpolate into SQL; identifiers via `quote_identifier`.
          - `NamedTuple#select` does not exist — use `to_a.select`.
          - `Exception#cause=` is not public — chain in constructor.
          - `Log::IOBackend` needs `require "log/io_backend"`; sync specs need `dispatcher: Sync`.
          - `MIME.from_extension?` takes leading dot: `".css"`.
          - `HEAD` matches `GET` routes, body dropped automatically.
          - `_method` override only on `POST` forms.
          - `yield` + `ensure` widens to `| Nil` — use `.as`.
          - New files must be registered in `src/altair.cr` in dependency order.
          - Welcome page renders when no routes and path is `/`.
          - `pkill` unreliable — kill by PID.
          - Crystal's `Time.instant` preferred over `Time.monotonic` (deprecated).
          MD
        end
      end
    end
  end
end
