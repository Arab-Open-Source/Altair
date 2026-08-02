# Altair — the batteries-included web framework for Crystal.
#
# Specs for the validation DSL of `Altair::Record::Model`: presence, length
# and numericality rules, custom messages, custom validation methods, and
# the save / save! behaviour around them.
require "./model_fixtures_spec"

describe Altair::Record::Model, "validations" do
  before_each do
    RecordSpec.setup_database
  end

  describe "#valid?" do
    it "is true for a record meeting every rule" do
      Post.new(title: "Hello", views: 0).valid?.should be_true
    end

    it "is false when a presence rule fails" do
      post = Post.new
      post.valid?.should be_false
      post.errors[:title].should eq(["can't be blank"])
    end

    it "is false when a length rule fails" do
      post = Post.new(title: "This title is too long", views: 0)
      post.valid?.should be_false
      post.errors[:title].should eq(["is too long (maximum is 10 characters)"])
    end

    it "is false when a numericality rule fails" do
      post = Post.new(title: "Hello", views: -1)
      post.valid?.should be_false
      post.errors[:views].should eq(["must be greater than -1.0"])
    end

    it "runs custom validation methods" do
      post = Post.new(title: "reserved", views: 0)
      post.valid?.should be_false
      post.errors[:title].should eq(["is reserved"])
    end

    it "uses the custom message when given" do
      comment = Comment.new(post_id: 1)
      comment.valid?.should be_false
      comment.errors[:body].should eq(["is required", "is too short (minimum is 5 characters)"])
    end

    it "accumulates errors from every failed rule" do
      post = Post.new(title: "This title is too long", views: -1)
      post.valid?.should be_false
      post.errors[:title].should eq(["is too long (maximum is 10 characters)"])
      post.errors[:views].should eq(["must be greater than -1.0"])
    end

    it "clears previous errors before revalidating" do
      post = Post.new
      post.valid?.should be_false
      post.title = "Hello"
      post.views = 0
      post.valid?.should be_true
      post.errors.should be_empty
    end
  end

  describe "#full_messages" do
    it "prefixes every message with the attribute" do
      post = Post.new
      post.valid?
      post.errors.full_messages.should eq(["title can't be blank"])
    end
  end

  describe "#save" do
    it "returns false and does not persist when invalid" do
      post = Post.new
      post.save.should be_false
      Post.count.should eq(0)
    end

    it "persists when valid" do
      Post.new(title: "Hello", views: 0).save.should be_true
      Post.count.should eq(1)
    end
  end

  describe "#save!" do
    it "raises RecordInvalid carrying the record when invalid" do
      post = Post.new
      expect_raises(Altair::Record::RecordInvalid, /Validation failed: title can't be blank/) do
        post.save!
      end
    end

    it "returns the record when valid" do
      post = Post.new(title: "Hello", views: 0)
      post.save!.should eq(post)
      post.id.should_not be_nil
    end
  end

  describe "#create" do
    it "returns the record even when validations fail" do
      post = Post.create
      post.valid?.should be_false
      Post.count.should eq(0)
    end
  end

  describe "#validates_uniqueness_of" do
    it "accepts a value no other record has" do
      Tag.new(name: "ruby").valid?.should be_true
    end

    it "rejects a value another record has" do
      Tag.create(name: "ruby")
      tag = Tag.new(name: "ruby")
      tag.valid?.should be_false
      tag.errors[:name].should eq(["has already been taken"])
    end

    it "ignores the record's own row when validating an update" do
      tag = Tag.create(name: "ruby")
      tag.name = "ruby"
      tag.valid?.should be_true
    end

    it "allows repeated nil values" do
      Tag.create(name: nil)
      Tag.new.valid?.should be_true
    end

    it "keeps create from persisting a duplicate" do
      Tag.create(name: "ruby")
      Tag.create(name: "ruby")
      Tag.count.should eq(1)
    end
  end

  describe "#validates_uniqueness_of with scope" do
    it "rejects a duplicate within the same scope" do
      Label.create(name: "a", kind: "x")
      label = Label.new(name: "a", kind: "x")
      label.valid?.should be_false
      label.errors[:name].should eq(["is taken"])
    end

    it "accepts the same value in a different scope" do
      Label.create(name: "a", kind: "x")
      Label.new(name: "a", kind: "y").valid?.should be_true
    end
  end
end
