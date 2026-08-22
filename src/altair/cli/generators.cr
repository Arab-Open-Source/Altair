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
        "auth"       => Generators::Auth,
      }

      # Runs the generator named by `args[0]` with the remaining arguments.
      # Returns the process exit code.
      def run(args : Array(String)) : Int32
        type = args[0]?
        rest = args.size > 1 ? args[1..] : [] of String
        case type
        when "model"
          Generators::Model.new(required_name(rest, type)).generate
          0
        when "migration"
          name = required_name(rest, type)
          cols = rest.size > 1 ? rest[1..] : [] of String
          Generators::Migration.new(name, Base.parse_columns(cols)).generate
          0
        when "controller"
          Generators::Controller.new(required_name(rest, type)).generate
          0
        when "scaffold"
          name = required_name(rest, type)
          cols = rest.size > 1 ? rest[1..] : [] of String
          Generators::Scaffold.new(name, Base.parse_columns(cols)).generate
          0
        when "auth"
          name = rest.first?
          if name && !name.starts_with?("-")
            Generators::Auth.new(name).generate
          else
            Generators::Auth.new.generate
          end
          0
        else
          message = String.build do |io|
            io << "Unknown generator: #{type || "(none)"}"
            if t = type
              suggestions = generator_suggestions(t)
              unless suggestions.empty?
                io << "\n\nDid you mean one of these?\n"
                suggestions.each { |suggestion| io << "  #{suggestion}\n" }
              end
            end
            io << "\n\n#{generator_help}"
          end
          abort message
        end
      end

      def self.generator_suggestions(input : String) : Array(String)
        known = TYPES.keys
        known.map { |command| {command, levenshtein(input, command)} }
          .select { |_, dist| dist <= 3 && dist > 0 }
          .sort_by! { |_, dist| dist }
          .first(3)
          .map(&.[0])
      end

      private def levenshtein(a : String, b : String) : Int32
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

      # The generator help text.
      def generator_help : String
        <<-TXT
          Usage:
            altair generate model <Name> [column:type ...]
            altair generate migration Create<Table> [column:type ...]
            altair generate controller <Name>
            altair generate scaffold <Name> [column:type ...]
            altair generate auth [User]

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
