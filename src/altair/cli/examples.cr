# Altair — the batteries-included web framework for Crystal.
#
# This file defines `altair examples`, the offline reader and copy command
# for the curated starter programs. Listing and reading work anywhere;
# copying requires a generated project and writes only to `examples/altair/`.
module Altair
  module CLI
    class Examples
      # Runs `altair examples`. Returns a process exit code.
      def self.run(args : Array(String)) : Int32
        copy = args.any? { |arg| arg == "--copy" || arg.starts_with?("--copy=") }
        names = args.flat_map do |arg|
          if arg.starts_with?("--copy=")
            [arg.split("=", 2)[1]]
          elsif arg.starts_with?("--")
            [] of String
          else
            [arg]
          end
        end

        if copy
          root = Altair::CLI.find_project_dir
          if root.nil?
            STDERR.puts "--copy must be run inside an Altair project."
            return 1
          end
          available = Bundle.examples(root)
          if available.empty?
            STDERR.puts "No examples bundle found — set ALTAIR_BUNDLE_PATH or install the framework source."
            return 1
          end
          targets = if names.empty? || names == ["all"]
                      available
                    else
                      names
                    end
          unknown = targets.reject { |name| available.includes?(name) }
          unless unknown.empty?
            STDERR.puts "Unknown example(s): #{unknown.join(", ")}"
            STDERR.puts "Available examples: #{available.join(", ")}"
            return 1
          end
          copied = Bundle.copy_examples(root.not_nil!, targets)
          copied.each { |name| puts "  create  examples/altair/#{name}" }
          puts "Copied #{copied.size} example(s); they compile against this project's shard.yml."
          Bundle.warn_if_drift(root)
          return 0
        end

        if names.empty?
          list_examples
        else
          root = Altair::CLI.find_project_dir
          available = Bundle.examples(root)
          unknown = names.reject { |name| available.includes?(name) }
          unless unknown.empty?
            STDERR.puts "Unknown example: #{unknown.join(", ")}"
            STDERR.puts "Available examples: #{available.join(", ")}"
            return 1
          end
          names.each do |name|
            content = Bundle.example_readme(name, root)
            if content.nil?
              STDERR.puts "Unknown example: #{name}"
              return 1
            end
            puts content
          end
          0
        end
      end

      # Prints the curated examples with the title from each README.
      def self.list_examples : Int32
        root = Altair::CLI.find_project_dir
        names = Bundle.examples(root)
        if names.empty?
          puts "No curated examples available. Install the framework bundle or set ALTAIR_BUNDLE_PATH."
          return 0
        end
        puts "Available starter examples (offline):"
        names.each do |name|
          readme = Bundle.example_readme(name, root) || ""
          title = readme.lines.find(&.starts_with?("# ")).try(&.lchop("# ").strip) || name
          puts "  #{name.ljust(16)} #{title}"
        end
        puts ""
        puts "Read one with: altair examples <name>"
        puts "Copy with:     altair examples --copy <name|all>"
        0
      end
    end
  end
end
