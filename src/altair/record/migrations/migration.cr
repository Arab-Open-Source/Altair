# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Record::Migration`, the base class of every
# migration file. A migration subclasses it, implements `up` (and
# optionally `down`), and is discovered by the runner through a
# compile-time registry — the migration files are `require`d by the
# runner script, so registration happens at compile time.
module Altair
  module Record
    abstract class Migration
      @@registry : Array(Migration.class)?

      # The registry of every migration class, in require (file) order.
      def self.registry : Array(Migration.class)
        @@registry ||= [] of Migration.class
      end

      # Registers subclasses as they are defined: the `inherited` hook is
      # expanded at compile time and runs at load time, so the registry is
      # populated in require order before the runner looks at it.
      macro inherited
        {{@type}}.register_migration
      end

      # The registration hook expanded into each subclass by `inherited`.
      # Crystal gives every subclass its own copy of class variables, so
      # the push must go through the base class explicitly.
      def self.register_migration : Nil
        Migration.registry << self
      end

      # Applies the migration's changes to the schema (and the database).
      abstract def up(schema : Schema) : Nil

      # Reverses `up`. Override in reversible migrations; the default
      # raises so a rollback never silently skips a step.
      def down(schema : Schema) : Nil
        raise Altair::Error.new(
          "#{self.class} is irreversible: it does not define a down migration. " \
          "Define `down` or rebuild from a fresh database instead of rolling back."
        )
      end
    end
  end
end
