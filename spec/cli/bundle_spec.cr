# Specs for the curated offline bundle: source discovery, manifest provenance,
# cache refresh and example copying. All paths come from a temporary fixture
# or `ALTAIR_BUNDLE_PATH`; nothing depends on the developer's HOME.
require "../spec_helper"
require "file_utils"

private def bundle_tempdir(&)
  dir = Path.new(Dir.tempdir, "altair_bundle_#{Random.rand(1_000_000)}")
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

private def bundle_fixture(root : Path) : Path
  source = root.join("fixture_bundle")
  FileUtils.mkdir_p(source.join("docs").to_s)
  FileUtils.mkdir_p(source.join("examples", "hello").to_s)
  File.write(source.join("docs", "record.md").to_s, "# Record\n\n## Associations\n\nUse has_many.\n")
  File.write(source.join("docs", "deployment.md").to_s, "# Deployment\n\nMigrations are explicit.\n")
  File.write(source.join("examples", "hello", "README.md").to_s, "# Hello\n\nMinimal app.\n")
  File.write(source.join("examples", "hello", "app.cr").to_s, "puts \"hello\"\n")
  source
end

private def with_bundle_env(value : String?, &block : -> Nil) : Nil
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
  describe Bundle do
    it "finds an explicit bundle and lists only files actually present" do
      bundle_tempdir do |dir|
        fixture = bundle_fixture(dir)
        with_bundle_env(fixture.to_s) do
          Bundle.source_root.should eq(fixture)
          Bundle.valid_source?(fixture).should be_true
          Bundle.topics.should eq(["deployment", "record"])
          Bundle.examples.should eq(["hello"])
        end
      end
    end

    it "finds a bundle installed at ~/.altair/framework/<version>/bundle" do
      bundle_tempdir do |dir|
        fixture = bundle_fixture(dir)
        fake_home = dir.join("home")
        installed = fake_home.join(".altair", "framework", Altair::VERSION, "bundle")
        FileUtils.mkdir_p(installed.parent.to_s)
        FileUtils.cp_r(fixture.to_s, installed.to_s)
        previous_home = ENV["HOME"]?
        previous_path = ENV["ALTAIR_PATH"]?
        ENV["HOME"] = fake_home.to_s
        begin
          with_bundle_env(nil) do
            ENV.delete("ALTAIR_PATH")
            Bundle.source_root.should eq(installed)
          end
        ensure
          if previous_home
            ENV["HOME"] = previous_home
          else
            ENV.delete("HOME")
          end
          if previous_path
            ENV["ALTAIR_PATH"] = previous_path
          else
            ENV.delete("ALTAIR_PATH")
          end
        end
      end
    end

    it "refreshes a project cache and writes deterministic provenance" do
      bundle_tempdir do |dir|
        fixture = bundle_fixture(dir)
        project = dir.join("app")
        FileUtils.mkdir_p(project.to_s)
        with_bundle_env(fixture.to_s) do
          Bundle.refresh(project).should be_true
          File.read(project.join(".altair", "cache", "docs", "record.md").to_s).should contain "## Associations"
          File.exists?(project.join(".altair", "cache", "examples", "hello", "app.cr").to_s).should be_true
          manifest = Bundle.read_manifest(project).not_nil!
          manifest.version.should eq(Altair::VERSION)
          manifest.revision.should eq(Bundle::REVISION)
          manifest.topics.should eq(["deployment", "record"])
          manifest.examples.should eq(["hello"])
          first = File.read(project.join(Bundle::MANIFEST_PATH).to_s)
          Bundle.write_manifest(project, fixture)
          File.read(project.join(Bundle::MANIFEST_PATH).to_s).should eq(first)
          manifest.drift?.should be_false
        end
      end
    end

    it "detects version drift from a project manifest" do
      bundle_tempdir do |dir|
        project = dir.join("app")
        FileUtils.mkdir_p(project.join(".altair").to_s)
        File.write(project.join(Bundle::MANIFEST_PATH).to_s, "revision: 0\nframework: 0.0.1\ntopics: []\nexamples: []\n")
        Bundle.drift?(project).should be_true
      end
    end

    it "copies an example without its own shard metadata" do
      bundle_tempdir do |dir|
        fixture = bundle_fixture(dir)
        project = dir.join("app")
        FileUtils.mkdir_p(project.to_s)
        with_bundle_env(fixture.to_s) do
          Bundle.copy_examples(project, ["hello"]).should eq(["hello"])
          File.read(project.join("examples", "altair", "hello", "app.cr").to_s).should contain "hello"
          File.exists?(project.join("examples", "altair", "hello", "shard.yml").to_s).should be_false
          Bundle.read_manifest(project).not_nil!.examples.should eq(["hello"])
        end
      end
    end
  end
end
