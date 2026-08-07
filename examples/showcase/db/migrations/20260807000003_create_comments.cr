# Showcase — creates the comments table.
class CreateComments < Altair::Record::Migration
  def up(schema : Altair::Record::Schema) : Nil
    schema.create_table(:comments) do |t|
      t.text :body
      t.integer :post_id
      t.integer :user_id
      t.datetime :created_at
      t.datetime :updated_at
      t.index [:post_id], unique: false, name: "index_comments_on_post_id"
      t.index [:user_id], unique: false, name: "index_comments_on_user_id"
    end
  end

  def down(schema : Altair::Record::Schema) : Nil
    schema.drop_table(:comments)
  end
end
