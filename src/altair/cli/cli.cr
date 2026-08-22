# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::CLI`, the command-line surface of the
# framework. It dispatches the generator commands (`new`, `generate`) that
# create projects and scaffold files, prints help, and forwards
# app-context commands (`server`, `routes`, `db:*`) to the project
# launcher when run from inside a generated project — so `altair server`
# works from anywhere in an application, old or new, without knowing about
# `bin/altair`. The generator half lives here so it is shared between a
# fresh checkout's `bin/altair` and the framework shard.
require "process"

module Altair
  module CLI
    # Dispatches the given arguments to a command. Returns a process exit
    # code. Recognizes `new`, `generate`/`g`, `install`, `update`,
    # `version` and `help`. App-context commands (`server`, `routes`,
    # `db:migrate`, `db:rollback`) are forwarded to the surrounding project
    # launcher when present.
    def self.run(args : Array(String)) : Int32
      case args[0]?
      when "new"
        Generators::New.run(args[1..])
      when "generate", "g"
        Generators.run(args[1..])
      when "install"
        Install.run(args[1..])
      when "update"
        Update.run(args[1..])
      when "version", "-v", "--version"
        puts "Altair #{Altair::VERSION}"
        0
      when "help", "--help", "-h", nil
        if args[1]?
          puts help_for(args[1])
        else
          puts help
        end
        0
      else
        if project_command?(args[0]?)
          if dir = find_project_dir
            return run_project(args, dir)
          else
            abort "#{args[0]?} must be run inside an Altair project (no bin/altair.cr found walking up from #{Dir.current}) — did you run `altair new`?"
          end
        end
        message = String.build do |io|
          io << "Unknown command: #{args[0]? || "(none)"}"
          suggestions = did_you_mean(args[0]? || "")
          unless suggestions.empty?
            io << "\n\nDid you mean one of these?\n"
            suggestions.each { |suggestion| io << "  #{suggestion}\n" }
          end
          io << "\n#{help}"
        end
        abort message
      end
    end

    # Returns up to three close matches for `input` among known commands.
    def self.did_you_mean(input : String) : Array(String)
      known = %w[new generate g install update version help server routes db:migrate db:rollback db:seed assets:precompile jobs:work jobs:stats]
      scored = known.map { |command| {command, levenshtein(input, command)} }
        .select { |_, dist| dist <= 3 && dist > 0 }
        .sort_by! { |_, dist| dist }
        .first(3)
        .map(&.[0])
      scored
    end

    # Levenshtein distance between two strings.
    private def self.levenshtein(a : String, b : String) : Int32
      return b.size if a.empty?
      return a.size if b.empty?
      prev = (0..b.size).to_a
      curr = Array(Int32).new(b.size + 1, 0)
      a.each_char.with_index(1) do |char_a, outer_index|
        curr[0] = outer_index
        b.each_char.with_index(1) do |char_b, inner_index|
          cost = char_a == char_b ? 0 : 1
          curr[inner_index] = {prev[inner_index] + 1, curr[inner_index - 1] + 1, prev[inner_index - 1] + cost}.min
        end
        prev, curr = curr, prev
      end
      prev[b.size]
    end

    # True when `command` is an app-context command that must run against a
    # project's compiled source rather than the global binary.
    def self.project_command?(command : String?) : Bool
      %w[server routes db:migrate db:rollback db:seed assets:precompile jobs:work jobs:stats].includes?(command)
    end

    # The directory of the Altair project surrounding the current working
    # directory, or nil. A project is recognized by its `bin/altair.cr`
    # launcher, so old projects (created before `bin/altair` existed) and
    # new ones are found the same way.
    def self.find_project_dir : Path?
      dir = Path[Dir.current]
      loop do
        return dir if File.exists?(dir / "bin" / "altair.cr")
        parent = dir.parent
        break if parent == dir
        dir = parent
      end
      nil
    end

    # Forwards `args` to the project launcher in `dir`. Prefers an
    # executable `bin/altair` (the sh wrapper) and falls back to
    # `crystal run bin/altair.cr` for projects that only carry the `.cr`
    # file. Returns the child process's exit code.
    def self.run_project(args : Array(String), dir : Path) : Int32
      command, cargs = project_launcher(dir, args)
      process = Process.run(command, cargs, chdir: dir.to_s, output: STDOUT, error: STDERR, input: STDIN)
      process.exit_code
    end

    # The command and arguments that run `args` inside the project at
    # `dir`. Returns `["bin/altair", args]` when the wrapper exists,
    # otherwise `["crystal", ["run", "bin/altair.cr", "--", *args]]`.
    def self.project_launcher(dir : Path, args : Array(String)) : {String, Array(String)}
      wrapper = dir / "bin" / "altair"
      if File.exists?(wrapper)
        {wrapper.to_s, args}
      else
        {"crystal", ["run", (dir / "bin" / "altair.cr").to_s, "--"] + args}
      end
    end

    # The command-line help text.
    def self.help : String
      <<-TXT
        Altair #{Altair::VERSION} — the batteries-included web framework for Crystal.

        Usage:
          altair new <name> [--framework-path DIR]  create a new application
          altair generate <type> <args> ...         scaffold files (alias: g)
          altair g scaffold Post title:string       model, migration, controller and views
          altair g model Post title:string          a model + table
          altair g migration CreatePosts ...        a timestamped migration
          altair g controller Posts                 a controller + views
          altair install [--dir DIR] [--force]      copy the binary onto your PATH
          altair update [--check] [--force]         update to the latest release
          altair version                            print the framework version
          altair help [command]                     print this help or help for a command
          altair db:seed                            run db/seeds.cr (inside a project)
          altair assets:precompile                  fingerprint assets/ into public/assets
          altair jobs:work                          run the background-jobs worker
          altair jobs:stats                         print background-job status counts

        Inside a generated project, `server`, `routes`, `db:migrate`,
        `db:rollback`, `db:seed`, `assets:precompile`, `jobs:work` and
        `jobs:stats` run against that project's application.
        TXT
    end

    # Per-command help. Falls back to the general help when unknown.
    def self.help_for(command : String) : String
      case command
      when "new"
        <<-TXT
          Usage: altair new <name> [--framework-path DIR]

            Creates a new Altair application in <name>. <name> may include a
            path (e.g. a/b or /tmp/my_app); only its basename becomes the
            application name, which must be lowercase letters, digits and
            underscores starting with a letter.

            Options:
              --framework-path DIR   use a local framework checkout instead of GitHub
              (also: --framework-path=DIR or ALTAIR_PATH env var)
          TXT
      when "generate", "g"
        Generators.generator_help
      when "install"
        "Usage: altair install [--dir DIR] [--force]\n  Copies the built binary onto your PATH.\n"
      when "update"
        "Usage: altair update [--check] [--force]\n  Checks GitHub for the latest release and verifies the download.\n"
      else
        help
      end
    end
  end
end
