# Showcase — creates the users table.
class CreateUsers < Altair::Record::Migration
  def up(schema : Altair::Record::Schema) : Nil
    schema.create_table(:users) do |t|
      t.string :name
      t.string :email
      t.string :password
      t.datetime :created_at
      t.datetime :updated_at
    end
  end

  def down(schema : Altair::Record::Schema) : Nil
    schema.drop_table(:users)
  end
end
