# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::CLI::Update`, the `altair update` command. It
# checks GitHub for the latest release, downloads the binary for the
# current platform, verifies its SHA-256 digest against the published
# `SHA256SUMS` before replacing the running executable, and reports the
# result. `--check` only reports whether a newer version is available;
# `--force` reinstalls even when the current version is already the
# latest.
require "http/client"
require "json"
require "digest/sha256"

module Altair
  module CLI
    class Update
      # The GitHub repository the framework is published to.
      REPOSITORY = "Arab-Open-Source/Altair"

      # The latest release metadata endpoint.
      LATEST_URL = "https://api.github.com/repos/#{REPOSITORY}/releases/latest"

      # The base download URL for a release's assets.
      DOWNLOAD_URL = "https://github.com/#{REPOSITORY}/releases/download"

      # The asset name for the current platform, e.g. `altair-linux-amd64`
      # (`altair-windows-amd64.exe` on Windows). Nil for unknown platforms.
      def self.platform_asset_name : String?
        os = {% if flag?(:win32) %}
               "windows"
             {% elsif flag?(:linux) %}
               "linux"
             {% elsif flag?(:darwin) %}
               "macos"
             {% else %}
               nil
             {% end %}
        arch = {% if flag?(:x86_64) %}
                 "amd64"
               {% elsif flag?(:aarch64) %}
                 "arm64"
               {% else %}
                 nil
               {% end %}
        return if os.nil? || arch.nil?
        ext = {{ flag?(:win32) ? ".exe" : "" }}
        "altair-#{os}-#{arch}#{ext}"
      end

      # Runs `altair update`. Returns the process exit code.
      def self.run(args : Array(String)) : Int32
        check = args.includes?("--check")
        force = args.includes?("--force")

        asset_name = platform_asset_name
        if asset_name.nil?
          abort "Unsupported platform — please install from source (`shards build altair && ./bin/altair install --force`)."
        end

        latest = latest_version
        if latest.nil?
          abort "Could not reach #{REPOSITORY} releases — check your network and try again."
        end

        current = "v#{Altair::VERSION}"
        newer = compare_versions(latest, current) > 0

        if check
          if newer
            puts "A newer version is available: #{current} -> #{latest}."
            return 1
          else
            puts "Altair is already up to date (#{current})."
            return 0
          end
        end

        unless newer || force
          puts "Altair is already up to date (#{current})."
          return 0
        end

        install_new(latest, asset_name)
        0
      end

      # Compares two semver `vX.Y.Z` tags, returning -1, 0 or 1.
      def self.compare_versions(a : String, b : String) : Int32
        av = a.lchop('v').split('.').map(&.to_i)
        bv = b.lchop('v').split('.').map(&.to_i)
        [av.size, bv.size].max.times do |i|
          return 1 if (av[i]? || 0) > (bv[i]? || 0)
          return -1 if (av[i]? || 0) < (bv[i]? || 0)
        end
        0
      end

      # The tag of the latest GitHub release (`v1.2.3`), or nil on failure.
      def self.latest_version : String?
        response = ::HTTP::Client.get(LATEST_URL)
        return unless response.success?
        body = JSON.parse(response.body)
        body["tag_name"]?.try(&.as_s)
      rescue IO::Error
        nil
      rescue Socket::Addrinfo::Error
        nil
      rescue JSON::ParseException
        nil
      end

      # Downloads `asset_name` from the `tag` release, verifies it against
      # the published `SHA256SUMS`, and replaces the running binary.
      def self.install_new(tag : String, asset_name : String) : Nil
        binary_url = "#{DOWNLOAD_URL}/#{tag}/#{asset_name}"
        sums_url = "#{DOWNLOAD_URL}/#{tag}/SHA256SUMS"

        binary = download(binary_url)
        sums = download(sums_url)
        expected = expected_digest(sums, asset_name)
        if expected.nil?
          abort "No checksum for #{asset_name} in SHA256SUMS."
        end

        actual = Digest::SHA256.hexdigest(binary)
        unless actual == expected
          abort "Checksum mismatch for #{asset_name}: expected #{expected}, got #{actual}."
        end

        target = current_executable
        if target.nil?
          abort "Cannot locate the running binary — reinstall with `altair install`."
        end

        write_atomic(target, binary)
        puts "Updated Altair to #{tag} (#{actual[0, 12]}...)."
      end

      # The path of the running binary, falling back to the installed
      # location on `PATH`.
      def self.current_executable : String?
        Process.executable_path || PROGRAM_NAME
      end

      # The hex SHA-256 of `asset_name` listed in `sums` (the `SHA256SUMS`
      # format is `<digest>  <name>`), or nil when absent.
      def self.expected_digest(sums : String, asset_name : String) : String?
        sums.each_line do |line|
          digest, _, name = line.partition("  ")
          digest = line.partition(" ")[0] if digest.empty?
          return digest if name.strip == asset_name
        end
        nil
      end

      # Fetches `url`, raising on any failure.
      def self.download(url : String) : String
        response = ::HTTP::Client.get(url)
        raise Altair::Error.new("Failed to download #{url} (#{response.status}).") unless response.success?
        response.body
      end

      # Writes `content` to `path` replacing the running binary. On Unix the
      # running binary can be overwritten in place, so we write through a
      # temp file and rename — the rename is atomic and keeps permissions.
      private def self.write_atomic(path : String, content : String) : Nil
        {% if flag?(:win32) %}
          File.write(path, content)
        {% else %}
          temp = "#{path}.new"
          File.write(temp, content)
          File.chmod(temp, 0o755)
          File.rename(temp, path)
        {% end %}
      end
    end
  end
end
