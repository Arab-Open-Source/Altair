# Altair — specs for has_many :through
require "./model_fixtures_spec"

describe "has_many :through" do
  before_each do
    RecordSpec.setup_database
  end

  it "loads through association lazily" do
    post = Post.create(title: "p1", views: 1, published: true)
    tag1 = Tag.create(name: "crystal")
    tag2 = Tag.create(name: "web")
    PostTag.create(post_id: post.id, tag_id: tag1.id)
    PostTag.create(post_id: post.id, tag_id: tag2.id)

    post.tags.compact_map(&.name).sort!.should eq(["crystal", "web"])
  end

  it "returns empty when no through records" do
    post = Post.create(title: "p1", views: 1, published: true)
    post.tags.should eq([] of Tag)
  end

  it "eager loads through association via includes" do
    post1 = Post.create(title: "p1", views: 1, published: true)
    post2 = Post.create(title: "p2", views: 1, published: true)
    tag = Tag.create(name: "shared")
    PostTag.create(post_id: post1.id, tag_id: tag.id)
    PostTag.create(post_id: post2.id, tag_id: tag.id)

    queried = 0
    Altair::Record.on_query { |_sql, _dur| queried += 1 }
    # 1 for posts, 1 for tags through, but not per post
    posts = Post.all.includes(:tags).order(:title).to_a
    # We don't count exactly, but should be 2 queries total (posts + tags)
    # The on_query hook counts all queries including setup, so we check relative
    posts.size.should eq(2)
    posts[0].tags.compact_map(&.name).should eq(["shared"])
    posts[1].tags.compact_map(&.name).should eq(["shared"])
    # Access again should not query
    before = queried
    posts[0].tags
    queried.should eq(before)
  end

  it "infers source when not given" do
    post = Post.create(title: "p1", views: 1, published: true)
    tag = Tag.create(name: "inferred")
    PostTag.create(post_id: post.id, tag_id: tag.id)

    # has_many :tags, through: :post_tags without explicit source: :tag
    # should infer source :tag
    post.tags.first.not_nil!.name.should eq("inferred")
  end

  it "supports joins through the association" do
    post1 = Post.create(title: "p1", views: 1, published: true)
    Post.create(title: "p2", views: 1, published: true)
    tag = Tag.create(name: "findme")
    PostTag.create(post_id: post1.id, tag_id: tag.id)

    results = Post.all.joins(:tags).where("tags.name", "findme").to_a
    results.map(&.id).should eq([post1.id])
  end
end
