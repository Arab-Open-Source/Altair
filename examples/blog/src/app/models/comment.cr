# Blog — the comments model, backed by the comments table.
class Comment < Altair::Record::Model
  table :comments

  belongs_to :post

  validates_presence_of :body
end
