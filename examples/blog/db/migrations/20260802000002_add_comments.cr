# Blog — creates the comments table and its index.
class AddComments < Altair::Record::Migration
  def up(schema : Altair::Record::Schema) : Nil
    schema.create_table(:comments) do |t|
      t.string :body
      t.integer :post_id
    end
    schema.add_index(:comments, :post_id)
  end

  def down(schema : Altair::Record::Schema) : Nil
    schema.drop_table(:comments)
  end
end
