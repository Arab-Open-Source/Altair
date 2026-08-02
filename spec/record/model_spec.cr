# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Record::Model`: typed attributes, create/find/all,
# find_by_* finders, update/delete, auto-timestamps, pluck and
# transactions, over the shared fixtures in `model_fixtures_spec.cr`.
require "./model_fixtures_spec"

# SQLite stores times with millisecond precision, so a record reloaded
# from the database differs from its in-memory original by microseconds.
private def expect_equivalent(post : Post, other : Post) : Nil
  other.id.should eq(post.id)
  other.title.should eq(post.title)
  other.body.should eq(post.body)
  other.views.should eq(post.views)
  other.published.should eq(post.published)
  other.rating.should eq(post.rating)
  other.created_at.not_nil!.should be_close(post.created_at.not_nil!, 1.millisecond)
  other.updated_at.not_nil!.should be_close(post.updated_at.not_nil!, 1.millisecond)
end

describe Altair::Record::Model do
  before_each do
    RecordSpec.setup_database
  end

  describe "attributes" do
    it "defaults every column to a schema-derived value" do
      post = Post.new
      post.id.should be_nil
      post.title.should be_nil
      post.views.should eq(0)
      post.published.should be_false
      post.rating.should be_nil
      post.created_at.should be_nil
    end

    it "reads and writes typed attributes" do
      post = Post.new(title: "Hello", views: 3, published: true)
      post.title.should eq("Hello")
      post.views.should eq(3)
      post.published.should be_true
      post.title = "Hi"
      post.title.should eq("Hi")
    end
  end

  describe ".create" do
    it "inserts the record and sets its id" do
      post = Post.create(title: "Hello", views: 2)
      post.id.should_not be_nil
      post.title.should eq("Hello")
      Post.count.should eq(1)
    end

    it "persists every column type" do
      post = Post.create(title: "Types", body: "body", views: 4, published: true, rating: 3.5)
      reloaded = Post.find(post.id.not_nil!).not_nil!
      reloaded.title.should eq("Types")
      reloaded.body.should eq("body")
      reloaded.views.should eq(4)
      reloaded.published.should be_true
      reloaded.rating.should eq(3.5)
    end

    it "keeps empty strings distinct from NULL" do
      post = Post.create(title: "T", body: "")
      reloaded = Post.find(post.id.not_nil!).not_nil!
      reloaded.body.should eq("")
      reloaded.body.should_not be_nil

      nulled = Post.create(title: "N", views: 0)
      Post.find(nulled.id.not_nil!).not_nil!.body.should be_nil
    end
  end

  describe ".find" do
    it "returns the record with the given id" do
      post = Post.create(title: "Hello")
      expect_equivalent(post, Post.find(post.id.not_nil!).not_nil!)
    end

    it "returns nil for a missing id" do
      Post.find(999).should be_nil
    end
  end

  describe ".find!" do
    it "returns the record with the given id" do
      post = Post.create(title: "Hello")
      expect_equivalent(post, Post.find!(post.id.not_nil!))
    end

    it "raises RecordNotFound for a missing id" do
      expect_raises(Altair::Record::RecordNotFound, /Couldn't find posts with id=999/) do
        Post.find!(999)
      end
    end
  end

  describe ".all" do
    it "returns every record" do
      first = Post.create(title: "First")
      second = Post.create(title: "Second")
      Post.all.map(&.id).should eq([first.id, second.id])
      Post.all.map(&.title).should eq(["First", "Second"])
    end

    it "returns an empty array when there are no records" do
      Post.all.should be_empty
    end
  end

  describe ".count" do
    it "counts the records" do
      Post.count.should eq(0)
      Post.create(title: "One")
      Post.create(title: "Two")
      Post.count.should eq(2)
    end
  end

  describe ".exists?" do
    it "reports whether any record exists" do
      Post.exists?.should be_false
      Post.create(title: "Hello")
      Post.exists?.should be_true
    end

    it "reports whether a record with the given id exists" do
      post = Post.create(title: "Hello")
      Post.exists?(post.id.not_nil!).should be_true
      Post.exists?(999).should be_false
    end
  end

  describe "find_by_*" do
    it "finds by a string column" do
      post = Post.create(title: "Hello")
      expect_equivalent(post, Post.find_by_title("Hello").not_nil!)
      Post.find_by_title("Nope").should be_nil
    end

    it "finds by a boolean column" do
      post = Post.create(title: "Published", published: true)
      Post.create(title: "Draft", published: false)
      expect_equivalent(post, Post.find_by_published(true).not_nil!)
    end

    it "finds by an integer column" do
      post = Post.create(title: "Popular", views: 42)
      expect_equivalent(post, Post.find_by_views(42).not_nil!)
    end

    it "matches NULL on a nullable column" do
      post = Post.create(title: "No rating")
      expect_equivalent(post, Post.find_by_rating(nil).not_nil!)
    end

    it "raises RecordNotFound from the bang variant" do
      expect_raises(Altair::Record::RecordNotFound, /Couldn't find posts with title="Nope"/) do
        Post.find_by_title!("Nope")
      end
    end
  end

  describe "#update" do
    it "updates the given columns and saves" do
      post = Post.create(title: "Before", views: 1)
      post.update(title: "After").should be_true
      reloaded = Post.find!(post.id.not_nil!)
      reloaded.title.should eq("After")
      reloaded.views.should eq(1)
    end

    it "updates every column type" do
      post = Post.create(title: "T", views: 0)
      post.update(body: "b", views: 9, published: true, rating: 1.5)
      reloaded = Post.find!(post.id.not_nil!)
      reloaded.body.should eq("b")
      reloaded.views.should eq(9)
      reloaded.published.should be_true
      reloaded.rating.should eq(1.5)
    end

    it "returns false when validations fail" do
      post = Post.create(title: "Valid")
      post.update(title: "This title is way too long").should be_false
      Post.find!(post.id.not_nil!).title.should eq("Valid")
    end
  end

  describe "#delete" do
    it "removes the row" do
      post = Post.create(title: "Gone")
      post.delete.should be_true
      Post.find(post.id.not_nil!).should be_nil
      Post.count.should eq(0)
    end

    it "returns false for an unsaved record" do
      Post.new.delete.should be_false
    end
  end

  describe "timestamps" do
    it "sets created_at and updated_at on create" do
      post = Post.create(title: "Timed")
      post.created_at.should_not be_nil
      post.updated_at.should_not be_nil
      (Time.utc - post.created_at.not_nil!).should be < 5.seconds
    end

    it "bumps updated_at but not created_at on update" do
      post = Post.create(title: "Timed")
      created_at = post.created_at.not_nil!
      sleep 10.milliseconds
      post.update(title: "Touched")
      post.created_at.should eq(created_at)
      post.updated_at.not_nil!.should be > created_at
    end
  end

  describe ".pluck" do
    it "returns the values of a column" do
      Post.create(title: "A", views: 1)
      Post.create(title: "B", views: 2)
      Post.pluck(:title).should eq(["A", "B"])
    end

    it "includes NULL values for nullable columns" do
      Post.create(title: "A")
      Post.pluck(:title).should eq(["A"])
      Post.pluck(:rating).should eq([nil])
    end
  end

  describe ".transaction" do
    it "commits when the block succeeds" do
      Post.transaction do
        Post.create(title: "Committed")
      end
      Post.count.should eq(1)
    end

    it "rolls back when the block raises" do
      expect_raises(Exception, "boom") do
        Post.transaction do
          Post.create(title: "Rolled back")
          raise "boom"
        end
      end
      Post.count.should eq(0)
    end

    it "supports nested transactions via savepoints" do
      Post.create(title: "Kept")
      Post.transaction do
        Post.create(title: "Outer")
        Post.transaction do
          Post.create(title: "Discarded")
          raise DB::Rollback.new
        end
        Post.create(title: "Outer too")
      end
      Post.all.compact_map(&.title).sort!.should eq(["Kept", "Outer", "Outer too"])
    end

    it "rolls back every nested savepoint when the outer block raises" do
      expect_raises(Exception, "boom") do
        Post.transaction do
          Post.create(title: "A")
          Post.transaction do
            Post.create(title: "B")
          end
          raise "boom"
        end
      end
      Post.count.should eq(0)
    end
  end
end
