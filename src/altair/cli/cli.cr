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
        puts help
        0
      else
        if project_command?(args[0]?) && (dir = find_project_dir)
          return run_project(args, dir)
        end
        abort "Unknown command: #{args[0]? || "(none)"}\n\n#{help}"
      end
    end

    # True when `command` is an app-context command that must run against a
    # project's compiled source rather than the global binary.
    def self.project_command?(command : String?) : Bool
      %w[server routes db:migrate db:rollback].includes?(command)
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
          altair new <name>                     create a new application
          altair generate <type> <args> ...     scaffold files (alias: g)
          altair g scaffold Post title:string   model, migration, controller and views
          altair g model Post title:string      a model + table
          altair g migration CreatePosts ...    a timestamped migration
          altair g controller Posts             a controller + views
          altair install [--dir DIR] [--force]  copy the binary onto your PATH
          altair update [--check] [--force]     update to the latest release
          altair version                        print the framework version
          altair help                           print this help

        Inside a generated project, `server`, `routes`, `db:migrate` and
        `db:rollback` run against that project's application.
        TXT
    end
  end
end
