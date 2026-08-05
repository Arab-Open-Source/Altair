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
      user_id:    {type: :integer, null: true, primary: false},
      created_at: {type: :datetime, null: true, primary: false},
      updated_at: {type: :datetime, null: true, primary: false},
    },
    comments: {
      id:      {type: :integer, null: false, primary: true},
      post_id: {type: :integer, null: true, primary: false},
      body:    {type: :text, null: false, primary: false},
    },
    users: {
      id:   {type: :integer, null: false, primary: true},
      name: {type: :string, null: true, primary: false},
    },
    profiles: {
      id:      {type: :integer, null: false, primary: true},
      user_id: {type: :integer, null: true, primary: false},
      bio:     {type: :string, null: true, primary: false},
    },
    categories: {
      id:      {type: :integer, null: false, primary: true},
      user_id: {type: :integer, null: true, primary: false},
      name:    {type: :string, null: true, primary: false},
    },
    articles: {
      id:          {type: :integer, null: false, primary: true},
      category_id: {type: :integer, null: true, primary: false},
      title:       {type: :string, null: true, primary: false},
    },
    humans: {
      id:   {type: :integer, null: false, primary: true},
      name: {type: :string, null: true, primary: false},
    },
    children: {
      id:       {type: :integer, null: false, primary: true},
      human_id: {type: :integer, null: true, primary: false},
      name:     {type: :string, null: true, primary: false},
    },
    tags: {
      id:   {type: :integer, null: false, primary: true},
      name: {type: :string, null: true, primary: false},
    },
    labels: {
      id:   {type: :integer, null: false, primary: true},
      name: {type: :string, null: true, primary: false},
      kind: {type: :string, null: true, primary: false},
    },
    payloads: {
      id:   {type: :integer, null: false, primary: true},
      name: {type: :string, null: true, primary: false},
      data: {type: :json, null: true, primary: false},
    },
    events: {
      id:   {type: :bigint, null: false, primary: true},
      name: {type: :string, null: true, primary: false},
    },
    accounts: {
      id:          {type: :integer, null: false, primary: true},
      name:        {type: :string, null: true, primary: false},
      balance:     {type: :decimal, null: true, primary: false},
      min_balance: {type: :decimal, null: false, primary: false},
    },
    members: {
      id:       {type: :integer, null: false, primary: true},
      role:     {type: :string, null: true, primary: false},
      name:     {type: :string, null: true, primary: false},
      email:    {type: :string, null: true, primary: false},
      password: {type: :string, null: true, primary: false},
      age:      {type: :integer, null: true, primary: false},
    },
  }
end

class Post < Altair::Record::Model
  table :posts

  has_many :comments, dependent: :destroy

  validates_presence_of :title
  validates_length_of :title, maximum: 10
  validates_numericality_of :views, greater_than: -1
  validate :title_must_not_be_reserved

  def title_must_not_be_reserved : Nil
    errors.add(:title, "is reserved") if title == "reserved"
  end
end

# A one-to-many owner without a dependent clause.
class User < Altair::Record::Model
  table :users

  has_many :posts
  has_many :categories
  has_one :profile, dependent: :nullify
end

# The one side of a `has_one`.
class Profile < Altair::Record::Model
  table :profiles

  belongs_to :user
end

# A `dependent: :delete_all` owner.
class Category < Altair::Record::Model
  table :categories

  has_many :articles, dependent: :delete_all
end

# The child of the `dependent: :delete_all` owner.
class Article < Altair::Record::Model
  table :articles

  belongs_to :category
end

# An owner whose association name has an irregular plural; the model class
# derives through the singularization rules (`:children` -> `Child`).
class Human < Altair::Record::Model
  table :humans

  has_many :children
end

# The child of the irregular-plural owner.
class Child < Altair::Record::Model
  table :children

  belongs_to :human
end

# A model with a plain uniqueness rule.
class Tag < Altair::Record::Model
  table :tags

  validates_uniqueness_of :name
end

# A model whose uniqueness rule is scoped and uses a custom message.
class Label < Altair::Record::Model
  table :labels

  validates_uniqueness_of :name, scope: :kind, message: "is taken"
end

# A model with a JSON column, exercising the adapter's coercion layer.
class Payload < Altair::Record::Model
  table :payloads
end

