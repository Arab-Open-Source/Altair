# Altair — self-install command.
#
# Specs for `Altair::CLI::Install`. `altair install` copies the running
# binary into a user-accessible directory on PATH (for example
# `~/.local/bin`) so the command is available directly. The specs run on
# file copies inside a temp dir — no real user home, no system directories
# and no network — keeping them fast, portable and side-effect free.
require "../spec_helper"
require "file_utils"

module Altair::CLI
  describe Install do
    describe ".sha256" do
      it "returns a 64-character hex digest for a file" do
        in_tempdir do |_dir|
          File.write("payload.bin", "altair install content\n")
          Install.sha256(Path.new("payload.bin")).size.should eq(64)
          Install.sha256(Path.new("payload.bin")).should match(/\A[0-9a-f]{64}\z/)
        end
      end

      it "is deterministic" do
        in_tempdir do |_dir|
          File.write("payload.bin", "same bytes")
          Install.sha256(Path.new("payload.bin")).should eq(Install.sha256(Path.new("payload.bin")))
        end
      end
    end

    describe "#target_path" do
      it "names the executable after altair, with .exe on Windows" do
        in_tempdir do |dir|
          install = Install.new(Path.new("source"), dir)
          install.target_path.should eq(dir / Install.executable_name)
        end
      end
    end

    describe ".default_bin_dir" do
      it "honors the ALTAIR_BIN override" do
        in_tempdir do |dir|
          previous = ENV["ALTAIR_BIN"]?
          ENV["ALTAIR_BIN"] = dir.to_s
          begin
            Install.default_bin_dir.should eq(dir)
          ensure
            if previous.nil?
              ENV.delete("ALTAIR_BIN")
            else
              ENV["ALTAIR_BIN"] = previous
            end
          end
        end
      end
    end

    describe ".option_value" do
      it "returns the token following the flag" do
        Install.option_value(["--dir", "/tmp/x", "--force"], "--dir").should eq(Path.new("/tmp/x"))
        Install.option_value(["--force"], "--dir").should be_nil
      end
    end

    describe "#install" do
      it "copies the source binary into the target directory" do
        in_tempdir do |dir|
          source = Path.new("altair-src")
          File.write(source, "the binary bytes")
          install = Install.new(source, dir)

          install.install.should be_true
          File.exists?(install.target_path).should be_true
          File.read(install.target_path).should eq("the binary bytes")
        end
      end

      it "makes the installed file executable" do
        in_tempdir do |dir|
          source = Path.new("altair-src")
          File.write(source, "the binary bytes")
          Install.new(source, dir).install

          permissions = File.info(dir / Install.executable_name).permissions
          (permissions & File::Permissions.new(0o111)).should_not eq(File::Permissions.new(0))
        end
      end

      it "is idempotent when the target is identical" do
        in_tempdir do |dir|
          source = Path.new("altair-src")
          File.write(source, "the binary bytes")
          install = Install.new(source, dir)

          install.install
          install.install.should be_false
        end
      end

      it "raises when the target holds different content without force" do
        in_tempdir do |dir|
          source = Path.new("altair-src")
          File.write(source, "new binary")
          target = dir / Install.executable_name
          File.write(target, "old, unrelated binary")

          expect_raises(Altair::Error, /already exists/) do
            Install.new(source, dir).install
          end
        end
      end

      it "overwrites with force" do
        in_tempdir do |dir|
          source = Path.new("altair-src")
          File.write(source, "new binary")
          target = dir / Install.executable_name
          File.write(target, "old binary")

          Install.new(source, dir).install(force: true).should be_true
          File.read(target).should eq("new binary")
        end
      end

      it "matches the source checksum after install" do
        in_tempdir do |dir|
          source = Path.new("altair-src")
          File.write(source, "the binary bytes")
          install = Install.new(source, dir)
          install.install

          Install.sha256(install.target_path).should eq(Install.sha256(source))
        end
      end
    end
  end
end

private def in_tempdir(&)
  dir = Path.new(Dir.tempdir, "altair_install_#{Random.rand(1_000_000)}")
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
