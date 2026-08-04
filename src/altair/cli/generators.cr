# Altair — the batteries-included web framework for Crystal.
#
# This file defines the generator dispatcher: it maps the `generate`
# command's first argument to the matching generator class and runs it.
# `altair g model Post title:string`, `altair g scaffold Post title:string`
# and friends all land here, running against the current working directory.
module Altair
  module CLI
    module Generators
      extend self

      # The generator type names and their classes.
      TYPES = {
        "model"      => Generators::Model,
        "migration"  => Generators::Migration,
        "controller" => Generators::Controller,
        "scaffold"   => Generators::Scaffold,
      }

      # Runs the generator named by `args[0]` with the remaining arguments.
      # Returns the process exit code.
      def run(args : Array(String)) : Int32
        type = args[0]?
        rest = args[1..]
        case type
        when "model"
          Generators::Model.new(required_name(rest, type)).generate
          0
        when "migration"
          name = required_name(rest, type)
          Generators::Migration.new(name, Base.parse_columns(rest[1..])).generate
          0
        when "controller"
          Generators::Controller.new(required_name(rest, type)).generate
          0
        when "scaffold"
          Generators::Scaffold.new(required_name(rest, type), Base.parse_columns(rest[1..])).generate
          0
        else
          abort "Unknown generator: #{type || "(none)"}\n\n#{generator_help}"
        end
      end

      # The generator help text.
      def generator_help : String
        <<-TXT
          Usage:
            altair generate model <Name> [column:type ...]
            altair generate migration Create<Table> [column:type ...]
            altair generate controller <Name>
            altair generate scaffold <Name> [column:type ...]

          Columns accept a type after a colon (defaults to string):
          title:string body:text price:float published:boolean
          TXT
      end

      private def required_name(rest : Array(String)?, type : String?) : String
        name = rest.try(&.first?)
        if name.nil? || name.empty?
          abort "Missing name for `#{type || "(none)"}` — e.g. `altair g #{type || "generator"} Post`"
        end
        name
      end
    end
  end
end
