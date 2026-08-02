# Altair — record model specs' shared schema and models.
#
# The `META` constant mirrors what the schema generator emits into a
# generated `db/schema.cr`, and the models below exercise the `table` macro
# over every column type. The DDL is re-created per suite; each example
# runs inside a rolled-back transaction for isolation.
require "../spec_helper"

class Altair::Record::Schema
  META = {
    posts: {
      id:         {type: :integer, null: false, primary: true},
      title:      {type: :string, null: true, primary: false},
      body:       {type: :text, null: true, primary: false},
      views:      {type: :integer, null: false, primary: false},
      published:  {type: :boolean, null: false, primary: false},
      rating:     {type: :float, null: true, primary: false},
      created_at: {type: :datetime, null: true, primary: false},
      updated_at: {type: :datetime, null: true, primary: false},
    },
    comments: {
      id:      {type: :integer, null: false, primary: true},
      post_id: {type: :integer, null: false, primary: false},
      body:    {type: :text, null: false, primary: false},
    },
  }
end

class Post < Altair::Record::Model
  table :posts

  validates_presence_of :title
  validates_length_of :title, maximum: 10
  validates_numericality_of :views, greater_than: -1
  validate :title_must_not_be_reserved

  def title_must_not_be_reserved : Nil
    errors.add(:title, "is reserved") if title == "reserved"
  end
end

class Comment < Altair::Record::Model
  table :comments

  validates_presence_of :body, message: "is required"
  validates_length_of :body, minimum: 5

  before_save :shout
  before_save :record_before_save
  after_save :record_after_save
  before_create :record_before_create
  after_create :record_after_create
  before_update :record_before_update
  after_update :record_after_update
  before_destroy :record_before_destroy
  after_destroy :record_after_destroy

  class_getter events : Array(Symbol) = [] of Symbol

  def shout : Nil
    self.body = "#{body}!"
  end

  def record_before_save : Nil
    Comment.events << :before_save
  end

  def record_after_save : Nil
    Comment.events << :after_save
  end

  def record_before_create : Nil
    Comment.events << :before_create
  end

  def record_after_create : Nil
    Comment.events << :after_create
  end

  def record_before_update : Nil
    Comment.events << :before_update
  end

  def record_after_update : Nil
    Comment.events << :after_update
  end

  def record_before_destroy : Nil
    Comment.events << :before_destroy
  end

  def record_after_destroy : Nil
    Comment.events << :after_destroy
  end
end

module RecordSpec
  def self.setup_database : Nil
    connection = Altair::Record.connection
    connection.exec("DROP TABLE IF EXISTS comments")
    connection.exec("DROP TABLE IF EXISTS posts")
    connection.exec(
      "CREATE TABLE posts (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, " \
      "title TEXT, body TEXT, views INTEGER NOT NULL DEFAULT 0, " \
      "published BOOLEAN NOT NULL DEFAULT 0, rating FLOAT, " \
      "created_at DATETIME, updated_at DATETIME)"
    )
    connection.exec(
      "CREATE TABLE comments (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, " \
      "post_id INTEGER NOT NULL, body TEXT NOT NULL)"
    )
  end
end
