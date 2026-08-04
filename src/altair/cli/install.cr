# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::CLI::Install`, the `altair install` command.
# It copies the running binary into a user-writable directory on PATH
# (`~/.local/bin` on Unix, `%USERPROFILE%\.altair\bin` on Windows) so the
# command is available directly from any shell, without a wrapper script.
# The copy is checksum-verified and refuses to clobber an unrelated file
# unless `--force` is given.
require "digest/sha256"
require "file_utils"

module Altair
  module CLI
    class Install
      # The target file name for the platform (`.exe` on Windows).
      def self.executable_name : String
        {% if flag?(:win32) %}
          "altair.exe"
        {% else %}
          "altair"
        {% end %}
      end

      # The directory where the binary is installed by default: a
      # user-owned bin directory on PATH, not a system location that needs
      # root. Honors the `ALTAIR_BIN` override for custom installs.
      def self.default_bin_dir : Path
        if override = ENV["ALTAIR_BIN"]?
          return Path.new(override)
        end

        home = ENV["HOME"]? || ENV["USERPROFILE"]?
        raise Altair::Error.new("Cannot locate your home directory — set ALTAIR_BIN") if home.nil?
        home = home.rchop('/') if home.ends_with?('/')

        {% if flag?(:win32) %}
          Path.new(home, ".altair", "bin")
        {% else %}
          Path.new(home, ".local", "bin")
        {% end %}
      end

      # The full SHA-256 digest of `path` as lowercase hex. Streaming is
      # unnecessary at install time — the binary is a few megabytes — so we
      # read it whole and hash it.
      def self.sha256(path : Path) : String
        digest = Digest::SHA256.new
        digest.update(File.read(path.to_s))
        digest.final.hexstring
      end

      # Runs `altair install`, copying the running binary into the default or an
      # explicit `--dir`. Returns the process exit code. Passing `--force`
      # overwrites an existing, different file at the target.
      def self.run(args : Array(String)) : Int32
        force = args.includes?("--force")
        dir = option_value(args, "--dir") || option_value(args, "-d") || default_bin_dir

        install = new(Path.new(PROGRAM_NAME), dir)
        begin
          if install.install(force: force)
            puts "Installed Altair to #{install.target_path}"
            puts "Digest SHA-256: #{sha256(install.target_path)}"
            puts "Run `altair` from any directory."
          else
            puts "Altair already installed at #{install.target_path}."
          end
        rescue e : Altair::Error
          abort e.message
        end
        0
      end

      # The value of `flag` in `args` (the token after it), or nil.
      def self.option_value(args : Array(String), flag : String) : Path?
        index = args.index(flag)
        value = index.try { |i| args[i + 1]? }
        value.try { |v| Path.new(v) }
      end

      @source : Path

      # Creates an installer that copies `source` into `dir`.
      def initialize(@source : Path, @dir : Path)
      end

      # The full path the binary will be copied to.
      def target_path : Path
        @dir / self.class.executable_name
      end

      # Installs the binary. Returns true when a copy happened and false
      # when the target already matches the source. Raises `Altair::Error`
      # when the target holds different content unless `force` is given.
      def install(force : Bool = false) : Bool
        FileUtils.mkdir_p(@dir.to_s)

        target = target_path
        return false if File.exists?(target) && same?(target)

        if File.exists?(target) && !force
          raise Altair::Error.new(
            "#{target} already exists with different content — pass `--force` to overwrite"
          )
        end

        File.copy(@source.to_s, target.to_s)
        chmod_executable(target)
        true
      end

      # True when `path` is byte-for-byte identical to the source binary.
      private def same?(path : Path) : Bool
        self.class.sha256(path) == self.class.sha256(@source)
      end

      # Makes `path` executable on platforms that distinguish permissions.
      # No-op on Windows where the execute bit does not exist.
      private def chmod_executable(path : Path) : Nil
        {% if flag?(:win32) %}
          nil
        {% else %}
          File.chmod(path.to_s, File.info(path.to_s).permissions | File::Permissions.new(0o111))
        {% end %}
      end
    end
  end
end
