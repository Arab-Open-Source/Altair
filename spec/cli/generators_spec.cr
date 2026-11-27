# Altair — the command-line interface and generator layer.
#
# Specs for `Altair::CLI` and `Altair::CLI::Generators`. Generators write
# into the current working directory, so every spec runs inside a fresh
# temp directory and leaves it clean. These cover the pure file-emission
# part of Phase 5 — no server, no database and no network are involved,
# which keeps them fast and portable across operating systems.
require "../spec_helper"
require "file_utils"
require "file"

private def in_tempdir(&)
  dir = Path.new(Dir.tempdir, "altair_cli_#{Random.rand(1_000_000)}")
  FileUtils.mkdir_p(dir)
  previous = Dir.current
  begin
    Dir.cd(dir.to_s)
    yield Dir.current
  ensure
    Dir.cd(previous)
    FileUtils.rm_rf(dir)
  end
end

module Altair::CLI
  describe ".help" do
    it "mentions new and the generator aliases" do
      help = Altair::CLI.help
      help.should contain "altair new"
      help.should contain "altair generate"
      help.should contain "scaffold"
      help.should contain "install"
    end
  end

  describe ".run" do
    it "returns 0 for --version" do
      Altair::CLI.run(["--version"]).should eq(0)
    end

    it "returns 0 for --help" do
      Altair::CLI.run(["--help"]).should eq(0)
    end
  end

  describe Generators::Column do
    it "renders a schema builder line" do
      Generators::Column.new("title", :string).schema_line.should eq("        t.string :title")
    end
  end

  describe Generators::Base do
    it "parses columns, defaulting missing type to string" do
      columns = Generators::Base.parse_columns(["title:string", "body", "price:float"])
      columns.map(&.name).should eq(["title", "body", "price"])
      columns.map(&.type).should eq([:string, :string, :float])
    end

    it "rejects an unknown column type" do
      expect_raises(Altair::Error) do
        Generators::Base.parse_columns(["title:zorp"])
      end
    end
  end

  describe Generators do
    describe "new --api" do
      it "generates a JSON-only project with CORS enabled" do
        in_tempdir do
          app = Generators::New.new("api_blog", nil, true)
          app.generate
          File.read("api_blog/src/config/application.cr").should contain "config.cors.origins = [\"*\"]"
          File.exists?("api_blog/src/app/views/layouts/application.ecr").should be_false
          File.exists?("api_blog/public/css/app.css").should be_false
        end
      end
    end

    describe "new -d postgresql" do
      it "wires the pg shard, postgres URLs and the adapter require" do
        in_tempdir do
          app = Generators::New.new("pg_blog", nil, false, :postgresql)
          app.generate
          shard = File.read("pg_blog/shard.yml")
          shard.should contain "pg:"
          shard.should contain "Arab-Open-Source/crystal-pg"
          shard.should contain "09165422b8fcac84d4359340bd4c35f5ff541e31"
          database = File.read("pg_blog/config/database.yml")
          database.should contain "postgres://postgres:postgres@localhost/pg_blog_development"
          database.should contain "postgres://postgres:postgres@localhost/pg_blog_test"
          source = File.read("pg_blog/src/pg_blog.cr")
          source.should contain "require \"altair/record/adapters/postgresql\""
          wrapper = File.read("pg_blog/bin/altair.cr")
          wrapper.should contain "require \"altair/record/adapters/postgresql\""
        end
      end

      it "keeps sqlite defaults untouched" do
        in_tempdir do
          app = Generators::New.new("lite_blog", nil, false)
          app.generate
          File.read("lite_blog/shard.yml").should_not contain "crystal-pg"
          File.read("lite_blog/config/database.yml").should contain "sqlite3://./db/lite_blog.db"
          File.read("lite_blog/src/lite_blog.cr").should_not contain "adapters/postgresql"
        end
      end

      it "rejects an unknown adapter" do
        expect_raises(Altair::Error, /database/) do
          Generators::New.new("weird", nil, false, :oracle)
        end
      end
    end

    describe "model" do
      it "writes a classified model file into src/app/models" do
        in_tempdir do
          Generators::Model.new("BlogPost").generate.should eq(Path.new("src/app/models/blog_post.cr"))
          content = File.read("src/app/models/blog_post.cr")
          content.should contain "class BlogPost < Altair::Record::Model"
          content.should contain "table :blog_posts"
        end
      end
    end

    describe "migration" do
      it "derives the plural table and timestamped file name" do
        in_tempdir do
          migration = Generators::Migration.new("CreatePosts", [
            Generators::Column.new("title", :string),
            Generators::Column.new("body", :text),
          ])
          migration.table.should eq "posts"
          migration.file_name.should match /\A\d{14}_create_posts\.cr\z/
          migration.generate
          files = Dir.children("db/migrations")
          files.size.should eq(1)
          content = File.read(Path.new("db/migrations/#{files.first}"))
          content.should contain "class CreatePosts < Altair::Record::Migration"
          content.should contain "schema.create_table(:posts)"
          content.should contain "t.string :title"
          content.should contain "t.text :body"
          content.should contain "schema.drop_table(:posts)"
        end
      end

      it "requires the name to start with Create" do
        expect_raises(Altair::Error) do
          Generators::Migration.new("AddPosts", [] of Generators::Column).table
        end
      end

      it "refuses to overwrite an existing migration" do
        in_tempdir do
          migration = Generators::Migration.new("CreatePosts", [] of Generators::Column)
          migration.generate
          expect_raises(Altair::Error) { migration.generate }
        end
      end
    end

    describe "controller" do
      it "writes a plural controller and its views" do
        in_tempdir do
          controller = Generators::Controller.new("Posts")
          controller.class_name.should eq "PostsController"
          controller.table.should eq "posts"
          controller.generate.should eq(Path.new("src/app/controllers/posts_controller.cr"))
          content = File.read("src/app/controllers/posts_controller.cr")
          content.should contain "class PostsController < ApplicationController"
          content.should contain "templates \"posts\""
          ["index.ecr", "show.ecr", "new.ecr", "edit.ecr"].each do |view|
            File.exists?(Path.new("src/app/views/posts/#{view}")).should be_true
          end
        end
      end
    end

    describe "scaffold" do
      it "writes model, migration, controller, views and routes" do
        in_tempdir do
          Dir.mkdir_p("src/config")
          File.write("src/config/routes.cr", <<-CR)
            class Blog
              routes do
              end
            end
            CR
          Dir.mkdir_p("db")
          File.write("db/schema.cr", "class Altair::Record::Schema\n  META = {} of Symbol => Hash(Symbol, Hash(Symbol, String))\nend\nAltair::Record::Schema.define do |schema|\nend\n")

          scaffold = Generators::Scaffold.new("Post", [
            Generators::Column.new("title", :string),
          ])
          scaffold.generate

          File.exists?("src/app/models/post.cr").should be_true
          File.exists?("db/migrations").should be_true
          Dir.children("db/migrations").size.should eq(1)
          File.exists?("src/app/controllers/posts_controller.cr").should be_true
          File.exists?("src/app/views/posts/index.ecr").should be_true

          routes = File.read("src/config/routes.cr")
          routes.should contain "resources :posts"

          schema = File.read("db/schema.cr")
          schema.should contain "posts: {"
          schema.should contain "t.column :id, :integer, null: false, primary: true"
        end
      end

      it "seeding schema is idempotent" do
        in_tempdir do
          Dir.mkdir_p("db")
          Dir.mkdir_p("src/config")
          File.write("db/schema.cr", "")
          File.write("src/config/routes.cr", "class Blog\n  routes do\n  end\nend\n")

          scaffold = Generators::Scaffold.new("Post", [Generators::Column.new("title", :string)])
          scaffold.generate
          first = File.read("db/schema.cr")
          scaffold.seed_schema("posts")
          File.read("db/schema.cr").should eq first
        end
      end
    end

    describe "auth" do
      it "writes the full registration/login stack" do
        in_tempdir do
          Dir.mkdir_p("src/config")
          File.write("src/config/routes.cr", <<-CR)
            class Blog
              routes do
              end
            end
            CR
          Dir.mkdir_p("db")
          File.write("db/schema.cr", "class Altair::Record::Schema\n  META = {} of Symbol => Hash(Symbol, Hash(Symbol, String))\nend\nAltair::Record::Schema.define do |schema|\nend\n")

          paths = Generators::Auth.new("User").generate

          paths.each { |path| File.exists?(path).should be_true }

          model = File.read("src/app/models/user.cr")
          model.should contain("table :users")
          model.should contain("password_auth min_length: 8")
          model.should contain("validates_uniqueness_of :email")

          migration = Dir.children("db/migrations").first
          migration.should contain("_create_users")

          File.read("src/app/controllers/sessions_controller.cr").should contain("authenticate_password")
          File.read("src/app/controllers/registrations_controller.cr").should contain("password_confirmation")
          ["sessions/new.ecr", "registrations/new.ecr"].each do |view|
            File.exists?(Path.new("src/app/views/#{view}")).should be_true
          end

          routes = File.read("src/config/routes.cr")
          ["/login", "/register", "/logout"].each { |path| routes.should contain(path) }

          schema = File.read("db/schema.cr")
          schema.should contain("users: {")
          schema.should contain("password_digest")
        end
      end

      it "defaults to a User model and is idempotent on rerun" do
        in_tempdir do
          Dir.mkdir_p("src/config")
          File.write("src/config/routes.cr", "class Blog\n  routes do\n  end\nend\n")
          Dir.mkdir_p("db")
          File.write("db/schema.cr", "class Altair::Record::Schema\n  META = {} of Symbol => Hash(Symbol, Hash(Symbol, String))\nend\nAltair::Record::Schema.define do |schema|\nend\n")

          Generators::Auth.new.generate
          before = File.read("db/schema.cr")
          Generators::Auth.new.generate
          File.read("db/schema.cr").should eq(before)
          File.read("src/config/routes.cr").scan(%(get "/login")).size.should eq(1)
        end
      end
    end
  end

  describe Generators::New do
    it "writes a runnable project layout" do
      in_tempdir do
        generator = Generators::New.new("blog", "/tmp/fake-framework")
        generator.generate.should eq(Path.new("blog"))

        File.read("blog/shard.yml").should contain "path: /tmp/fake-framework"
        File.exists?("blog/bin/altair").should be_true
        File.exists?("blog/bin/altair.cr").should be_true
        File.exists?("blog/bin/altair.cmd").should be_true
        File.read("blog/bin/altair").should start_with("#!/usr/bin/env sh")
        File.read("blog/bin/altair.cr").should start_with("require \"altair\"")
        File.read("blog/bin/altair.cmd").should contain "crystal run bin\\altair.cr -- %*"
        unless {{ flag?(:win32) }}
          File::Info.executable?("blog/bin/altair").should be_true
        end
        File.read("blog/src/blog.cr").should contain "Blog.run!"
        File.read("blog/src/config/application.cr").should contain "class Blog < Altair::Application"
        File.read("blog/src/config/routes.cr").should contain "routes do"
        File.read("blog/config/database.yml").should contain "sqlite3://./db/blog.db"
        File.read("blog/.env.example").should contain "DATABASE_URL="
        File.exists?("blog/.env").should be_true
        File.read("blog/.gitignore").should contain "/.env"
        File.exists?("blog/src/app/models/.gitkeep").should be_true
        File.exists?("blog/db/migrations/.gitkeep").should be_true
        File.read("blog/db/schema.cr").should contain "META = {} of Symbol => Hash(Symbol, Hash(Symbol, String))"
        File.exists?("blog/db/seeds.cr").should be_true
        File.read("blog/db/seeds.cr").should contain "Altair::CLI::Project.seeds"
        File.read("blog/bin/altair.cr").should contain "require \"../db/seeds\""
        File.read("blog/bin/altair.cr").should contain "when \"db:seed\""
        File.exists?("blog/public/css/app.css").should be_true
      end
    end

    it "points the user at shards install before the first run" do
      message = Generators::New.new("blog", "/tmp/fake-framework").post_create_message
      message.should contain("shards install")
      message.should contain("--framework-path")
    end

    it "supports a path like a/b and uses its basename for the app" do
      in_tempdir do
        generator = Generators::New.new("a/b", "/tmp/fake-framework")
        generator.generate.should eq(Path.new("a/b"))
        File.read("a/b/shard.yml").should contain "name: b"
        File.exists?("a/b/src/b.cr").should be_true
        File.read("a/b/src/b.cr").should contain "B.run!"
        File.read("a/b/config/database.yml").should contain "sqlite3://./db/b.db"
      end
    end

    it "rejects hyphenated names with a suggestion" do
      expect_raises(Altair::Error, "my_app") do
        Generators::New.new("my-app").generate
      end
    end

    it "defaults the framework to a GitHub dependency" do
      in_tempdir do
        Generators::New.new("blog").generate
        File.read("blog/shard.yml").should contain "github: Arab-Open-Source/Altair"
      end
    end

    it "generates an admin controller with require_login" do
      in_tempdir do
        Dir.mkdir_p("src/config")
        File.write("src/config/routes.cr", "class Blog\n  routes do\n  end\nend\n")

        Generators::Admin.new("Post").generate

        controller = File.read("src/app/controllers/admin/posts_controller.cr")
        controller.should contain("Admin::PostsController")
        controller.should contain("before_action :require_login")

        routes = File.read("src/config/routes.cr")
        routes.should contain("namespace :admin do")
        routes.should contain("resources :posts")
      end
    end

    it "refuses to overwrite an existing directory" do
      in_tempdir do
        Dir.mkdir("blog")
        expect_raises(Altair::Error) { Generators::New.new("blog").generate }
      end
    end

    it "generates a Docker and Compose deployment contract" do
      in_tempdir do
        Generators::New.new("blog", "/tmp/fake-framework").generate
        docker = File.read("blog/Dockerfile")
        docker.should contain "FROM crystallang/crystal:1.22.3-alpine AS builder"
        docker.should contain "--release --static --no-debug"
        docker.should contain "sqlite-static yaml-static"
        docker.should contain "USER app"
        docker.should contain "HEALTHCHECK"
        docker.should contain "http://127.0.0.1:3000/health"
        docker.should contain "CMD [\"./bin/blog\"]"
        docker.should contain "COPY db/migrations ./db/migrations"
        docker.should_not contain "db:migrate"
        ignore = File.read("blog/.dockerignore")
        %w[.git .env lib/ bin/* spec/ db/*.db public/assets/].each do |pattern|
          ignore.should contain pattern
        end
        ignore.should contain "!bin/altair.cr"
        compose = File.read("blog/compose.yml")
        compose.should contain "sqlite_data:/app/db/data"
        compose.should contain "DATABASE_URL: ${DATABASE_URL:-sqlite3://./db/data/blog_production.db}"
        compose.should contain "SECRET_KEY_BASE: ${SECRET_KEY_BASE:?set SECRET_KEY_BASE}"
        File.read("blog/src/config/application.cr").should contain "config.observability = true"
        env = File.read("blog/.env.example")
        env.should contain "ALTAIR_ENV=production"
        env.should contain "HOST_PORT=3000"
        env.should_not contain "postgres:postgres"
      end
    end

    it "generates a PostgreSQL image and a healthy database service" do
      in_tempdir do
        Generators::New.new("pg_blog", "/tmp/fake-framework", false, :postgresql).generate
        docker = File.read("pg_blog/Dockerfile")
        docker.should contain "postgresql-dev"
        docker.should contain "sqlite-static yaml-static"
        compose = File.read("pg_blog/compose.yml")
        compose.should contain "image: postgres:16-alpine"
        compose.should contain "pg_data:/var/lib/postgresql/data"
        compose.should contain "condition: service_healthy"
        compose.should contain "POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD}"
        compose.should_not contain "POSTGRES_PASSWORD: postgres"
      end
    end

    it "omits views and asset stages in API mode" do
      in_tempdir do
        generator = Generators::New.new("api_blog", "/tmp/fake-framework", true)
        paths = generator.generated_paths
        paths.should_not contain "public/css/app.css"
        paths.should_not contain "assets/css/app.css"
        generator.generate
        File.exists?("api_blog/src/app/views").should be_false
        docker = File.read("api_blog/Dockerfile")
        docker.should_not contain "assets:precompile"
        docker.should_not contain "COPY --from=builder /app/public"
        File.read("api_blog/compose.yml").should contain "web:"
      end
    end

    it "copies the curated examples and a bundle manifest with --with-examples" do
      in_tempdir do
        framework = Path[__DIR__].parent.parent
        Generators::New.new("with_examples", framework.to_s, false, :sqlite, true).generate
        %w[hello json_api cache].each do |name|
          File.exists?("with_examples/examples/altair/#{name}/app.cr").should be_true
          File.exists?("with_examples/examples/altair/#{name}/README.md").should be_true
          File.exists?("with_examples/examples/altair/#{name}/shard.yml").should be_false
        end
        manifest = File.read("with_examples/.altair/bundle.yml")
        manifest.should contain "framework: #{Altair::VERSION}"
        manifest.should contain "revision: #{Altair::CLI::Bundle::REVISION}"
        manifest.should contain "  - hello"
        File.exists?("with_examples/.altair/cache/docs/deployment.md").should be_true
        File.read("with_examples/README.md").should contain "examples/altair/"
      end
    end

    it "writes deterministic files for the same arguments" do
      first_root = Path.new(Dir.tempdir, "altair_generator_first_#{Random.rand(1_000_000)}")
      second_root = Path.new(Dir.tempdir, "altair_generator_second_#{Random.rand(1_000_000)}")
      FileUtils.mkdir_p(first_root)
      FileUtils.mkdir_p(second_root)
      begin
        first = Generators::New.new("blog", "/tmp/fake-framework")
        second = Generators::New.new("blog", "/tmp/fake-framework")
        first.generated_paths.should eq(second.generated_paths)
        Dir.cd(first_root.to_s) { first.generate }
        Dir.cd(second_root.to_s) { second.generate }
        first.generated_paths.each do |relative|
          first_file = first_root.join("blog", relative)
          second_file = second_root.join("blog", relative)
          File.exists?(second_file.to_s).should be_true
          File.read(first_file.to_s).should eq(File.read(second_file.to_s))
        end
      ensure
        FileUtils.rm_rf(first_root.to_s)
        FileUtils.rm_rf(second_root.to_s)
      end
    end

    it "embeds a comprehensive agent skill into every new project" do
      in_tempdir do
        Generators::New.new("blog", "/tmp/fake-framework").generate
        File.exists?("blog/AGENTS.md").should be_true
        File.read("blog/AGENTS.md").should contain("Altair")
        File.exists?("blog/.opencode/skills/altair/SKILL.md").should be_true
        File.read("blog/.opencode/skills/altair/SKILL.md").should contain("Altair")
        File.read("blog/.opencode/skills/altair/SKILL.md").should contain("description:")
        # reference index
        File.exists?("blog/.opencode/skills/altair/reference/routing.md").should be_true
        File.exists?("blog/.opencode/skills/altair/reference/controllers.md").should be_true
        File.exists?("blog/.opencode/skills/altair/reference/record.md").should be_true
        File.read("blog/.opencode/skills/altair/reference/record.md").should contain("Altair::Record")
        File.exists?("blog/.opencode/skills/altair/reference/testing.md").should be_true
      end
    end
  end
end
