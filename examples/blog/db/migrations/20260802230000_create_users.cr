# Creates the users table backing the blog's password authentication.
class CreateUsers < Altair::Record::Migration
  def up(schema : Altair::Record::Schema) : Nil
    schema.create_table(:users) do |t|
      t.string :email
      t.string :password_digest
    end
    schema.add_index(:users, :email, unique: true)
  end

  def down(schema : Altair::Record::Schema) : Nil
    schema.drop_table(:users)
  end
end
