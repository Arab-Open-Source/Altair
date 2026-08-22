# Altair — the batteries-included web framework for Crystal.
#
# Specs for nested `includes`: `includes(posts: :comments)` schedules the
# second level's batched load on the already-loaded children, so two
# levels of association materialize through the same fixed number of
# batched queries as a flat `includes` — never one query per record.
require "./model_fixtures_spec"

private def seed_chain : Nil
  2.times do |index|
    user = User.create(name: "user #{index}")
    post = Post.create(title: "post #{index}", views: index + 1, published: true, user_id: user.id)
    Comment.create(post_id: post.id, body: "c1 for #{index}")
    Comment.create(post_id: post.id, body: "c2 for #{index}")
  end
end

describe Altair::Record::Relation, "nested includes" do
  before_each do
    RecordSpec.setup_database
  end

  it "loads the second level onto the loaded children" do
    seed_chain
    users = User.all.includes(posts: :comments).to_a
    users.first.posts.size.should eq(1)
    users.first.posts.first.comments.first.body.should eq("c1 for 0!")
    users.last.posts.first.comments.last.body.should eq("c2 for 1!")
  end

  it "nests through belongs_to back-references" do
    seed_chain
    post = Post.all.includes(comments: :post).to_a.first
    comment = post.comments.first
    comment.body.should eq("c1 for 0!")
    comment.post.not_nil!.title.should eq("post 0")
  end

  it "recurses through a NamedTuple spec to the third table" do
    seed_chain
    user = User.all.includes(posts: {comments: :post}).to_a.first
    comment = user.posts.first.comments.first
    comment.post.not_nil!.id.should eq(user.posts.first.id)
    comment.body.should eq("c1 for 0!")
  end

  it "keeps plain symbol includes working alongside nested ones" do
    seed_chain
    Post.all.includes(:comments).to_a.first.comments.size.should eq(2)
  end
end
