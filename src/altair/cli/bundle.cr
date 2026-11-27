# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::CLI::Bundle`, the shared filesystem contract for
# the curated offline documentation and starter examples. The bundle ships
# with the framework source (and the release source archive), is copied into
# `~/.altair/framework/<version>/bundle` by the installers, and is recorded in
# a generated project's `.altair/bundle.yml`. Nothing here writes into
# `lib/`, which stays managed by Shards.
require "yaml"
require "file_utils"

module Altair
  module CLI
    module Bundle
      # Bumped when the curated bundle layout or content changes incompatibly.
      REVISION = 1

      # Relative paths used by the framework, the installers and projects.
      SOURCE_DIR    = "bundle"
      DOCS_DIR      = "docs"
      EXAMPLES_DIR  = "examples"
      MANIFEST_PATH = ".altair/bundle.yml"
      CACHE_DIR     = ".altair/cache"

      # Provenance recorded in `.altair/bundle.yml`.
      record Manifest, version : String, revision : Int32, topics : Array(String), examples : Array(String) do
        # True when the manifest was produced by a different framework
        # version or bundle revision than the running CLI.
        def drift?(version : String = Altair::VERSION, revision : Int32 = REVISION) : Bool
          @version != version || @revision != revision
        end
      end

      # The framework-side bundle directory, searched in the same order the
      # installers place it: an explicit override, the current project's
      # `path:` dependency, `ALTAIR_PATH`, the installed framework copy, then
      # a framework checkout used as the current working directory.
      def self.source_root : Path?
        candidates = [] of Path
        if direct = ENV["ALTAIR_BUNDLE_PATH"]?
          candidates << Path.new(direct)
        end
        if project = Altair::CLI.find_project_dir
          if framework = framework_path_from_shard(project)
            candidates << framework.join(SOURCE_DIR)
          end
        end
        if env_path = ENV["ALTAIR_PATH"]?
          candidates << Path.new(env_path).join(SOURCE_DIR)
        end
        framework_root = Path[home_dir].join(".altair", "framework")
        candidates << framework_root.join(Altair::VERSION, SOURCE_DIR)
        if Dir.exists?(framework_root.to_s)
          versions = Dir.children(framework_root.to_s).sort!.reverse!
          versions.each { |version| candidates << framework_root.join(version, SOURCE_DIR) }
        end
        candidates << Path[Dir.current].join(SOURCE_DIR)
        candidates.each do |candidate|
          return candidate if valid_source?(candidate)
        end
        nil
      end

      # True when `path` carries both curated directories.
      def self.valid_source?(path : Path) : Bool
        Dir.exists?(path.join(DOCS_DIR).to_s) && Dir.exists?(path.join(EXAMPLES_DIR).to_s)
      end

      # The `altair` shard's local `path:` dependency in a generated project,
      # resolved relative to the project root. Nil for published releases.
      def self.framework_path_from_shard(project : Path) : Path?
        shard = project.join("shard.yml")
        return unless File.exists?(shard.to_s)
        parsed = YAML.parse(File.read(shard.to_s))
        altair = parsed["dependencies"]?.try(&.["altair"]?)
        raw = altair.try(&.["path"]?).try(&.as_s?)
        return unless raw
        path = Path.new(raw)
        path = project.join(path) unless path.absolute?
        Dir.exists?(path.to_s) ? path : nil
      rescue YAML::ParseException
        nil
      end

      # Curated topic names, taken from the files actually present so the
      # command never lists a guide that cannot be printed.
      def self.topics(root : Path? = nil) : Array(String)
        docs = docs_dir(root)
        return [] of String unless docs
        Dir.children(docs.to_s).select(&.ends_with?(".md"))
          .map(&.rchop(".md")).sort!
      end

      # Curated example names, taken from directories carrying a README.
      def self.examples(root : Path? = nil) : Array(String)
        examples = examples_dir(root)
        return [] of String unless examples
        Dir.children(examples.to_s).select do |name|
          File.exists?(examples.join(name, "README.md").to_s)
        end.sort!
      end

      # The source docs directory, or the project-local cache when no
      # framework bundle is installed.
      def self.docs_dir(root : Path? = nil) : Path?
        if root
          cached = root.join(CACHE_DIR, DOCS_DIR)
          return cached if Dir.exists?(cached.to_s)
        end
        source_root.try(&.join(DOCS_DIR))
      end

      # The source examples directory, or the project-local cache.
      def self.examples_dir(root : Path? = nil) : Path?
        if root
          cached = root.join(CACHE_DIR, EXAMPLES_DIR)
          return cached if Dir.exists?(cached.to_s)
        end
        source_root.try(&.join(EXAMPLES_DIR))
      end

      # Exact text of a guide in the source bundle or a project cache.
      def self.topic_content(name : String, root : Path? = nil) : String?
        path = docs_dir(root).try(&.join("#{name}.md"))
        return unless path && File.exists?(path.to_s)
        File.read(path.to_s)
      end

      # Exact text of an example's README.
      def self.example_readme(name : String, root : Path? = nil) : String?
        path = examples_dir(root).try(&.join(name, "README.md"))
        return unless path && File.exists?(path.to_s)
        File.read(path.to_s)
      end

      # Reads the manifest written into a generated project.
      def self.read_manifest(root : Path? = nil) : Manifest?
        path = (root || Path[Dir.current]).join(MANIFEST_PATH)
        return unless File.exists?(path.to_s)
        node = YAML.parse(File.read(path.to_s))
        version = node["framework"]?.try(&.as_s?) || node["version"]?.try(&.as_s?) || ""
        revision = node["revision"]?.try(&.as_i?) || 0
        topics = node["topics"]?.try(&.as_a?).try(&.map(&.as_s)) || [] of String
        examples = node["examples"]?.try(&.as_a?).try(&.map(&.as_s)) || [] of String
        Manifest.new(version, revision, topics, examples)
      rescue YAML::ParseException
        nil
      end

      # Writes `.altair/bundle.yml` with the running framework version and
      # the curated names present in the installed bundle. Deterministic:
      # the same framework always writes the same bytes.
      def self.write_manifest(root : Path, bundle : Path? = nil) : Manifest
        bundle ||= source_root
        manifest = Manifest.new(
          Altair::VERSION,
          REVISION,
          bundle ? Dir.children(bundle.not_nil!.join(DOCS_DIR).to_s).select(&.ends_with?(".md")).map(&.rchop(".md")).sort! : [] of String,
          bundle ? examples_in(bundle.not_nil!) : [] of String
        )
        Dir.mkdir_p(root.join(".altair").to_s)
        File.write(root.join(MANIFEST_PATH).to_s, render_manifest(manifest))
        manifest
      end

      # The exact manifest text. Kept separate so generator specs can assert
      # deterministic output.
      def self.render_manifest(manifest : Manifest) : String
        String.build do |io|
          io << "# Generated by Altair " << Altair::VERSION << " — do not edit.\n"
          io << "revision: " << manifest.revision << '\n'
          io << "framework: " << manifest.version << '\n'
          io << "topics:\n"
          manifest.topics.each { |topic| io << "  - " << topic << '\n' }
          io << "examples:\n"
          manifest.examples.each { |name| io << "  - " << name << '\n' }
        end
      end

      # Copy the installed guides and examples into the project cache.
      # Returns true when a source bundle was found.
      def self.refresh(root : Path, bundle : Path? = nil) : Bool
        source = bundle || source_root
        return false unless source && valid_source?(source)
        FileUtils.rm_rf(root.join(CACHE_DIR).to_s)
        copy_tree(source.join(DOCS_DIR), root.join(CACHE_DIR, DOCS_DIR))
        copy_tree(source.join(EXAMPLES_DIR), root.join(CACHE_DIR, EXAMPLES_DIR))
        write_manifest(root, source)
        true
      end

      # Copies curated example sources into `examples/altair/` without their
      # own shard metadata, so they compile against the project's shard.
      # Returns the copied names.
      def self.copy_examples(root : Path, names : Array(String), bundle : Path? = nil) : Array(String)
        source = if bundle
                   bundle.join(EXAMPLES_DIR)
                 else
                   examples_dir(root) || source_root.try(&.join(EXAMPLES_DIR))
                 end
        raise Altair::Error.new("No examples bundle found — install the framework bundle or pass ALTAIR_BUNDLE_PATH") unless source
        available = examples_in(source.parent)
        copied = [] of String
        names.each do |name|
          raise Altair::Error.new("Unknown example `#{name}` — run `altair examples` to list them") unless available.includes?(name)
          target = root.join("examples", "altair", name)
          FileUtils.rm_rf(target.to_s)
          copy_tree(source.join(name), target)
          copied << name
        end
        write_manifest(root, bundle || source.parent)
        copied
      end

      # Example names in an explicit bundle directory.
      private def self.examples_in(bundle : Path) : Array(String)
        dir = bundle.join(EXAMPLES_DIR)
        return [] of String unless Dir.exists?(dir.to_s)
        Dir.children(dir.to_s).select { |name| File.exists?(dir.join(name, "README.md").to_s) }.sort!
      end

      # True when the project's recorded bundle differs from this CLI.
      def self.drift?(root : Path) : Bool
        manifest = read_manifest(root)
        manifest ? manifest.drift? : false
      end

      # Emits a warning when a project-local bundle was written by a
      # different framework version or revision. Called by `altair update`
      # and `altair docs` after upgrade.
      def self.warn_if_drift(root : Path? = nil) : Nil
        project = root || Altair::CLI.find_project_dir
        return unless project
        manifest = read_manifest(project)
        return unless manifest && manifest.drift?
        STDERR.puts "Note: .altair/bundle.yml was written by Altair #{manifest.version} (bundle revision #{manifest.revision});"
        STDERR.puts "current CLI is #{Altair::VERSION}. Run `altair docs --refresh` to update it."
      end

      # Recursively copies the contents of `from` into `to`, creating `to`.
      private def self.copy_tree(from : Path, to : Path) : Nil
        FileUtils.mkdir_p(to.to_s)
        Dir.children(from.to_s).each do |entry|
          source = from.join(entry)
          target = to.join(entry)
          File.directory?(source.to_s) ? copy_tree(source, target) : FileUtils.cp(source.to_s, target.to_s)
        end
      end

      private def self.home_dir : String
        ENV["HOME"]? || ENV["USERPROFILE"]? || "."
      end
    end
  end
end
