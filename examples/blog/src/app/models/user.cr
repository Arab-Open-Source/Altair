# Blog — the user model with password authentication.
#
# `password_auth` stages the plain password on assignment, hashes it into
# `password_digest` through PBKDF2 before save, and validates length and
# confirmation as ordinary record errors.
class User < Altair::Record::Model
  table :users

  validates_presence_of :email
  validates_uniqueness_of :email
  password_auth min_length: 8
end
