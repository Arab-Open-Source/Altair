# Showcase — creates the posts table.
class CreatePosts < Altair::Record::Migration
  def up(schema : Altair::Record::Schema) : Nil
    schema.create_table(:posts) do |t|
      t.string :title
      t.text :body
      t.string :image
      t.boolean :published
      t.integer :user_id
      t.datetime :created_at
      t.datetime :updated_at
      t.index [:user_id], unique: false, name: "index_posts_on_user_id"
    end
  end

  def down(schema : Altair::Record::Schema) : Nil
    schema.drop_table(:posts)
  end
end
