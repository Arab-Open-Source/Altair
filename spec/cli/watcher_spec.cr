require "../spec_helper"
require "file_utils"

private def with_tempdir(& : Path ->)
  dir = Path.new(Dir.tempdir, "altair_watcher_#{Random.rand(1_000_000)}")
  Dir.mkdir_p(dir)
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir.to_s)
  end
end

describe Altair::CLI::Watcher do
  describe Altair::CLI::Watcher::Options do
    it "parses port flags" do
      options = Altair::CLI::Watcher::Options.parse(["-p", "4000"])
      options.port.should eq(4000)

      options2 = Altair::CLI::Watcher::Options.parse(["--port", "5000"])
      options2.port.should eq(5000)
    end

    it "parses bind and host flags" do
      options = Altair::CLI::Watcher::Options.parse(["-b", "127.0.0.1"])
      options.host.should eq("127.0.0.1")

      options2 = Altair::CLI::Watcher::Options.parse(["--bind", "10.0.0.1"])
      options2.host.should eq("10.0.0.1")

      options3 = Altair::CLI::Watcher::Options.parse(["-h", "localhost"])
      options3.host.should eq("localhost")

      options4 = Altair::CLI::Watcher::Options.parse(["--host", "0.0.0.0"])
      options4.host.should eq("0.0.0.0")
    end

    it "parses environment flags" do
      options = Altair::CLI::Watcher::Options.parse(["-e", "production"])
      options.env.should eq("production")

      options2 = Altair::CLI::Watcher::Options.parse(["--env", "development"])
      options2.env.should eq("development")
    end

    it "parses watch flags" do
      options = Altair::CLI::Watcher::Options.parse(["-w"])
      options.watch?.should be_true

      options2 = Altair::CLI::Watcher::Options.parse(["--watch"])
      options2.watch?.should be_true

      options3 = Altair::CLI::Watcher::Options.parse(["--no-watch"])
      options3.watch?.should be_false
    end

    it "parses delay and entry flags" do
      options = Altair::CLI::Watcher::Options.parse(["--delay", "500ms", "--entry", "src/custom.cr"])
      options.delay.should eq(500.milliseconds)
      options.entry.should eq("src/custom.cr")
    end

    it "parses durations correctly" do
      Altair::CLI::Watcher::Options.parse_duration("250ms").should eq(250.milliseconds)
      Altair::CLI::Watcher::Options.parse_duration("1.5s").should eq(1500.milliseconds)
      Altair::CLI::Watcher::Options.parse_duration("2s").should eq(2000.milliseconds)
      Altair::CLI::Watcher::Options.parse_duration("1m").should eq(60000.milliseconds)
      Altair::CLI::Watcher::Options.parse_duration("300").should eq(300.milliseconds)
    end

    it "accumulates unrecognized extra arguments" do
      options = Altair::CLI::Watcher::Options.parse(["-p", "3000", "--foo", "bar"])
      options.port.should eq(3000)
      options.extra_args.should eq(["--foo", "bar"])
    end
  end

  describe ".should_watch?" do
    it "returns false inside child worker process" do
      ENV["ALTAIR_CHILD_PROCESS"] = "1"
      begin
        options = Altair::CLI::Watcher::Options.new
        Altair::CLI::Watcher.should_watch?(SpecApp, options).should be_false
      ensure
        ENV.delete("ALTAIR_CHILD_PROCESS")
      end
    end

    it "returns false when --no-watch is passed" do
      options = Altair::CLI::Watcher::Options.new
      options.watch = false
      Altair::CLI::Watcher.should_watch?(SpecApp, options).should be_false
    end

    it "returns true when -w is explicitly passed even in test environment" do
      options = Altair::CLI::Watcher::Options.new
      options.watch = true
      Altair::CLI::Watcher.should_watch?(SpecApp, options).should be_true
    end

    it "returns false in production environment" do
      options = Altair::CLI::Watcher::Options.new
      options.env = "production"
      Altair::CLI::Watcher.should_watch?(SpecApp, options).should be_false
    end

    it "returns false in test environment by default" do
      options = Altair::CLI::Watcher::Options.new
      Altair::CLI::Watcher.should_watch?(SpecApp, options).should be_false
    end
  end

  describe "entrypoint resolution" do
    it "uses explicit entry when present" do
      with_tempdir do |root|
        Dir.mkdir_p(root.join("src"))
        File.write(root.join("src/main.cr"), "puts 1")

        entry = Altair::CLI::Watcher.resolve_entry(root, SpecApp, "src/main.cr")
        entry.should eq("src/main.cr")
      end
    end

    it "raises when explicit entry does not exist" do
      with_tempdir do |root|
        expect_raises(Altair::Error, "Specified entry file not found") do
          Altair::CLI::Watcher.resolve_entry(root, SpecApp, "src/missing.cr")
        end
      end
    end

    it "resolves from shard.yml name" do
      with_tempdir do |root|
        File.write(root.join("shard.yml"), "name: my_blog\nversion: 0.1.0\n")
        Dir.mkdir_p(root.join("src"))
        File.write(root.join("src/my_blog.cr"), "puts 1")

        entry = Altair::CLI::Watcher.resolve_entry(root, SpecApp)
        entry.should eq("src/my_blog.cr")
      end
    end

    it "resolves single .cr file inside src" do
      with_tempdir do |root|
        Dir.mkdir_p(root.join("src"))
        File.write(root.join("src/standalone.cr"), "puts 1")

        entry = Altair::CLI::Watcher.resolve_entry(root, SpecApp)
        entry.should eq("src/standalone.cr")
      end
    end

    it "resolves bin/altair.cr as fallback" do
      with_tempdir do |root|
        Dir.mkdir_p(root.join("bin"))
        File.write(root.join("bin/altair.cr"), "puts 1")

        entry = Altair::CLI::Watcher.resolve_entry(root, SpecApp)
        entry.should eq("bin/altair.cr")
      end
    end
  end

  describe "YAML configuration loading" do
    it "loads reload settings from config/altair.yml" do
      with_tempdir do |root|
        Dir.mkdir_p(root.join("config"))
        File.write(root.join("config/altair.yml"), <<-YAML
          test:
            reload: true
            reload_delay: 350ms
            watch:
              - src/
              - views/
            ignore:
              - .git/
              - tmp/
          YAML
        )

        config = Altair::Config.new
        Altair::CLI::Watcher.load_yaml_config(root, config)

        config.reload.enabled?.should be_true
        config.reload.delay.should eq(350.milliseconds)
        config.reload.watch_paths.should eq(["src/", "views/"])
        config.reload.ignore_paths.should eq([".git/", "tmp/"])
      end
    end
  end

  describe "file change detection and filtering" do
    it "detects added, modified and removed files" do
      with_tempdir do |root|
        Dir.mkdir_p(root.join("src"))
        file1 = root.join("src/file1.cr")
        File.write(file1, "first")

        watcher = Altair::CLI::Watcher.new(
          root: root,
          entry: "src/file1.cr",
          watch_paths: ["src"]
        )

        snap1 = watcher.scan_files
        snap1.keys.should contain("src/file1.cr")

        # No changes
        watcher.detect_changes(snap1, snap1).should be_empty

        # Modify file
        sleep 10.milliseconds
        File.write(file1, "second modification")
        snap2 = watcher.scan_files
        changes = watcher.detect_changes(snap1, snap2)
        changes.should eq(["src/file1.cr"])

        # Add file
        file2 = root.join("src/file2.cr")
        File.write(file2, "new file")
        snap3 = watcher.scan_files
        changes_add = watcher.detect_changes(snap2, snap3)
        changes_add.should eq(["src/file2.cr"])

        # Delete file
        File.delete(file1)
        snap4 = watcher.scan_files
        changes_del = watcher.detect_changes(snap3, snap4)
        changes_del.should eq(["src/file1.cr"])
      end
    end

    it "ignores sqlite database and journal files" do
      watcher = Altair::CLI::Watcher.new(
        root: Path.new("."),
        entry: "src/blog.cr"
      )

      watcher.ignored_file?("app.db", "db/app.db").should be_true
      watcher.ignored_file?("app.sqlite3", "db/app.sqlite3").should be_true
      watcher.ignored_file?("app.db-wal", "db/app.db-wal").should be_true
      watcher.ignored_file?("app.db-shm", "db/app.db-shm").should be_true
      watcher.ignored_file?("app.db-journal", "db/app.db-journal").should be_true
      watcher.ignored_file?("post.cr~", "src/post.cr~").should be_true
      watcher.ignored_file?(".post.cr.swp", "src/.post.cr.swp").should be_true
    end

    it "ignores configured directory patterns" do
      watcher = Altair::CLI::Watcher.new(
        root: Path.new("."),
        entry: "src/blog.cr",
        ignore_paths: [".git", "lib", "bin", "tmp", "node_modules"]
      )

      watcher.ignored_dir?(".git", ".git").should be_true
      watcher.ignored_dir?("lib", "lib").should be_true
      watcher.ignored_dir?("sqlite3", "lib/sqlite3").should be_true
      watcher.ignored_dir?("tmp", "tmp").should be_true
      watcher.ignored_dir?("controllers", "src/controllers").should be_false
    end
  end

  describe "binary slot management" do
    it "alternates binary slots between :a and :b" do
      watcher = Altair::CLI::Watcher.new(
        root: Path.new("/tmp/test_project"),
        entry: "src/main.cr"
      )

      path_a = watcher.target_binary_path(:a)
      path_b = watcher.target_binary_path(:b)

      path_a.to_s.should end_with(".altair/bin/server_a")
      path_b.to_s.should end_with(".altair/bin/server_b")
      path_a.should_not eq(path_b)
    end
  end

  describe "output formatting" do
    it "formats change detection output" do
      watcher = Altair::CLI::Watcher.new(
        root: Path.new("."),
        entry: "src/main.cr"
      )

      # Should not raise when printing change notifications
      watcher.print_change_detected(["src/controllers/users_controller.cr"])
      watcher.print_compilation_failure("syntax error", previous_running: true)
      watcher.print_compilation_failure("type mismatch", previous_running: false)
    end
  end
end
