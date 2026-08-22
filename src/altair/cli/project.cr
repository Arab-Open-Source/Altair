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

      # The registered seed blocks, filled when a project's `db/seeds.cr`
      # is required and executed only by `seed`.
      SEED_BLOCKS = [] of Proc(Nil)

      # Registers a seed block. Called at require time from a project's
      # `db/seeds.cr`; nothing runs until `bin/altair db:seed` executes
      # the blocks in registration order:
      #
      # ```
      # Altair::CLI::Project.seeds do
      #   Post.create(title: "Hello") unless Post.exists?
      # end
      # ```
      #
      # Requiring the file is safe from every entry point — booting a
      # server never plants data.
      def seeds(&block : Proc(Nil)) : Nil
        SEED_BLOCKS << block
      end

      # Runs every registered seed block and returns the process exit
      # code. Blocks re-run on every invocation; guarding with
      # `unless Model.exists?` keeps repeated seeds idempotent.
      def seed : Int32
        if SEED_BLOCKS.empty?
          puts "No seeds registered — add them to db/seeds.cr with Altair::CLI::Project.seeds { ... }."
          return 0
        end
        SEED_BLOCKS.each &.call
        puts "Seeded #{SEED_BLOCKS.size} block(s)."
        0
      end

      # Clears the registry. Suites use it so seed registrations from one
      # example never leak into another.
      def reset_seeds! : Nil
        SEED_BLOCKS.clear
      end

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

      # Builds fingerprinted assets from `assets/` into
      # `public/assets/` and writes the manifest. Returns a process exit
      # code; prints the count of compiled files.
      def precompile_assets(app : A.class) : Int32 forall A
        entries = Altair::Assets::Pipeline.new(app.instance.root).precompile
        if entries.empty?
          puts "No assets found in assets/ — nothing to compile."
        else
          puts "Compiled #{entries.size} asset(s):"
          entries.each { |entry| puts "  #{entry.logical} -> #{entry.url}" }
        end
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

      # Runs the background-jobs worker until interrupted. Blocks the
      # process; returns a process exit code once stopped.
      def jobs_work(app : A.class) : Int32 forall A
        instance = app.instance
        config = instance.config
        worker = Altair::Jobs::Worker.new(config.jobs_poll_interval, config.jobs_queues)
        puts "Starting background worker on queues #{config.jobs_queues.join(", ")} — Ctrl-C to stop."
        worker.run
        0
      end

      # Prints the status counts of the background-jobs table.
      def jobs_stats(app : A.class) : Int32 forall A
        app.instance
        counts = Altair::Jobs::Queue.stats
        if counts.empty?
          puts "No background jobs recorded."
        else
          width = counts.keys.map(&.size).max
          counts.each { |status, count| puts "#{status.ljust(width)}  #{count}" }
        end
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
