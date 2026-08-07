# Showcase — the comments model.
#
# A comment belongs to a post and its author. Deleting a post destroys its
# comments through the `dependent: :destroy` association on `Post`.
class Comment < Altair::Record::Model
  table :comments

  belongs_to :post
  belongs_to :user

  validates_presence_of :body
end
