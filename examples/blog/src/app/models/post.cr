# Blog — the posts model, backed by the posts table.
class Post < Altair::Record::Model
  table :posts

  validates_presence_of :title
end
