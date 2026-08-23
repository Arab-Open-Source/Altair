# Altair — specs for Relation#joins and table-qualified where.
require "./model_fixtures_spec"

describe Altair::Record::Relation do
  before_each do
    RecordSpec.setup_database
  end

  it "inner joins a has_many association" do
    post = Post.create(title: "p1", views: 1, published: true)
    Comment.create(post_id: post.id, body: "hello hello")
    Comment.create(post_id: post.id, body: "world hello")

    results = Post.all.joins(:comments).where("comments.body", "hello hello!").to_a
    results.map(&.id).should eq([post.id])
  end

  it "filters through a joined belongs_to" do
    post = Post.create(title: "p1", views: 1, published: true)
    Comment.create(post_id: post.id, body: "match")
    Comment.create(post_id: nil, body: "orphan")

    results = Comment.all.joins(:post).where("posts.title", "p1").to_a
    results.size.should eq(1)
    results.first.body.should eq("match!")
  end

  it "dedupes posts when a post has multiple matching comments" do
    post = Post.create(title: "p1", views: 1, published: true)
    Comment.create(post_id: post.id, body: "same body")
    Comment.create(post_id: post.id, body: "same body")

    results = Post.all.joins(:comments).where("comments.body", "same body!").to_a
    results.size.should eq(1)
    results.first.id.should eq(post.id)
  end

  it "counts distinct posts through a join" do
    post = Post.create(title: "p1", views: 1, published: true)
    Comment.create(post_id: post.id, body: "same body")
    Comment.create(post_id: post.id, body: "same body")

    Post.all.joins(:comments).where("comments.body", "same body!").count.should eq(1)
  end

  it "supports left outer joins" do
    post_with = Post.create(title: "with", views: 1, published: true)
    post_without = Post.create(title: "without", views: 1, published: true)
    Comment.create(post_id: post_with.id, body: "hello world")

    results = Post.all.left_joins(:comments).order(:title).to_a
    results.map(&.title).should eq(["with", "without"])
  end

  it "supports qualified where with operator" do
    Post.create(title: "a", views: 5, published: true)
    post2 = Post.create(title: "b", views: 10, published: true)
    Comment.create(post_id: post2.id, body: "hello")

    results = Post.all.joins(:comments).where("comments.body", "hello!").to_a
    results.map(&.title).should eq(["b"])
  end

  it "chains joins and merges with other scopes" do
    post = Post.create(title: "p1", views: 1, published: true)
    Comment.create(post_id: post.id, body: "hello")

    scope = Post.published.joins(:comments).where("comments.body", "hello!")
    scope.to_a.size.should eq(1)

    merged = Post.published.merge(Post.all.joins(:comments))
    merged.to_a.size.should eq(1)
  end

  it "raises for an unknown association" do
    expect_raises(ArgumentError, /Unknown association :bogus/) do
      Post.all.joins(:bogus).to_a
    end
  end

  it "supports ordering by a qualified column" do
    post_a = Post.create(title: "a", views: 1, published: true)
    post_b = Post.create(title: "b", views: 1, published: true)
    Comment.create(post_id: post_a.id, body: "zebra")
    Comment.create(post_id: post_b.id, body: "apple")

    results = Post.all.joins(:comments).order("comments.body", :asc).to_a
    results.first.title.should eq("b")
  end

  it "keeps joins and distinct through find_each batches" do
    3.times do |i|
      post = Post.create(title: "p#{i}", views: 1, published: true)
      Comment.create(post_id: post.id, body: "same body")
      Comment.create(post_id: post.id, body: "same body")
    end

    collected = [] of Post
    Post.all.joins(:comments).where("comments.body", "same body!").find_each(batch_size: 2) do |post|
      collected << post
    end
    collected.size.should eq(3)
  end
end
