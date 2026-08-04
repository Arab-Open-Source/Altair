# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::CLI::Project`, the app-context commands a
# generated project's `bin/altair` wrapper exposes: `server`, `routes`,
# `db:migrate` and `db:rollback`. These need the concrete application
# class, so the generated wrapper requires the whole application and calls
# in here with that class — the `forall A` dispatch keeps the concrete
# type through to `run!`, `route_set_for` and the migration runner.
module Altair
  module CLI
    module Project
      extend self

      # Boots the HTTP server for the given application class.
      def run!(app : A.class) : Int32 forall A
        app.run!
        0
      end

      # Prints the application's route table: method, pattern and named
      # helper, in registration order. Used by `bin/altair routes`.
      def print_routes(app : A.class) : Int32 forall A
        set = Altair::Routing.route_set_for(app)
        if set.routes.empty?
          puts "No routes defined."
          return 0
        end
        table = set.routes.map do |route|
          method = route.method.ljust(6)
          pattern = route.pattern
          name = route.name ? "  (#{route.name})" : ""
          "#{method}  #{pattern}#{name}"
        end
        puts table.join('\n')
        0
      end

      # Applies pending migrations and regenerates `db/schema.cr`. Returns
      # a process exit code; prints the count of applied migrations.
      def migrate(app : A.class) : Int32 forall A
        runner, conn = build_runner(app)
        count = runner.migrate
        if count.zero?
          puts "Already up to date."
        else
          puts "Applied #{count} migration(s)."
        end
        conn.close
        0
      end

      # Rolls back one migration and regenerates `db/schema.cr`. Returns a
      # process exit code.
      def rollback(app : A.class) : Int32 forall A
        runner, conn = build_runner(app)
        if runner.rollback
          puts "Rolled back one migration."
        else
          puts "Nothing to roll back."
        end
        conn.close
        0
      end

      # Builds a migration runner wired to the application's database and
      # paths, plus the connection the caller must close.
      private def build_runner(app : A.class) : {Altair::Record::Migrations::Runner, Altair::Record::Connection} forall A
        instance = app.instance
        conn = Altair::Record::Connection.for(instance)
        runner = Altair::Record::Migrations::Runner.new(
          conn,
          Path.new("db/migrations"),
          Path.new("db/schema.cr"),
          conn.adapter
        )
        {runner, conn}
      end
    end
  end
end
