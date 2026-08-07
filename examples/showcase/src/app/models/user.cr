# Showcase — the users model.
#
# `email` is unique across the table, `password` is stored as plain text
# only because this is a demo — an integration with a password-hashing
# library is left to the application.
class User < Altair::Record::Model
  table :users

  has_many :posts
  has_many :comments

  validates_presence_of :name, :email, :password
  validates_uniqueness_of :email
  validates_format_of :email, with: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
end
