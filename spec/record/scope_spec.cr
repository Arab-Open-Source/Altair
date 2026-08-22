# Altair — the batteries-included web framework for Crystal.
#
# Specs for the `scope` macro: reusable named query fragments, in static
# (NamedTuple) and block forms, chainable with each other and with the
# plain Relation methods.
require "./model_fixtures_spec"

private def seed_posts : Nil
  Post.create(title: "quiet-a", views: 10, published: true)
  Post.create(title: "loud-b", views: 90, published: true)
  Post.create(title: "loud-c", views: 70, published: false)
end

describe Altair::Record::Model, "scopes" do
  before_each do
    RecordSpec.setup_database
  end

  it "filters through a static NamedTuple scope" do
    seed_posts
    titles = Post.published.to_a.map(&.title.not_nil!).sort!
    titles.should eq(["loud-b", "quiet-a"])
  end

  it "applies order and limit through a block scope" do
    seed_posts
    Post.all.where(published: true)
    top = Post.popular.to_a
    top.map(&.title).should eq(["loud-b", "loud-c"])
  end

  it "chains scopes with each other" do
    seed_posts
    Post.published.merge(Post.popular).to_a.map(&.title).should eq(["loud-b"])
  end

  it "chains a scope with plain Relation methods" do
    seed_posts
    Post.published.where(:views, :>=, 20).count.should eq(1)
  end

  it "merges where clauses from both sides and keeps the stricter count" do
    seed_posts
    Post.published.merge(Post.all.where(:views, :>=, 20)).count.should eq(1)
    Post.popular.merge(Post.published).count.should eq(1)
  end
end
