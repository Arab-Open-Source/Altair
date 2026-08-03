# Altair — the batteries-included web framework for Crystal.
#
# The adapter contract suite: the same ORM behaviour battery runs against
# every backend. The SQLite half always runs; the PostgreSQL half runs
# when `ALTAIR_TEST_PG_URL` is set (the adapter itself is required here
# because it is not part of the framework's default load path).
#
# Every example starts from a freshly recreated schema, and the record
# fixtures (`Post`, `Comment`, ...) are exercised identically on both
# backends — the models must never care which database they talk to.
require "./model_fixtures_spec"
require "../../src/altair/record/adapters/postgresql"

private def queries(&block : -> Nil) : Int32
  count = 0
  Altair::Record.on_query { |_sql, _duration| count += 1 }
  block.call
  count
end

# Whether the backend allows several concurrent writers across connections.
# SQLite is single-writer, so true concurrency is only possible on a server
# database (PostgreSQL).
private def parallel_writers? : Bool
  !Altair::Record.connection.adapter.class.name.includes?("SQLite")
end

# Runs the shared behaviour battery as one describe with the given setup
# and teardown. The examples are the framework's contract with any
# adapter: CRUD, finders, validations (including uniqueness), timestamps,
# callbacks, associations with batched eager loading, and transactions.
private def adapter_contract(name : String, setup : Proc(Nil), teardown : Proc(Nil) = -> { }) : Nil
  describe name do
    before_each { setup.call }
    after_each { teardown.call }

    it "creates a record and reads its attributes back" do
      post = Post.create(title: "Hello", views: 3, published: true)
      post.id.should_not be_nil
      Post.count.should eq(1)
      reloaded = Post.find(post.id.not_nil!).not_nil!
      reloaded.title.should eq("Hello")
      reloaded.views.should eq(3)
      reloaded.published.should be_true
    end

    it "finds by primary key and by column" do
      post = Post.create(title: "Hello", views: 0)
      Post.find(post.id.not_nil!).not_nil!.title.should eq("Hello")
      Post.find_by_title("Hello").not_nil!.id.should eq(post.id)
      Post.find_by_title!("Hello").id.should eq(post.id)
      expect_raises(Altair::Record::RecordNotFound) { Post.find_by_title!("Nope") }
      Post.find_by_views(0).should_not be_nil
    end

    it "updates an existing record" do
      post = Post.create(title: "Hello", views: 0)
      post.title = "Updated"
      post.save.should be_true
      Post.find(post.id.not_nil!).not_nil!.title.should eq("Updated")
    end

    it "deletes a record" do
      post = Post.create(title: "Hello", views: 0)
      post.delete.should be_true
      Post.count.should eq(0)
    end

    it "round-trips a JSON column through the adapter coercion" do
      payload = JSON.parse(%({"a": [1, 2, 3], "nested": {"ok": true}}))
      saved = Payload.create(name: "p", data: payload)
      reloaded = Payload.find(saved.id.not_nil!).not_nil!
      reloaded.data.should eq(payload)
      reloaded.update(data: JSON.parse(%({"a": [9]}))).should be_true
      Payload.find(saved.id.not_nil!).not_nil!.data.should eq(JSON.parse(%({"a": [9]})))
    end

    it "round-trips a bigint primary key" do
      event = Event.create(name: "big")
      event.id.should be_a(Int64)
      Event.find!(event.id.not_nil!).name.should eq("big")
      event.update(name: "bigger").should be_true
      Event.find(event.id.not_nil!).not_nil!.name.should eq("bigger")
    end

    it "round-trips a decimal column with full precision" do
      amount = BigDecimal.new("1234567.89")
      account = Account.create(name: "holder", balance: amount)
      reloaded = Account.find(account.id.not_nil!).not_nil!
      reloaded.balance.should eq(amount)
      account.update(balance: BigDecimal.new("20.123")).should be_true
      Account.find(account.id.not_nil!).not_nil!.balance.should eq(BigDecimal.new("20.123"))
    end

    it "scopes the relation with bound clauses" do
      Post.create(title: "one", views: 1, published: true)
      Post.create(title: "two", views: 20, published: false)
      Post.create(title: "three", views: 3, published: true)
      Post.all.where(published: true).where(:views, :>=, 2).order(:views, :desc).limit(1)
        .map(&.title.not_nil!).should eq(["three"])
    end

    it "plucks a column's values" do
      Post.create(title: "A", views: 0)
      Post.create(title: "B", views: 0)
      Post.pluck(:title).compact.map(&.to_s).sort.should eq(["A", "B"])
    end

    it "rejects invalid records" do
      post = Post.new
      post.save.should be_false
      Post.count.should eq(0)
      post.errors[:title].should eq(["can't be blank"])
    end

    it "rejects duplicate values through the uniqueness rule" do
      Tag.create(name: "ruby")
      tag = Tag.new(name: "ruby")
      tag.valid?.should be_false
      tag.errors[:name].should eq(["has already been taken"])
      Tag.create(name: "ruby")
      Tag.count.should eq(1)
    end

    it "allows a record to keep its own unique value on update" do
      tag = Tag.create(name: "ruby")
      tag.name = "ruby"
      tag.valid?.should be_true
    end

    it "runs save callbacks" do
      Comment.events.clear
      Comment.create(post_id: 1, body: "a nice body")
      Comment.events.should eq([:before_save, :before_create, :after_create, :after_save])
      Comment.events.clear
      comment = Comment.all.first
      comment.body = "a longer body"
      comment.save.should be_true
      Comment.events.should eq([:before_save, :before_update, :after_update, :after_save])
    end

    it "sets timestamps on create and update" do
      post = Post.create(title: "Hello", views: 0)
      post.created_at.should_not be_nil
      post.updated_at.should_not be_nil
      before = post.updated_at.not_nil!
      post.title = "Updated"
      post.save.should be_true
      post.updated_at.not_nil!.should be > before
    end

    it "loads belongs_to and has_many associations" do
      post = Post.create(title: "Hello", views: 0)
      comment = Comment.create(post_id: post.id, body: "a nice body")
      comment.post.not_nil!.id.should eq(post.id)
      post.comments.map(&.id).should eq([comment.id])
    end

    it "eager loads associations in batched queries" do
      posts = Array.new(3) { Post.create(title: "P", views: 0) }
      posts.each { |post| Comment.create(post_id: post.id, body: "a nice body") }
      count = queries do
        loaded = Post.all.includes(:comments).to_a
        loaded.each { |post| post.comments.size.should eq(1) }
      end
      count.should eq(2)
    end

    it "derives the model class from an irregular plural name" do
      human = Human.create(name: "hmh")
      child = Child.create(human_id: human.id, name: "kid")
      human.children.map(&.id).should eq([child.id])
    end

    it "destroys children through dependent: :destroy" do
      post = Post.create(title: "Hello", views: 0)
      Comment.create(post_id: post.id, body: "goodbye")
      Comment.events.clear
      post.delete.should be_true
      Comment.count.should eq(0)
      Comment.events.should eq([:before_destroy, :after_destroy])
    end

    it "rolls back a transaction when the block raises" do
      expect_raises(Exception) do
        Post.transaction do
          Post.create(title: "Doomed", views: 0)
          raise "boom"
        end
      end
      Post.count.should eq(0)
    end

    it "runs the migration schema builder" do
      connection = Altair::Record.connection
      connection.exec("DROP TABLE IF EXISTS #{connection.adapter.quote_identifier("widgets")}")
      schema = Altair::Record::Schema.new(connection.adapter, connection)
      schema.create_table(:widgets) do |t|
        t.string :name
        t.integer :count, null: false
      end
      schema.add_column(:widgets, :label, :string)
      schema.add_index(:widgets, :name)
      widget = connection.exec(
        "INSERT INTO #{connection.adapter.quote_identifier("widgets")} " \
        "(#{connection.adapter.quote_identifier("name")}, #{connection.adapter.quote_identifier("count")}, #{connection.adapter.quote_identifier("label")}) " \
        "VALUES (#{connection.adapter.placeholder(0)}, #{connection.adapter.placeholder(1)}, #{connection.adapter.placeholder(2)})",
        "w", 1, "l"
      )
      widget.rows_affected.should eq(1)
      connection.exec("DROP TABLE IF EXISTS #{connection.adapter.quote_identifier("widgets")}")
    end

    it "isolates concurrent transactions across fibers on a server database" do
      unless parallel_writers?
        pending! "SQLite serializes writers — run this on a server database"
      end
      connection = Altair::Record.connection
      n = 4
      arrived = Channel(Nil).new
      go = Channel(Nil).new
      completed = Channel(Int32).new
      n.times do |i|
        spawn do
          Post.transaction do
            Post.create(title: "fiber-#{i}", views: 0)
            arrived.send(nil)
            go.receive
          end
          completed.send(1)
        end
      end
      n.times { arrived.receive }
      n.times { go.send(nil) }
      total = 0
      n.times { total += completed.receive }
      total.should eq(n)
      Post.count.should eq(n)
    end

    it "keeps a rolling-back fiber from rolling back another fiber's work" do
      unless parallel_writers?
        pending! "SQLite serializes writers — run this on a server database"
      end
      connection = Altair::Record.connection
      arrived = Channel(Nil).new
      go = Channel(Nil).new
      done = Channel(Int32).new
      spawn do
        begin
          Post.transaction do
            Post.create(title: "doomed-A", views: 0)
            arrived.send(nil)
            go.receive
            raise "rollback A"
          end
        rescue
        end
        done.send(1)
      end
      arrived.receive
      spawn do
        Post.transaction do
          Post.create(title: "kept-B", views: 0)
        end
        done.send(1)
      end
      go.send(nil)
      2.times { done.receive }
      Post.count.should eq(1)
    end
  end
