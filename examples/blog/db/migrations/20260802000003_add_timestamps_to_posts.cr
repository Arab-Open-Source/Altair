# Blog — adds the auto-updated timestamps to posts.
class AddTimestampsToPosts < Altair::Record::Migration
  def up(schema : Altair::Record::Schema) : Nil
    schema.add_column(:posts, :created_at, :datetime)
    schema.add_column(:posts, :updated_at, :datetime)
  end

  def down(schema : Altair::Record::Schema) : Nil
    schema.remove_column(:posts, :created_at)
    schema.remove_column(:posts, :updated_at)
  end
end
