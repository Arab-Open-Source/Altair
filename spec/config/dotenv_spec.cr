# Altair — the `.env` loader.
#
# Specs for `Altair::Config::DotEnv`: parsing rules and the precedence of
# real environment variables over `.env` files. Mutates the process
# environment, so every example cleans up the keys it sets.
require "../spec_helper"
require "file_utils"

describe Altair::Config::DotEnv do
  describe ".parse" do
    it "reads KEY=VALUE lines" do
      vars = Altair::Config::DotEnv.parse("FOO=bar\nBAZ=qux\n")
      vars["FOO"].should eq "bar"
      vars["BAZ"].should eq "qux"
    end

    it "skips blank lines and comments" do
      vars = Altair::Config::DotEnv.parse("# comment\n\nFOO=bar\n")
      vars.should eq({"FOO" => "bar"})
    end

    it "accepts an export prefix" do
      Altair::Config::DotEnv.parse("export FOO=bar\n")["FOO"].should eq "bar"
    end

    it "strips surrounding quotes" do
      vars = Altair::Config::DotEnv.parse("A=\"hello world\"\nB='single'\n")
      vars["A"].should eq "hello world"
      vars["B"].should eq "single"
    end

    it "cuts an inline comment after the value" do
      Altair::Config::DotEnv.parse("FOO=value # trailing\n")["FOO"].should eq "value"
    end

    it "keeps a # inside the value" do
      Altair::Config::DotEnv.parse("FOO=a#b\n")["FOO"].should eq "a#b"
    end

    it "ignores lines without an equals sign" do
      vars = Altair::Config::DotEnv.parse("FOO=bar\njust-text\n")
      vars.keys.should eq ["FOO"]
    end
  end

  describe ".env_suffix" do
    it "lowercases the environment name" do
      Altair::Config::DotEnv.env_suffix(Altair::Env::Test).should eq ".test"
      Altair::Config::DotEnv.env_suffix(Altair::Env::Production).should eq ".production"
    end
  end

  describe ".load" do
    around_each do |example|
      previous = ENV.to_h
      example.run
      ENV.keys.each { |key| ENV.delete(key) unless previous.has_key?(key) }
      previous.each { |k, v| ENV[k] = v }
    end

    it "loads .env into the process environment" do
      with_temp_dir do |dir|
        File.write(Path.new(dir, ".env"), "HELLO=world\n")
        Altair::Config::DotEnv.load(Path.new(dir)).should eq(1)
        ENV["HELLO"].should eq "world"
      end
    end

    it "does not override variables already set" do
      ENV["ALREADY"] = "real"
      with_temp_dir do |dir|
        File.write(Path.new(dir, ".env"), "ALREADY=file\n")
        Altair::Config::DotEnv.load(Path.new(dir))
        ENV["ALREADY"].should eq "real"
      end
    ensure
      ENV.delete("ALREADY")
    end

    it "lets .env.<environment> override .env" do
      with_temp_dir do |dir|
        File.write(Path.new(dir, ".env"), "DUPE=base\n")
        File.write(Path.new(dir, ".env.test"), "DUPE=test\n")
        Altair::Config::DotEnv.load(Path.new(dir), Altair::Env::Test)
        ENV["DUPE"].should eq "test"
      end
    ensure
      ENV.delete("DUPE")
    end

    it "returns 0 when there is nothing to load" do
      with_temp_dir do |dir|
        Altair::Config::DotEnv.load(Path.new(dir)).should eq(0)
      end
    end
  end
end

private def with_temp_dir(& : Path ->)
  dir = Path.new(Dir.tempdir, "altair_dotenv_#{Random.rand(100_000)}")
  Dir.mkdir_p(dir.to_s)
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir.to_s)
  end
end