end

# The schema the contract runs against on PostgreSQL. It mirrors the
# SQLite fixture DDL: same columns, same nullability, same defaults —
# with the adapter's identity primary key.
module PgContract
  # The application instance to restore after the contract examples.
  class_getter original : Altair::Application? = nil

  def self.original=(instance : Altair::Application?) : Nil
    @@original = instance
  end

  def self.setup_database(connection : Altair::Record::Connection) : Nil
    %w[accounts labels payloads events tags children humans articles categories profiles users comments posts].each do |table|
      connection.exec("DROP TABLE IF EXISTS #{connection.adapter.quote_identifier(table)}")
    end
    connection.exec(
      "CREATE TABLE posts (" \
      "\"id\" INTEGER GENERATED ALWAYS AS IDENTITY, " \
      "\"title\" TEXT, \"body\" TEXT, \"views\" INTEGER NOT NULL DEFAULT 0, " \
      "\"published\" BOOLEAN NOT NULL DEFAULT false, \"rating\" DOUBLE PRECISION, \"user_id\" INTEGER, " \
      "\"created_at\" TIMESTAMP, \"updated_at\" TIMESTAMP)"
    )
    connection.exec(
      "CREATE TABLE comments (" \
      "\"id\" INTEGER GENERATED ALWAYS AS IDENTITY, " \
      "\"post_id\" INTEGER, \"body\" TEXT NOT NULL)"
    )
    connection.exec(
      "CREATE TABLE users (" \
      "\"id\" INTEGER GENERATED ALWAYS AS IDENTITY, \"name\" TEXT)"
    )
    connection.exec(
      "CREATE TABLE profiles (" \
      "\"id\" INTEGER GENERATED ALWAYS AS IDENTITY, \"user_id\" INTEGER, \"bio\" TEXT)"
    )
    connection.exec(
      "CREATE TABLE categories (" \
      "\"id\" INTEGER GENERATED ALWAYS AS IDENTITY, \"user_id\" INTEGER, \"name\" TEXT)"
    )
    connection.exec(
      "CREATE TABLE articles (" \
      "\"id\" INTEGER GENERATED ALWAYS AS IDENTITY, \"category_id\" INTEGER, \"title\" TEXT)"
    )
    connection.exec(
      "CREATE TABLE humans (" \
      "\"id\" INTEGER GENERATED ALWAYS AS IDENTITY, \"name\" TEXT)"
    )
    connection.exec(
      "CREATE TABLE children (" \
      "\"id\" INTEGER GENERATED ALWAYS AS IDENTITY, \"human_id\" INTEGER, \"name\" TEXT)"
    )
    connection.exec(
      "CREATE TABLE tags (" \
      "\"id\" INTEGER GENERATED ALWAYS AS IDENTITY, \"name\" TEXT)"
    )
    connection.exec(
      "CREATE TABLE labels (" \
      "\"id\" INTEGER GENERATED ALWAYS AS IDENTITY, \"name\" TEXT, \"kind\" TEXT)"
    )
    connection.exec(
      "CREATE TABLE payloads (" \
      "\"id\" INTEGER GENERATED ALWAYS AS IDENTITY, \"name\" TEXT, \"data\" JSONB)"
    )
    connection.exec(
      "CREATE TABLE events (" \
      "\"id\" BIGINT GENERATED ALWAYS AS IDENTITY, \"name\" TEXT)"
    )
    connection.exec(
      "CREATE TABLE accounts (" \
      "\"id\" INTEGER GENERATED ALWAYS AS IDENTITY, \"name\" TEXT, " \
      "\"balance\" NUMERIC(20,3), \"min_balance\" NUMERIC(20,3) NOT NULL DEFAULT 0)"
    )
  end
end

adapter_contract("SQLite adapter contract", -> { RecordSpec.setup_database })

# Points the shared application at the contract PostgreSQL database.
# The URL is set per example (class bodies run before the suite, when
# the shared application instance already exists).
class PgContractApp < Altair::Application
end

private def pg_setup : Nil
  PgContract.original = Altair.application_instance
  Altair.application_instance = nil
  Altair::Record.close_connection
  PgContractApp.instance
  PgContractApp.config.db_url = ENV["ALTAIR_TEST_PG_URL"]?
  PgContract.setup_database(Altair::Record.connection)
end

private def pg_teardown : Nil
  Altair.application_instance = PgContract.original
  Altair::Record.close_connection
end

if ENV["ALTAIR_TEST_PG_URL"]?
  adapter_contract("PostgreSQL adapter contract", -> { pg_setup }, -> { pg_teardown })
else
  it "runs the PostgreSQL contract suite when ALTAIR_TEST_PG_URL is set" do
    pending! "set ALTAIR_TEST_PG_URL to run the PostgreSQL contract suite"
  end
end
