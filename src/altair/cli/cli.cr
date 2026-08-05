# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::CLI`, the command-line surface of the
# framework. It dispatches the generator commands (`new`, `generate`) that
# create projects and scaffold files, and prints help. The generated
# project's `bin/altair` entry drives app-context commands (`server`,
# `routes`, `db:migrate` and `db:rollback`) directly against the concrete
# application class, while the generator half lives here so it is shared
# between a fresh checkout's `bin/altair` and the framework shard.
module Altair
  module CLI
    # Dispatches the given arguments to a command. Returns a process exit
    # code. Recognizes `new`, `generate`/`g`, `version` and `help`.
    def self.run(args : Array(String)) : Int32
      case args[0]?
      when "new"
        Generators::New.run(args[1..])
      when "generate", "g"
        Generators.run(args[1..])
      when "install"
        Install.run(args[1..])
      when "version", "-v", "--version"
        puts "Altair #{Altair::VERSION}"
        0
      when "help", "--help", "-h", nil
        puts help
        0
      else
        abort "Unknown command: #{args[0]? || "(none)"}\n\n#{help}\n#{project_hint(args[0]?)}"
      end
    end

    # A hint shown for app-context commands (like `server`) invoked through
    # the global binary while inside a generated project, pointing at the
    # project launcher. Empty otherwise.
    def self.project_hint(command : String?) : String
      if command && %w[server routes db:migrate db:rollback].includes?(command) &&
         File.exists?("bin/altair") && File.exists?("shard.yml")
        "\n`#{command}` is a project command — run `bin/altair #{command}` inside your application."
      else
        ""
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
          altair version                        print the framework version
          altair help                           print this help

        Inside a generated project, `bin/altair` accepts `server`, `routes`,
        `db:migrate`, `db:rollback` and the generator commands above.
        TXT
    end
  end
end
