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
  describe ".project_hint" do
    it "is empty outside a project" do
      in_tempdir { Altair::CLI.project_hint("server").should eq "" }
    end

    it "is empty for an unknown command name" do
      in_tempdir { Altair::CLI.project_hint("not-a-real-command").should eq "" }
    end

    {% if !flag?(:win32) %}
      it "points at bin/altair when inside a generated project" do
        in_tempdir do
          Dir.mkdir_p("bin")
          FileUtils.touch("shard.yml")
          File.write("bin/altair", "#!/usr/bin/env sh\n")
          File.chmod("bin/altair", 0o755)
          hint = Altair::CLI.project_hint("server")
          hint.should contain "bin/altair server"
        end
      end
    {% end %}

    it "is empty when only the command matches but no project is present" do
      in_tempdir { Altair::CLI.project_hint("db:migrate").should eq "" }
    end
  end
end
