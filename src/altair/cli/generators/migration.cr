# Altair — the batteries-included web framework for Crystal.
#
# This file defines the migration generator: `altair generate migration
# CreatePosts title:string body:text` writes a timestamped migration under
# `db/migrations/`. The migration name must be `Create<Table>`; the table
# name is derived from it and the columns are mapped to `t.<type>` calls.
module Altair
  module CLI
    module Generators
      class Migration
        include Base

        # The migration name argument, e.g. `CreatePosts`.
        getter name : String

        # The parsed columns the migration creates.
        getter columns : Array(Column)

        def initialize(@name : String, @columns : Array(Column))
        end

        # The migration's class name, e.g. `CreatePosts`.
        def class_name : String
          @name
        end

        # The table the migration creates, derived from a `Create<Table>`
        # name, e.g. `posts`.
        def table : String
          unless @name.starts_with?("Create")
            raise Altair::Error.new(
              "Migration name must start with `Create`, e.g. `CreatePosts` — got #{@name.inspect}"
            )
          end
          tableize(@name[6..])
        end

        # The 14-digit version timestamp prefixing the file name.
        def version : String
          Time.utc.to_s("%Y%m%d%H%M%S")
        end

        # The migration file name, e.g. `20260802000001_create_posts.cr`.
        def file_name : String
          "#{version}_#{Altair::Inflector.underscore(class_name)}.cr"
        end

        # The migration file path under `db/migrations/`.
        def path : Path
          Path.new("db/migrations/#{file_name}")
        end

        # Whether a file with this migration's name already exists.
        def exists? : Bool
          File.exists?(path)
        end

        # Writes the migration file and returns its path. Refuses to
        # overwrite an existing migration so a regeneration never clobbers
        # a run.
        def generate : Path
          raise Altair::Error.new("Migration already exists: #{path}") if exists?
          content = String.build do |io|
            io << "# Creates the #{table} table.\n"
            io << "class #{class_name} < Altair::Record::Migration\n"
            io << "  def up(schema : Altair::Record::Schema) : Nil\n"
            io << "    schema.create_table(:#{table}) do |t|\n"
            columns.each do |column|
              io << "      t.#{column.type} :#{column.name}\n"
            end
            io << "    end\n"
            io << "  end\n"
            io << "\n"
            io << "  def down(schema : Altair::Record::Schema) : Nil\n"
            io << "    schema.drop_table(:#{table})\n"
            io << "  end\n"
            io << "end\n"
          end
          write_file(path, content)
        end
      end
    end
  end
end
