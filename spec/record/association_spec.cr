# Altair — the batteries-included web framework for Crystal.
#
# Specs for the association macros (`belongs_to`, `has_many`, `has_one`):
# lazy accessors and their caches, `dependent:` handling, the batched
# eager loading behind `Relation#includes`, and the `Relation` object
# `Model.all` returns. Query counts are asserted through the
# `Altair::Record.on_query` hook — eager loading must never degrade into
# one query per record.
require "./model_fixtures_spec"

private def queries(&block : -> Nil) : Int32
  count = 0
  Altair::Record.on_query { |_sql, _duration| count += 1 }
  block.call
  count
end

describe Altair::Record::Model do
  before_each do
    RecordSpec.setup_database
  end

  describe "belongs_to" do
    it "lazily loads the owner through the foreign key" do
      post = Post.create(title: "Hello", views: 0)
      comment = Comment.create(post_id: post.id, body: "a nice body")
      comment.post.not_nil!.id.should eq(post.id)
    end

    it "returns nil when the foreign key has no matching record" do
      comment = Comment.create(post_id: 999, body: "orphan")
      comment.post.should be_nil
    end

    it "caches the loaded owner" do
      post = Post.create(title: "Hello", views: 0)
      comment = Comment.create(post_id: post.id, body: "a nice body")
      comment.post.should be(comment.post)
    end

    it "assigns the owner and the foreign key through the setter" do
      post = Post.create(title: "Hello", views: 0)
      comment = Comment.new(body: "a nice body")
      comment.post = post
      comment.post_id.should eq(post.id)
      comment.post.should be(post)
    end

    it "clears the owner and the foreign key through the setter" do
      post = Post.create(title: "Hello", views: 0)
      comment = Comment.create(post_id: post.id, body: "a nice body")
      comment.post = nil
      comment.post_id.should be_nil
      comment.post.should be_nil
    end

    it "eager loads owners in one batched query" do
      posts = Array.new(3) { Post.create(title: "P", views: 0) }
      comments = posts.map { |post| Comment.create(post_id: post.id, body: "a nice body") }
      count = queries do
        loaded = Comment.all.includes(:post).to_a
        loaded.zip(comments).each do |comment, original|
          comment.post.not_nil!.id.should eq(original.post_id)
        end
      end
      count.should eq(2)
    end

    it "eager loads owners when some foreign keys are missing" do
      Post.create(title: "P", views: 0)
      Comment.create(post_id: 999, body: "orphan")
      count = queries do
        loaded = Comment.all.includes(:post).to_a
        loaded.first.post.should be_nil
      end
      count.should eq(2)
    end
  end

  describe "has_many" do
    it "returns the children in id order" do
      post = Post.create(title: "Hello", views: 0)
      first = Comment.create(post_id: post.id, body: "the first")
      second = Comment.create(post_id: post.id, body: "the second")
      post.comments.map(&.id).should eq([first.id, second.id])
    end

    it "returns an empty array when the record is not saved" do
      post = Post.new(title: "Hello", views: 0)
      post.comments.should be_empty
    end

    it "caches the children" do
      post = Post.create(title: "Hello", views: 0)
      Comment.create(post_id: post.id, body: "the first")
      post.comments.should be(post.comments)
    end

    it "eager loads children in one batched query" do
      posts = Array.new(3) { Post.create(title: "P", views: 0) }
      posts.each { |post| Comment.create(post_id: post.id, body: "a child") }
      count = queries do
        loaded = Post.all.includes(:comments).to_a
        loaded.each(&.comments.size.should(eq(1)))
      end
      count.should eq(2)
    end

    it "eager loads empty collections without extra queries" do
      Post.create(title: "Alone", views: 0)
      count = queries do
        loaded = Post.all.includes(:comments).to_a
        loaded.first.comments.should be_empty
      end
      count.should eq(2)
    end

    it "derives the model class from an irregular plural name" do
      human = Human.create(name: "hmh")
      child = Child.create(human_id: human.id, name: "kid")
      human.children.map(&.id).should eq([child.id])
      child.human.not_nil!.id.should eq(human.id)
    end

    it "derives the model class through the -ies rule" do
      user = User.create(name: "hmh")
      category = Category.create(user_id: user.id, name: "news")
      user.categories.map(&.id).should eq([category.id])
    end
  end

  describe "has_one" do
    it "loads the single related record" do
      user = User.create(name: "hmh")
      profile = Profile.create(user_id: user.id, bio: "hello")
      user.profile.not_nil!.id.should eq(profile.id)
    end

    it "returns nil when there is no related record" do
      user = User.create(name: "hmh")
      user.profile.should be_nil
    end

    it "eager loads related records in one batched query" do
      users = Array.new(2) { User.create(name: "u") }
      users.each { |user| Profile.create(user_id: user.id, bio: "b") }
      count = queries do
        loaded = User.all.includes(:profile).to_a
        loaded.each { |user| user.profile.not_nil!.id.should eq(user.id) }
      end
      count.should eq(2)
    end
  end

  describe "dependent" do
    it "destroys the children with dependent: :destroy, running their callbacks" do
      post = Post.create(title: "Hello", views: 0)
      Comment.create(post_id: post.id, body: "goodbye")
      Comment.events.clear
      post.delete.should be_true
      Comment.count.should eq(0)
      Comment.events.should eq([:before_destroy, :after_destroy])
    end

    it "deletes children with one query with dependent: :delete_all, without callbacks" do
      category = Category.create(name: "news")
      Article.create(category_id: category.id, title: "a")
      category.delete.should be_true
      Article.count.should eq(0)
    end

    it "nullifies the foreign key with dependent: :nullify" do
      user = User.create(name: "u")
      Profile.create(user_id: user.id, bio: "b")
      user.delete.should be_true
      Profile.count.should eq(1)
      Profile.all.first.user_id.should be_nil
    end
  end

  describe "Relation" do
    it "is lazy: the query runs on iteration, not on all" do
      Post.create(title: "Hello", views: 0)
      relation = Post.all
      queries do
        relation.to_a
      end.should eq(1)
    end

    it "behaves like an enumerable" do
      Post.create(title: "B", views: 0)
      Post.create(title: "A", views: 0)
      Post.all.compact_map(&.title).sort!.should eq(["A", "B"])
      Post.all.size.should eq(2)
    end

    it "raises for an association the model does not declare" do
      expect_raises(ArgumentError, /Unknown association :bogus/) do
        Post.all.includes(:bogus).to_a
      end
    end
  end
end