# A model with a `:bigint` primary key, exercising wide-id typing end to end.
class Event < Altair::Record::Model
  table :events
end

# A model with a decimal column, exercising the adapter's numeric coercion.
class Account < Altair::Record::Model
  table :accounts
end

# A model exercising inclusion, exclusion, format and confirmation rules.
class Member < Altair::Record::Model
  table :members

  validates_inclusion_of :role, in: %w[admin editor viewer]
  validates_inclusion_of :age, in: 18..65
  validates_exclusion_of :name, in: %w[root admin guest]
  validates_format_of :email, with: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
  validates_confirmation_of :password

  property password_confirmation : String?
end

class Comment < Altair::Record::Model
  table :comments

  belongs_to :post

  validates_presence_of :body, message: "is required"
  validates_length_of :body, minimum: 5

  before_save :shout
  before_save :record_before_save
  after_save :record_after_save
  before_create :record_before_create
  after_create :record_after_create
  after_create :raise_if_asked_create
  before_update :record_before_update
  after_update :record_after_update
  after_update :raise_if_asked_update
  before_destroy :record_before_destroy
  after_destroy :record_after_destroy
  after_destroy :raise_if_asked_destroy

  class_getter events : Array(Symbol) = [] of Symbol
  class_property? raise_after_create : Bool = false
  class_property? raise_after_update : Bool = false
  class_property? raise_after_destroy : Bool = false

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

  def raise_if_asked_create : Nil
    raise "boom on create" if Comment.raise_after_create?
  end

  def raise_if_asked_update : Nil
    raise "boom on update" if Comment.raise_after_update?
  end

  def raise_if_asked_destroy : Nil
    raise "boom on destroy" if Comment.raise_after_destroy?
  end
end

module RecordSpec
  def self.setup_database : Nil
    connection = Altair::Record.connection
    connection.exec("DROP TABLE IF EXISTS labels")
    connection.exec("DROP TABLE IF EXISTS payloads")
    connection.exec("DROP TABLE IF EXISTS events")
    connection.exec("DROP TABLE IF EXISTS accounts")
    connection.exec("DROP TABLE IF EXISTS members")
    connection.exec("DROP TABLE IF EXISTS tags")
    connection.exec("DROP TABLE IF EXISTS children")
    connection.exec("DROP TABLE IF EXISTS humans")
    connection.exec("DROP TABLE IF EXISTS articles")
    connection.exec("DROP TABLE IF EXISTS categories")
    connection.exec("DROP TABLE IF EXISTS profiles")
    connection.exec("DROP TABLE IF EXISTS users")
    connection.exec("DROP TABLE IF EXISTS comments")
    connection.exec("DROP TABLE IF EXISTS posts")
    connection.exec(
      "CREATE TABLE posts (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, " \
      "title TEXT, body TEXT, views INTEGER NOT NULL DEFAULT 0, " \
      "published BOOLEAN NOT NULL DEFAULT 0, rating FLOAT, user_id INTEGER, " \
      "created_at DATETIME, updated_at DATETIME)"
    )
    connection.exec(
      "CREATE TABLE comments (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, " \
      "post_id INTEGER, body TEXT NOT NULL)"
    )
    connection.exec(
      "CREATE TABLE users (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)"
    )
    connection.exec(
      "CREATE TABLE profiles (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, bio TEXT)"
    )
    connection.exec(
      "CREATE TABLE categories (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, name TEXT)"
    )
    connection.exec(
      "CREATE TABLE articles (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, category_id INTEGER, title TEXT)"
    )
    connection.exec(
      "CREATE TABLE humans (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)"
    )
    connection.exec(
      "CREATE TABLE children (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, human_id INTEGER, name TEXT)"
    )
    connection.exec(
      "CREATE TABLE tags (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)"
    )
    connection.exec(
      "CREATE TABLE labels (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, kind TEXT)"
    )
    connection.exec(
      "CREATE TABLE payloads (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, data JSON)"
    )
    connection.exec(
      "CREATE TABLE events (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)"
    )
    connection.exec(
      "CREATE TABLE accounts (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, balance TEXT, min_balance TEXT NOT NULL DEFAULT '0')"
    )
    connection.exec(
      "CREATE TABLE members (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT, name TEXT, email TEXT, password TEXT, age INTEGER)"
    )
  end
end
