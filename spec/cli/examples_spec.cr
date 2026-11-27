# Specs for `altair examples`: listing, reading and copying curated examples
# from an explicit temp fixture bundle.
require "../spec_helper"
require "file_utils"

private def examples_tempdir(&)
  dir = Path.new(Dir.tempdir, "altair_examples_#{Random.rand(1_000_000)}")
  FileUtils.mkdir_p(dir)
  previous = Dir.current
  begin
    Dir.cd(dir.to_s)
    yield dir
  ensure
    Dir.cd(previous)
    FileUtils.rm_rf(dir)
  end
end

private def examples_fixture(root : Path) : Path
  source = root.join("fixture_bundle")
  FileUtils.mkdir_p(source.join("docs").to_s)
  FileUtils.mkdir_p(source.join("examples", "hello").to_s)
  File.write(source.join("examples", "hello", "README.md").to_s, "# Hello\n\nA tiny app.\n")
  File.write(source.join("examples", "hello", "app.cr").to_s, "puts \"hello\"\n")
  source
end

private def examples_with_bundle(value : String?, &block : -> Nil) : Nil
  previous = ENV["ALTAIR_BUNDLE_PATH"]?
  if value
    ENV["ALTAIR_BUNDLE_PATH"] = value
  else
    ENV.delete("ALTAIR_BUNDLE_PATH")
  end
  block.call
ensure
  if previous
    ENV["ALTAIR_BUNDLE_PATH"] = previous
  else
    ENV.delete("ALTAIR_BUNDLE_PATH")
  end
end

module Altair::CLI
  describe Examples do
    it "lists and reads examples outside a project" do
      examples_tempdir do |dir|
        fixture = examples_fixture(dir)
        examples_with_bundle(fixture.to_s) do
          CLI.find_project_dir.should be_nil
          Examples.list_examples.should eq(0)
          Examples.run([] of String).should eq(0)
          Examples.run(["hello"]).should eq(0)
          Examples.run(["missing"]).should eq(1)
        end
      end
    end

    it "refuses to copy outside a project" do
      examples_tempdir do |dir|
        fixture = examples_fixture(dir)
        examples_with_bundle(fixture.to_s) do
          Examples.run(["--copy", "hello"]).should eq(1)
          File.exists?("examples/altair/hello").should be_false
        end
      end
    end

    it "copies one example into examples/altair without shard metadata" do
      examples_tempdir do |dir|
        fixture = examples_fixture(dir)
        FileUtils.mkdir_p("bin")
        File.write("bin/altair.cr", "require \"altair\"\n")
        examples_with_bundle(fixture.to_s) do
          CLI.run(["examples", "--copy", "hello"]).should eq(0)
          File.read("examples/altair/hello/app.cr").should contain "hello"
          File.exists?("examples/altair/hello/shard.yml").should be_false
          File.read(".altair/bundle.yml").should contain "  - hello"
        end
      end
    end

    it "accepts --copy=NAME and rejects unknown names" do
      examples_tempdir do |dir|
        fixture = examples_fixture(dir)
        FileUtils.mkdir_p("bin")
        File.write("bin/altair.cr", "require \"altair\"\n")
        examples_with_bundle(fixture.to_s) do
          Examples.run(["--copy=hello"]).should eq(0)
          File.exists?("examples/altair/hello/README.md").should be_true
          Examples.run(["--copy=nope"]).should eq(1)
        end
      end
    end
  end
end
