# Specs for `altair docs`: topic listing, section lookup, unknown topics and
# project-local cache refresh. The bundle is a temp fixture selected by
# `ALTAIR_BUNDLE_PATH`, never the developer's installed framework.
require "../spec_helper"
require "file_utils"

private def docs_tempdir(&)
  dir = Path.new(Dir.tempdir, "altair_docs_#{Random.rand(1_000_000)}")
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

private def docs_fixture(root : Path) : Path
  source = root.join("fixture_bundle")
  FileUtils.mkdir_p(source.join("docs").to_s)
  FileUtils.mkdir_p(source.join("examples", "hello").to_s)
  File.write(source.join("docs", "record.md").to_s, "# Record\n\n```crystal\n## Associations in a code sample\n```\n\n## Associations\n\nUse has_many and belongs_to.\n\n## Validations\n\nValidate presence.\n")
  File.write(source.join("examples", "hello", "README.md").to_s, "# Hello\n")
  source
end

private def docs_with_bundle(value : String?, &block : -> Nil) : Nil
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
  describe Docs do
    it "lists topics from the fixture bundle" do
      docs_tempdir do |dir|
        fixture = docs_fixture(dir)
        docs_with_bundle(fixture.to_s) do
          Docs.all_topics.should contain("record")
          Docs.list_topics.should eq(0)
          Docs.topic_content("record").not_nil!.should contain("## Associations")
        end
      end
    end

    it "resolves a topic and a heading while ignoring fenced code headings" do
      docs_tempdir do |dir|
        fixture = docs_fixture(dir)
        docs_with_bundle(fixture.to_s) do
          words = ["record", "associations"]
          Docs.resolve_topic(words).should eq("record")
          section = Docs.section_for(Docs.topic_content("record").not_nil!, words)
          section.should contain("## Associations")
          section.should contain("has_many")
          section.should contain("Use has_many and belongs_to.\n")
          section.should_not contain("in a code sample")
          section.should_not contain("## Validations")
        end
      end
    end

    it "returns zero for a known topic and one for an unknown topic" do
      docs_tempdir do |dir|
        fixture = docs_fixture(dir)
        docs_with_bundle(fixture.to_s) do
          Docs.run(["record"]).should eq(0)
          Docs.run(["no_such_topic_here"]).should eq(1)
          CLI.run(["docs", "record"]).should eq(0)
        end
      end
    end

    it "refreshes inside a project and refuses outside one" do
      docs_tempdir do |dir|
        fixture = docs_fixture(dir)
        docs_with_bundle(fixture.to_s) do
          Docs.run(["--refresh"]).should eq(1)
          FileUtils.mkdir_p("bin")
          File.write("bin/altair.cr", "require \"altair\"\n")
          Docs.run(["--refresh"]).should eq(0)
          File.exists?(".altair/cache/docs/record.md").should be_true
          File.read(".altair/bundle.yml").should contain "framework: #{Altair::VERSION}"
        end
      end
    end
  end
end
