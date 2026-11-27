# Altair — the batteries-included web framework for Crystal.
#
# This file defines `altair docs`, the offline documentation reader. Guides
# are read from the curated bundle installed with the framework (or from the
# project-local `.altair/cache`); when no bundle is installed, the references
# embedded in the CLI are used. No network access is needed to print a topic.
require "process"

module Altair
  module CLI
    class Docs
      # Website pages opened by `--open`. Topics without a dedicated page
      # point at the closest published guide.
      WEB_BASE   = "https://arab-open-source.github.io/Altair/docs"
      TOPIC_URLS = {
        "getting_started"   => "usage",
        "cli"               => "cli",
        "configuration"     => "configuration",
        "routing"           => "routing",
        "record"            => "record",
        "auth"              => "sessions",
        "jobs"              => "features",
        "testing"           => "testing",
        "deployment"        => "deployment",
        "observability"     => "observability",
        "read_replicas"     => "read_replicas",
        "docs_and_examples" => "docs_and_examples",
        "troubleshooting"   => "install",
      }

      # Reference topics available from the CLI itself, used only when no
      # curated bundle can be found.
      EMBEDDED_TOPICS = %w[
        getting_started cli configuration routing controllers views record
        auth jobs assets testing deployment observability read_replicas
        docs_and_examples middleware cache storage cable redis gotchas
        troubleshooting
      ]

      # Runs `altair docs`. Returns a process exit code.
      def self.run(args : Array(String)) : Int32
        list = args.includes?("--list")
        open = args.includes?("--open")
        refresh = args.includes?("--refresh")
        words = args.reject(&.starts_with?("--"))

        if refresh
          root = Altair::CLI.find_project_dir
          if root.nil?
            STDERR.puts "--refresh must be run inside an Altair project."
            return 1
          end
          unless Bundle.refresh(root.not_nil!)
            STDERR.puts "No framework bundle found — set ALTAIR_BUNDLE_PATH or install the framework source."
            return 1
          end
          puts "Refreshed .altair/cache and .altair/bundle.yml from Altair #{Altair::VERSION}."
          return 0
        end

        return list_topics if list || words.empty?

        topic = resolve_topic(words)
        if topic.nil?
          STDERR.puts "Unknown docs topic: #{words.join(" ")}"
          STDERR.puts "Available topics: #{all_topics.join(", ")}"
          return 1
        end

        if open
          return open_topic(topic)
        end

        content = topic_content(topic)
        if content.nil?
          STDERR.puts "No guide found for topic `#{topic}`."
          return 1
        end
        puts section_for(content, words)
        Bundle.warn_if_drift
        0
      end

      # Prints every available topic with a one-line description from its
      # first heading or a short embedded label.
      def self.list_topics : Int32
        puts "Available Altair docs topics (offline):"
        all_topics.each do |name|
          content = topic_content(name)
          title = content.try { |text| text.lines.find(&.starts_with?("# ")).try(&.lchop("# ").strip) }
          puts "  #{name.ljust(20)} #{title || "reference"}"
        end
        puts ""
        puts "Read one with: altair docs <topic>   e.g. altair docs record associations"
        puts "Add --open to open the matching online guide."
        0
      end

      # Union of curated bundle topics and embedded reference topics.
      def self.all_topics : Array(String)
        (Bundle.topics(Altair::CLI.find_project_dir) + EMBEDDED_TOPICS).uniq.sort!
      end

      # Resolves words such as `["record", "associations"]` to the longest
      # matching topic name, preferring the bundle over embedded references.
      def self.resolve_topic(words : Array(String)) : String?
        return if words.empty?
        joined = words.join("_")
        available = all_topics
        return joined if available.includes?(joined)
        words.each do |word|
          return word if available.includes?(word)
          hit = available.find(&.starts_with?(word))
          return hit if hit
        end
        nil
      end

      # Exact guide text, falling back to references compiled into the CLI.
      def self.topic_content(name : String) : String?
        Bundle.topic_content(name, Altair::CLI.find_project_dir) || embedded_content(name)
      end

      # Text embedded in the binary for offline use without a bundle.
      def self.embedded_content(name : String) : String?
        case name
        when "getting_started"
          "# Getting started\n\n" \
          "Install the CLI, run `altair new blog -d sqlite`, then `shards install`,\n" \
          "`bin/altair db:migrate` and `bin/altair server`. Crystal 1.22.3 or newer is required.\n"
        when "deployment"
          "# Deployment\n\n" \
          "`altair new` writes a multi-stage Dockerfile, `.dockerignore` and `compose.yml`.\n" \
          "Build with `docker compose build`, apply migrations explicitly with\n" \
          "`docker compose run --rm web ./bin/altair db:migrate`, then start with\n" \
          "`docker compose up -d` and check `/health`. Migrations never run at boot.\n"
        when "observability"
          "# Observability\n\n" \
          "Generated projects enable `/health` and `/metrics` through `config.observability`.\n"
        when "read_replicas"
          "# Read replicas\n\n" \
          "Set `config.db_replica_url`; writes and transactions use the primary, and\n" \
          "`Relation#on_primary` forces a read onto it. `QueryEvent#target` and `/metrics`\n" \
          "report per-target counters. Replica routing is experimental.\n"
        when "docs_and_examples"
          "# Docs and examples\n\n" \
          "`altair docs` and `altair examples` work offline from the installed bundle.\n" \
          "`altair new --with-examples` copies curated programs into `examples/altair/`.\n"
        when "troubleshooting"
          "# Troubleshooting\n\n" \
          "Use `altair docs --list` for exact topic names. Set `ALTAIR_BUNDLE_PATH`\n" \
          "to a directory with `docs/` and `examples/` when no bundle is found.\n"
        else
          Generators::New.new("docs").reference_doc(name)
        end
      end

      # When lookup words name a markdown heading, prints only that section;
      # otherwise prints the whole guide. Keeps `altair docs record
      # associations` focused without a separate index file.
      def self.section_for(content : String, words : Array(String)) : String
        return content if words.size < 2
        needle = words[1..].join(" ").downcase
        lines = content.lines
        start = heading_index(lines, needle)
        return content unless start
        level = heading_level(lines[start])
        finish = lines.size
        fenced = false
        ((start + 1)...lines.size).each do |index|
          line = lines[index]
          if line.lstrip.starts_with?("```")
            fenced = !fenced
            next
          end
          next if fenced
          if line.starts_with?('#') && heading_level(line) <= level
            finish = index
            break
          end
        end
        lines[start...finish].join('\n')
      end

      # The first ATX heading containing `needle`, ignoring fenced code.
      private def self.heading_index(lines : Array(String), needle : String) : Int32?
        fenced = false
        lines.each_with_index do |line, index|
          if line.lstrip.starts_with?("```")
            fenced = !fenced
            next
          end
          next if fenced
          return index if line.starts_with?('#') && line.downcase.includes?(needle)
        end
        nil
      end

      # The number of leading `#` characters, or zero for a non-heading.
      private def self.heading_level(line : String) : Int32
        line.each_char.take_while { |char| char == '#' }.size
      end

      # Opens the published guide in a browser. Falls back to printing the
      # URL when no opener is available; no network call is made by Altair.
      def self.open_topic(name : String) : Int32
        page = TOPIC_URLS[name]? || "index"
        url = "#{WEB_BASE}/#{page}.html"
        commands = {% if flag?(:win32) %}
                     [{"cmd", ["/c", "start", url]}]
                   {% elsif flag?(:darwin) %}
                     [{"open", [url]}]
                   {% else %}
                     [{"xdg-open", [url]}]
                   {% end %}
        commands.each do |command, args|
          process = Process.run(command, args, output: Process::Redirect::Close, error: Process::Redirect::Close)
          return 0 if process.success?
        rescue IO::Error | File::NotFoundError
        end
        puts url
        0
      end
    end
  end
end
