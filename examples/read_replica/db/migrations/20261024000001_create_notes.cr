# Read-replica demo — creates the notes table.
class CreateNotes < Altair::Record::Migration
  def up(schema : Altair::Record::Schema) : Nil
    schema.create_table(:notes) do |t|
      t.string :body
      t.datetime :created_at
      t.datetime :updated_at
    end
  end

  def down(schema : Altair::Record::Schema) : Nil
    schema.drop_table(:notes)
  end
end
