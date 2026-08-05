# Specs for `Altair::CLI`, the top-level command dispatcher.

require "../spec_helper"
require "file_utils"

private def in_tempdir(&)
  dir = Path.new(Dir.tempdir, "altair_cli_#{Random.rand(1_000_000)}")
  FileUtils.mkdir_p(dir)
  previous = Dir.current
  begin
    Dir.cd(dir.to_s)
    yield
  ensure
    Dir.cd(previous)
    FileUtils.rm_rf(dir)
  end
end

module Altair::CLI
  describe ".project_command?" do
    it "recognizes app-context commands" do
      %w[server routes db:migrate db:rollback].each do |command|
        Altair::CLI.project_command?(command).should be_true
      end
    end

    it "rejects non-app commands" do
      %w[new version help g scaffold].each do |command|
        Altair::CLI.project_command?(command).should be_false
      end
      Altair::CLI.project_command?(nil).should be_false
    end
  end

  describe ".find_project_dir" do
    it "is nil outside a project" do
      in_tempdir { Altair::CLI.find_project_dir.should be_nil }
    end

    it "finds a project by its bin/altair.cr launcher" do
      in_tempdir do
        Dir.mkdir_p("bin")
        File.write("bin/altair.cr", "require \"altair\"\n")
        Altair::CLI.find_project_dir.should eq(Path[Dir.current])
      end
    end

    it "finds the project from a nested directory" do
      in_tempdir do
        Dir.mkdir_p("bin")
        Dir.mkdir_p("src/app/models")
        File.write("bin/altair.cr", "require \"altair\"\n")
        Dir.cd("src/app/models")
        Altair::CLI.find_project_dir.should eq(Path.new("../../..").expand(Dir.current))
      end
    end
  end

  describe ".project_launcher" do
    it "prefers an executable bin/altair wrapper when present" do
      in_tempdir do
        Dir.mkdir_p("bin")
        File.write("bin/altair", "#!/usr/bin/env sh\n")
        command, args = Altair::CLI.project_launcher(Path[Dir.current], ["server"])
        command.should eq((Path[Dir.current] / "bin" / "altair").to_s)
        args.should eq(["server"])
      end
    end

    it "falls back to crystal run bin/altair.cr for old projects" do
      in_tempdir do
        Dir.mkdir_p("bin")
        File.write("bin/altair.cr", "require \"altair\"\n")
        command, args = Altair::CLI.project_launcher(Path[Dir.current], ["routes"])
        command.should eq("crystal")
        args.should eq(["run", (Path[Dir.current] / "bin" / "altair.cr").to_s, "--", "routes"])
      end
    end
  end
end
