# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Assets::Pipeline`, the conventional asset
# build: everything under the project's `assets/` directory is copied into
# `public/assets/<name>-<sha256-digest>.<ext>`, plus an unfingerprinted copy
# of every file so development links work without a rebuild. A
# `manifest.json` maps each logical path (`css/app.css`) to its
# fingerprinted public URL, which the view helpers prefer once present.
# Re-running replaces stale fingerprints of the same logical path.
require "digest"
require "json"
require "set"

module Altair
  module Assets
    # Builds fingerprinted assets and the manifest mapping logical paths to
    # their published URLs.
    #
    # ```
    # Altair::Assets::Pipeline.new(app.root).precompile
    # ```
    class Pipeline
      # The source directory inside the project root.
      SOURCE_DIR = "assets"

      # The output directory under `public/`.
      OUTPUT_DIR = "public/assets"

      # The URL prefix the output directory is served at (Static serves
      # everything inside `public/` from the site root).
      URL_PREFIX = "/assets"

      # One built asset: its logical path and the public URL it now lives at.
      record Entry, logical : String, url : String

      getter root : Path

      def initialize(@root : Path)
      end

      # Copies every file under `assets/` into `public/assets/`, writes the
      # manifest, and removes fingerprints left by earlier runs for logical
      # paths rebuilt this time. Returns the entries in walk order.
      def precompile : Array(Entry)
        built = [] of {String, String, String}
        each_source_file do |source, logical|
          content = File.read(source)
          digest = Digest::SHA256.hexdigest(content)[0, 12]
          built << {logical, digest, content}
        end

        remove_fingerprints(built.map(&.[0]))
        entries = built.map do |logical, digest, content|
          write_output(Fingerprint.name(logical, digest), content)
          write_output(logical, content)
          Entry.new(logical, "#{URL_PREFIX}/#{Fingerprint.name(logical, digest)}")
        end

        write_manifest(entries)
        entries
      end

      # The parsed manifest, or `{}` when the project was never compiled.
      def self.manifest_for(root : Path) : Hash(String, String)
        path = root / OUTPUT_DIR / "manifest.json"
        return {} of String => String unless File.exists?(path)
        Hash(String, String).from_json(File.read(path))
      rescue JSON::ParseException
        {} of String => String
      end

      private def each_source_file(& : Path, String -> Nil)
        files = [] of Path
        collect_files(root / SOURCE_DIR, files)
        files.sort.each do |file|
          relative = file.relative_to(root / SOURCE_DIR).to_s.gsub('\\', '/')
          yield file, relative
        end
      end

      private def collect_files(dir : Path, collected : Array(Path)) : Nil
        return unless Dir.exists?(dir.to_s)
        Dir.children(dir.to_s).each do |child|
          path = dir / child
          File.directory?(path.to_s) ? collect_files(path, collected) : collected << path
        end
      end

      private def write_output(name : String, content : String) : Nil
        target = root / OUTPUT_DIR / name
        Dir.mkdir_p(target.parent.to_s)
        File.write(target, content)
      end

      # Deletes every fingerprint-shaped file whose reconstructed logical
      # path is rebuilt by this run. Plain copies never match the shape and
      # survive untouched.
      private def remove_fingerprints(logicals : Array(String)) : Nil
        out_dir = root / OUTPUT_DIR
        return unless Dir.exists?(out_dir.to_s)
        rebuild = logicals.to_set
        existing = [] of Path
        collect_files(out_dir, existing)
        existing.each do |file|
          next unless parsed = Fingerprint.parse(file.basename)
          name_logical, _hex = parsed
          relative_dir = File.dirname(file.relative_to(out_dir).to_s)
          logical = relative_dir == "." ? name_logical : "#{relative_dir.gsub('\\', '/')}/#{name_logical}"
          File.delete(file) if rebuild.includes?(logical)
        end
      end

      # Builds and reads back the `<base>-<12-hex><ext>` fingerprinted file
      # names shared by `precompile` and pruning.
      module Fingerprint
        DIGEST_SIZE = 12

        # The fingerprinted name for a logical path at a given digest.
        def self.name(logical : String, digest : String) : String
          base, sep, ext = logical.rpartition(".")
          if sep.empty?
            "#{logical}-#{digest}"
          else
            "#{base}-#{digest}.#{ext}"
          end
        end

        # Splits a fingerprinted name into `{logical, digest}`, or nil when
        # the name does not carry this pipeline's fingerprint shape.
        def self.parse(name : String) : {String, String}?
          match = name.match(/\A(?<base>.+)-(?<hex>[0-9a-f]{12})(?<ext>\.[^.]*)?\z/)
          return unless match
          base = match["base"]
          ext = match["ext"]?
          hex = match["hex"]
          logical = ext ? "#{base}#{ext}" : base
          {logical, hex}
        end
      end

      private def write_manifest(entries : Array(Entry)) : Nil
        map = {} of String => String
        entries.each { |entry| map[entry.logical] = entry.url }
        out_dir = root / OUTPUT_DIR
        Dir.mkdir_p(out_dir.to_s)
        File.write(out_dir / "manifest.json", map.to_pretty_json)
      end
    end

    # Resolves a logical asset path to its public URL: the fingerprinted
    # URL from a compiled manifest when present, otherwise the plain copy
    # served from `/assets`. View helpers call this on every render; the
    # manifest read is a single small file.
    def self.url(root : Path, logical : String) : String
      normalized = logical.gsub(/\A\//, "")
      manifest = Pipeline.manifest_for(root)
      manifest[normalized]? || "#{Pipeline::URL_PREFIX}/#{normalized}"
    end
  end
end
