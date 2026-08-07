# Showcase — the posts model.
#
# A post belongs to a user, carries an optional uploaded `image` file name
# and has a `published` flag the author toggles with the `publish` route.
class Post < Altair::Record::Model
  table :posts

  belongs_to :user
  has_many :comments, dependent: :destroy

  validates_presence_of :title, :body
  validates_length_of :title, maximum: 80
end
