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
          File.executable?("blog/bin/altair").should be_true
        end
        File.read("blog/src/blog.cr").should contain "Blog.run!"
        File.read("blog/src/config/application.cr").should contain "class Blog < Altair::Application"
        File.read("blog/src/config/routes.cr").should contain "routes do"
        File.exists?("blog/src/app/models/.gitkeep").should be_true
        File.exists?("blog/db/migrations/.gitkeep").should be_true
        File.read("blog/db/schema.cr").should contain "META = {} of Symbol => Hash(Symbol, Hash(Symbol, String))"
        File.exists?("blog/public/css/app.css").should be_true
      end
    end

    it "defaults the framework to a GitHub dependency" do
      in_tempdir do
        Generators::New.new("blog").generate
        File.read("blog/shard.yml").should contain "github: Arab-Open-Source/Altair"
      end
    end

    it "refuses to overwrite an existing directory" do
      in_tempdir do
        Dir.mkdir("blog")
        expect_raises(Altair::Error) { Generators::New.new("blog").generate }
      end
    end
  end
end
