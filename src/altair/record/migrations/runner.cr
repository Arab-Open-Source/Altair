# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Record::Migrations::Runner`, which applies and
# rolls back migrations against a connection. The migration files are
# compiled into the runner script, so pending files are picked from the
# migrations directory and matched to the compiled registry by their
# timestamp-prefixed names. Every run rebuilds the schema state by
# replaying the applied migrations and regenerates `db/schema.cr` — schema
# and database can never drift apart.
module Altair
  module Record
    module Migrations
      class Runner
        # The migrations directory the runner scans for pending files.
        getter migrations_dir : Path

        # Where the regenerated `db/schema.cr` is written.
        getter schema_path : Path

        # Creates a runner for the given connection and project paths.
        def initialize(@connection : Connection, @migrations_dir : Path, @schema_path : Path, @adapter : Adapter)
        end

        # Applies every pending migration, in file order, then regenerates
        # the schema file. Returns the number of migrations applied.
        # A guard prevents two concurrent migrate processes from racing.
        def migrate : Int32
          acquire_migrate_lock
          ensure_schema_migrations
          applied = applied_versions
          pending = migration_files.select { |file| !applied.includes?(file.stem) }
          pending.each do |file|
            klass = registry_class(file.stem)
            @connection.transaction do
              klass.new.up(Schema.new(@adapter, @connection))
              record_version(file.stem)
            end
          end
          generate_schema unless pending.empty?
          pending.size
        end

        # Rolls back the last applied migration, regenerating the schema
        # file. Returns `false` when nothing is applied.
        def rollback : Bool
          ensure_schema_migrations
          version = last_version
          return false unless version
          klass = registry_class(version)
          @connection.transaction do
            klass.new.down(Schema.new(@adapter, @connection))
            delete_version(version)
          end
          generate_schema
          true
        end

        # The currently applied migration versions, oldest first.
        def applied_versions : Array(String)
          versions = [] of String
          @connection.query("SELECT version FROM schema_migrations ORDER BY version") do |rs|
            rs.each { versions << rs.read(String) }
          end
          versions
        end

        private def schema_for_replay : Schema
          schema = Schema.new(@adapter)
          applied_versions.each do |version|
            registry_class(version).new.up(schema)
          end
          schema
        end

        private def ensure_schema_migrations : Nil
          @connection.exec(
            "CREATE TABLE IF NOT EXISTS #{@adapter.quote_identifier("schema_migrations")} " \
            "(#{@adapter.quote_identifier("version")} TEXT PRIMARY KEY)"
          )
        end

        private def record_version(version : String) : Nil
          @connection.exec(
            "INSERT INTO #{@adapter.quote_identifier("schema_migrations")} " \
            "(#{@adapter.quote_identifier("version")}) VALUES (#{@adapter.placeholder(0)})", version
          )
        end

        private def delete_version(version : String) : Nil
          @connection.exec(
            "DELETE FROM #{@adapter.quote_identifier("schema_migrations")} " \
            "WHERE #{@adapter.quote_identifier("version")} = #{@adapter.placeholder(0)}", version
          )
        end

        private def last_version : String?
          @connection.query_one(
            "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1"
          ) { |rs| rs.read(String) }
        rescue DB::NoResultsError
          nil
        end

        private def migration_files : Array(Path)
          Dir.children(@migrations_dir.to_s)
            .select(&.matches?(/\A\d{14}_.+\.cr\z/))
            .sort!
            .map { |file| @migrations_dir.join(file) }
        end

        private def registry_class(version : String) : Migration.class
          klass = Migration.registry.find(&.name.ends_with?(camelized(version)))
          raise Altair::Error.new("No migration class found for #{version}. Is the file required by the runner script?") unless klass
          klass
        end

        private def camelized(version : String) : String
          Altair::Inflector.camelize(version.split("_")[1..].join("_"))
        end

        private def generate_schema : Nil
          SchemaGenerator.new(@adapter, @schema_path).write(schema_for_replay)
        end

        # Prevents two `db:migrate` processes from racing on the same
        # database. PostgreSQL uses advisory locks; SQLite's single-writer
        # model plus busy_timeout already serializes writers.
        private def acquire_migrate_lock : Nil
          @connection.exec(
            "SELECT #{@connection.adapter.quote_identifier("pg_advisory_lock")}" \
            "(hashtext('altair_migrate'))"
          )
        rescue
          # SQLite and other adapters don't support advisory locks — their
          # single-writer model plus busy_timeout already serializes writes.
        end
      end
    end
  end
end
