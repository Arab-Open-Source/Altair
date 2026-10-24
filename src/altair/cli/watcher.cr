# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::CLI::Watcher`, the development hot reload supervisor.
# It monitors project files for changes, debounces rapid edits, rebuilds the
# application in a separate child process, and restarts the server only after a
# successful compilation — keeping the previous server instance running uninterrupted
# whenever compilation errors occur.
require "process"
require "socket"
require "yaml"

module Altair
  module CLI
    class Watcher
      # Options parsed from CLI flags or configuration for the server / watcher.
      class Options
        property? watch : Bool? = nil
        property port : Int32? = nil
        property host : String? = nil
        property env : String? = nil
        property delay : Time::Span? = nil
        property poll_interval : Time::Span? = nil
        property entry : String? = nil
        property extra_args : Array(String) = [] of String

        def self.parse(args : Array(String)) : Options
          options = Options.new
          i = 0
          while i < args.size
            arg = args[i]
            case arg
            when "-p", "--port"
              i += 1
              if val = args[i]?
                options.port = val.to_i?
              end
            when "-b", "-h", "--bind", "--host"
              i += 1
              options.host = args[i]?
            when "-e", "--env"
              i += 1
              options.env = args[i]?
            when "-w", "--watch"
              options.watch = true
            when "--no-watch"
              options.watch = false
            when "--delay"
              i += 1
              if val = args[i]?
                options.delay = parse_duration(val)
              end
            when "--poll"
              i += 1
              if val = args[i]?
                options.poll_interval = parse_duration(val)
              end
            when "--entry"
              i += 1
              options.entry = args[i]?
            when "--help"
              puts help
              exit 0
            else
              options.extra_args << arg
            end
            i += 1
          end
          options
        end

        # Parses a duration string such as `200ms`, `1.5s`, or `2m`.
        def self.parse_duration(val : String) : Time::Span
          val = val.strip
          if val.ends_with?("ms")
            num = val.rchop("ms").to_f? || 200.0
            num.milliseconds
          elsif val.ends_with?("s")
            num = val.rchop("s").to_f? || 1.0
            (num * 1000).to_i64.milliseconds
          elsif val.ends_with?("m")
            num = val.rchop("m").to_f? || 1.0
            (num * 60 * 1000).to_i64.milliseconds
          else
            num = val.to_f? || 200.0
            num.milliseconds
          end
        end

        def self.help : String
          <<-TXT
            Usage: altair server [options]

            Options:
              -p, --port PORT      port to listen on (default: 3000)
              -b, --bind HOST      host to bind to (default: 0.0.0.0)
              -e, --env ENV        environment to run in (default: development)
              -w, --watch          enable hot reload watcher (default in development)
                  --no-watch       disable hot reload watcher
                  --delay DURATION debounce delay for hot reload (default: 200ms)
                  --entry PATH     application entrypoint file to compile
              -h, --help           print this help
            TXT
        end
      end

      # Snapshot of a watched file's modification time and size.
      record FileSnapshot, mtime : Time, size : Int64

      # Configuration options for the watcher.
      getter root : Path
      getter entry : String
      getter watch_paths : Array(String)
      getter ignore_paths : Array(String)
      getter debounce_delay : Time::Span
      getter poll_interval : Time::Span
      getter port : Int32
      getter host : String
      getter current_process : Process? = nil
      getter? running : Bool = false
      getter active_binary_slot : Symbol = :a

      def initialize(
        @root : Path,
        @entry : String,
        @watch_paths : Array(String) = ["src", "views", "config"],
        @ignore_paths : Array(String) = [".git", "lib", "bin", "tmp", "log", "node_modules", "db", ".altair"],
        @debounce_delay : Time::Span = 200.milliseconds,
        @poll_interval : Time::Span = 150.milliseconds,
        @port : Int32 = 3000,
        @host : String = "0.0.0.0",
        @server_args : Array(String) = [] of String,
      )
        @snapshot = Hash(String, FileSnapshot).new
      end

      # Builds a Watcher instance for an application class and parsed options.
      def self.new(app_class, options : Options = Options.new) : Watcher
        root = Path.new(Dir.current)
        app = app_class.instance rescue nil
        config = app ? app.config : Altair::Config.new

        # Load file-based reload configuration if present (e.g. config/altair.yml or config/watch.yml)
        load_yaml_config(root, config)

        reload = config.reload
        entry = resolve_entry(root, app_class, options.entry || reload.entry)

        watch_paths = reload.watch_paths.dup
        ignore_paths = reload.ignore_paths.dup
        debounce = options.delay || reload.delay
        poll = options.poll_interval || reload.poll_interval
        port = options.port || config.port
        host = options.host || config.host

        new(
          root: root,
          entry: entry,
          watch_paths: watch_paths,
          ignore_paths: ignore_paths,
          debounce_delay: debounce,
          poll_interval: poll,
          port: port,
          host: host,
          server_args: options.extra_args
        )
      end

      # Determines whether watch mode should be used.
      def self.should_watch?(app_class, options : Options = Options.new) : Bool
        # Never watch if running inside the child worker process
        return false if ENV["ALTAIR_CHILD_PROCESS"]? == "1"

        # Explicit CLI flag takes precedence
        if opt_watch = options.watch?
          return opt_watch
        end

        # Respect explicit environment flag or ENV variable
        if env_str = options.env || ENV["ALTAIR_ENV"]?
          case env_str.downcase
          when "production", "prod", "test"
            return false
          end
        else
          return false if Altair.env.production? || Altair.env.test?
        end

        # Check config setting
        app = app_class.instance rescue nil
        if app
          return app.config.reload.enabled?
        end

        true
      end

      # Resolves the application entry point to compile.
      def self.resolve_entry(root : Path, app_class, explicit_entry : String? = nil) : String
        if explicit_entry
          full_path = root.join(explicit_entry)
          return explicit_entry if File.exists?(full_path)
          raise Altair::Error.new("Specified entry file not found: #{explicit_entry}")
        end

        # 1. Check shard.yml name
        shard_path = root.join("shard.yml")
        if File.exists?(shard_path)
          begin
            parsed = YAML.parse(File.read(shard_path))
            if shard_name = parsed["name"]?.try(&.as_s?)
              candidate = "src/#{shard_name}.cr"
              return candidate if File.exists?(root.join(candidate))
            end
          rescue
            # Ignore YAML parse errors
          end
        end

        # 2. Check app class name underscore
        class_name = app_class.to_s.split("::").last
        underscored = Inflector.underscore(class_name)
        candidate = "src/#{underscored}.cr"
        return candidate if File.exists?(root.join(candidate))

        # 3. Check any single .cr file directly inside src/
        src_dir = root.join("src")
        if Dir.exists?(src_dir)
          cr_files = Dir.children(src_dir).select { |file| file.ends_with?(".cr") && File.file?(src_dir.join(file)) }
          return "src/#{cr_files.first}" if cr_files.size == 1
        end

        # 4. Check bin/altair.cr
        if File.exists?(root.join("bin/altair.cr"))
          return "bin/altair.cr"
        end

        raise Altair::Error.new("Could not determine application entrypoint in #{root}. Specify --entry PATH.")
      end

      # Loads reload settings from `config/altair.yml` or `config/watch.yml` if present.
      def self.load_yaml_config(root : Path, config : Altair::Config) : Nil
        path = [root.join("config/altair.yml"), root.join("config/watch.yml")].find { |candidate| File.exists?(candidate) }
        return unless path

        begin
          parsed = YAML.parse(File.read(path))
          env_name = Altair.env.to_s.downcase
          section = parsed[env_name]? || parsed["default"]?
          return unless section

          if reload_val = section["reload"]?
            config.reload.enabled = reload_val.as_bool? || true
          end
          if delay_val = section["reload_delay"]?
            raw = delay_val.as_s? || delay_val.to_s
            config.reload.delay = Options.parse_duration(raw)
          end
          if watch_val = section["watch"]?.try(&.as_a?)
            config.reload.watch_paths = watch_val.compact_map(&.as_s?)
          end
          if ignore_val = section["ignore"]?.try(&.as_a?)
            config.reload.ignore_paths = ignore_val.compact_map(&.as_s?)
          end
        rescue
          # Ignore malformed YAML and keep defaults
        end
      end

      # Takes a snapshot of all watched files with their modification times and sizes.
      def scan_files : Hash(String, FileSnapshot)
        result = Hash(String, FileSnapshot).new
        @watch_paths.each do |watch_dir|
          full_dir = @root.join(watch_dir)
          if Dir.exists?(full_dir)
            scan_directory(full_dir, result)
          elsif File.exists?(full_dir)
            rel_path = full_dir.to_s.sub(/^#{@root}\/?/, "")
            record_file(full_dir, rel_path, result)
          end
        end
        result
      end

      # Recursively scans a directory.
      private def scan_directory(dir : Path, result : Hash(String, FileSnapshot)) : Nil
        Dir.each_child(dir) do |entry|
          child_path = dir.join(entry)
          rel_path = child_path.to_s.sub(/^#{@root}\/?/, "")

          if Dir.exists?(child_path)
            next if ignored_dir?(entry, rel_path)
            scan_directory(child_path, result)
          elsif File.exists?(child_path)
            next if ignored_file?(entry, rel_path)
            record_file(child_path, rel_path, result)
          end
        end
      rescue File::NotFoundError
        # Directory was removed during scan
      end

      # Records a single file in the snapshot.
      private def record_file(path : Path, rel_path : String, result : Hash(String, FileSnapshot)) : Nil
        info = File.info(path)
        result[rel_path] = FileSnapshot.new(info.modification_time, info.size)
      rescue File::NotFoundError
        # File was removed during scan
      end

      # Checks if a directory should be excluded from watching.
      def ignored_dir?(name : String, rel_path : String) : Bool
        return true if name.starts_with?(".")
        clean_rel = rel_path.rstrip('/')
        @ignore_paths.any? do |pattern|
          clean_pat = pattern.strip('/')
          name == clean_pat || clean_rel == clean_pat || clean_rel.starts_with?("#{clean_pat}/")
        end
      end

      # Checks if a file should be excluded from watching.
      def ignored_file?(name : String, rel_path : String) : Bool
        return true if name.starts_with?(".")
        return true if name.ends_with?("~") || name.ends_with?(".swp") || name.ends_with?(".tmp")
        # Ignore sqlite database files
        return true if name.ends_with?(".db") || name.ends_with?(".sqlite3") ||
                       name.ends_with?(".db-wal") || name.ends_with?(".db-shm") ||
                       name.ends_with?(".db-journal")
        clean_rel = rel_path.lstrip('/')
        @ignore_paths.any? do |pattern|
          clean_pat = pattern.strip('/')
          clean_rel == clean_pat || clean_rel.starts_with?("#{clean_pat}/")
        end
      end

      # Compares previous and current snapshots, returning a list of changed paths.
      def detect_changes(previous : Hash(String, FileSnapshot), current : Hash(String, FileSnapshot)) : Array(String)
        changed = [] of String
        current.each do |path, state|
          if prev = previous[path]?
            if prev.mtime != state.mtime || prev.size != state.size
              changed << path
            end
          else
            changed << path
          end
        end
        previous.each_key do |path|
          unless current.has_key?(path)
            changed << path
          end
        end
        changed
      end

      # Formats and prints detected file changes matching the specification.
      def print_change_detected(changed_files : Array(String)) : Nil
        puts ""
        if changed_files.size == 1
          puts "[Altair] Change detected"
        else
          puts "[Altair] Change detected (#{changed_files.size} files)"
        end
        puts ""
        puts "Modified:"
        changed_files.first(10).each do |file|
          puts "  #{file}"
        end
        if changed_files.size > 10
          puts "  ... and #{changed_files.size - 10} more"
        end
        puts ""
      end

      # Formats and prints compilation failure messages matching the specification.
      def print_compilation_failure(error_output : String, previous_running : Bool) : Nil
        separator = "─" * 40
        puts ""
        puts separator
        puts ""
        puts "Compilation failed"
        puts ""
        puts error_output.strip
        puts ""
        if previous_running
          puts "Previous build is still running."
        end
        puts "Waiting for file changes..."
        puts ""
        puts separator
        puts ""
      end

      # Starts the watcher supervisor: builds the application, boots the server,
      # and watches for file modifications in a debounced loop.
      def start : Nil
        @running = true
        setup_signal_traps
        ensure_build_directory

        # Initial build
        initial_binary = target_binary_path(:a)
        status, output = compile(initial_binary)

        if status.success?
          @active_binary_slot = :a
          restart_server(initial_binary)
        else
          print_compilation_failure(output, previous_running: false)
        end

        # Seed initial file snapshot
        @snapshot = scan_files

        # Main watch loop
        while @running
          sleep @poll_interval

          current = scan_files
          changes = detect_changes(@snapshot, current)

          next if changes.empty?

          # Debounce rapid file modifications
          accumulated_changes = Set(String).new(changes)
          deadline = Time.instant + @debounce_delay

          while Time.instant < deadline
            sleep 50.milliseconds
            more_current = scan_files
            more_changes = detect_changes(current, more_current)
            unless more_changes.empty?
              accumulated_changes.concat(more_changes)
              current = more_current
              deadline = Time.instant + @debounce_delay
            end
          end

          @snapshot = current
          trigger_rebuild(accumulated_changes.to_a)
        end
      ensure
        shutdown
      end

      # Rebuilds the project and restarts the server if compilation succeeds.
      private def trigger_rebuild(changed_files : Array(String)) : Nil
        print_change_detected(changed_files)
        puts "Rebuilding..."
        puts ""

        next_slot = @active_binary_slot == :a ? :b : :a
        next_binary = target_binary_path(next_slot)

        build_start = Time.instant
        status, error_output = compile(next_binary)
        duration = (Time.instant - build_start).total_seconds.round(2)

        if status.success?
          puts "Build completed in #{duration}s"
          puts ""
          puts "Restarting server..."
          puts ""
          @active_binary_slot = next_slot
          restart_server(next_binary)
          puts "Server ready"
        else
          prev_running = @current_process.try(&.exists?) || false
          print_compilation_failure(error_output, previous_running: prev_running)
        end
      end

      # Compiles the application entrypoint into `output_path`.
      def compile(output_path : Path) : {Process::Status, String}
        args = ["build", @entry, "-o", output_path.to_s]
        output = IO::Memory.new

        status = Process.run(
          "crystal",
          args,
          chdir: @root.to_s,
          output: output,
          error: output
        )

        {status, output.to_s}
      end

      # Restarts the server using the compiled binary at `binary_path`.
      private def restart_server(binary_path : Path) : Nil
        stop_current_process

        env = ENV.to_h
        env["ALTAIR_CHILD_PROCESS"] = "1"
        env["PORT"] = @port.to_s
        env["HOST"] = @host

        # If bin/altair.cr was used as entrypoint, tell it to run server without watching
        args = @server_args.dup
        if @entry == "bin/altair.cr" && !args.includes?("server")
          args = ["server", "--no-watch"] + args
        end

        process = Process.new(
          binary_path.to_s,
          args: args,
          env: env,
          chdir: @root.to_s,
          output: Process::Redirect::Inherit,
          error: Process::Redirect::Inherit,
          input: Process::Redirect::Inherit
        )
        @current_process = process

        # Wait until the HTTP server is accepting connections
        wait_until_ready(@host, @port, timeout: 5.seconds)
      end

      # Gracefully stops the running child server process.
      private def stop_current_process : Nil
        if process = @current_process
          begin
            if process.exists?
              process.signal(Signal::TERM)
              deadline = Time.instant + 2.seconds
              while process.exists? && Time.instant < deadline
                sleep 50.milliseconds
              end
              if process.exists?
                process.signal(Signal::KILL)
              end
              process.wait rescue nil
            end
          rescue
            # Process already terminated
          ensure
            @current_process = nil
          end
        end
      end

      # Probes the host and port until the server is reachable.
      private def wait_until_ready(host : String, port : Int32, timeout : Time::Span) : Nil
        deadline = Time.instant + timeout
        probe_host = (host == "0.0.0.0" || host.empty?) ? "127.0.0.1" : host

        while Time.instant < deadline
          begin
            socket = TCPSocket.new(probe_host, port)
            socket.close
            return
          rescue IO::Error
            sleep 50.milliseconds
          end
        end
      end

      # Shuts down the watcher and any running child server process.
      def shutdown : Nil
        @running = false
        stop_current_process
        cleanup_binaries
      end

      # Ensures `.altair/bin` directory exists inside the project root.
      private def ensure_build_directory : Nil
        Dir.mkdir_p(@root.join(".altair/bin"))
      end

      # Path to alternating binary slots: `:a` and `:b`.
      def target_binary_path(slot : Symbol) : Path
        @root.join(".altair/bin/server_#{slot}")
      end

      # Removes temporary compiled binaries.
      private def cleanup_binaries : Nil
        [:a, :b].each do |slot|
          path = target_binary_path(slot)
          File.delete(path) if File.exists?(path)
        end
      rescue
        # Ignore cleanup errors on exit
      end

      # Configures signal handling for clean shutdown on Ctrl-C.
      private def setup_signal_traps : Nil
        Process.on_terminate do
          shutdown
          exit 0
        end
      end
    end
  end

  # Alias under Altair::Dev for ergonomic reference
  module Dev
    alias Watcher = Altair::CLI::Watcher
  end
end
