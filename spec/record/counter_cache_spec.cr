# Altair — counter cache and batched dependent specs.
#
# Specs for `belongs_to ..., counter_cache:` maintaining an `<assoc>_count`
# column on the owner, and `has_many ..., dependent: :destroy` collapsing
# to a single DELETE when the child model declares no destroy callbacks.
require "./model_fixtures_spec"

class CountedPost < Altair::Record::Model
  table :posts

  has_many :counted_comments, class_name: "CountedComment", foreign_key: :post_id, dependent: :destroy
end

class CountedComment < Altair::Record::Model
  table :comments

  belongs_to :counted_post, class_name: "CountedPost", foreign_key: :post_id, counter_cache: :comments_count
end

class BatchHuman < Altair::Record::Model
  table :humans

  has_many :kids, class_name: "BatchKid", foreign_key: :human_id, dependent: :destroy
end

class BatchKid < Altair::Record::Model
  table :children
end

describe "counter caches" do
  before_each do
    RecordSpec.setup_database
  end

  it "increments the owner count when a child is created" do
    post = CountedPost.create(title: "owner", views: 1, published: true)
    CountedComment.create(post_id: post.id.not_nil!, body: "first comment")
    post.reload.comments_count.should eq(1)
    CountedComment.create(post_id: post.id.not_nil!, body: "second comment")
    post.reload.comments_count.should eq(2)
  end

  it "decrements the owner count when a child is deleted" do
    post = CountedPost.create(title: "owner", views: 1, published: true)
    child = CountedComment.create(post_id: post.id.not_nil!, body: "first comment")
    child.delete
    post.reload.comments_count.should eq(0)
  end

  it "keeps counts consistent through a parent destroy" do
    post = CountedPost.create(title: "owner", views: 1, published: true)
    2.times { |n| CountedComment.create(post_id: post.id.not_nil!, body: "comment #{n}xx") }
    post.delete
    CountedComment.all.where(post_id: post.id).to_a.should be_empty
  end

  it "leaves other owners untouched" do
    kept = CountedPost.create(title: "kept", views: 1, published: true)
    other = CountedPost.create(title: "other", views: 1, published: true)
    CountedComment.create(post_id: kept.id.not_nil!, body: "belongs to kept")
    CountedComment.create(post_id: other.id.not_nil!, body: "belongs to other")
    kept.reload.comments_count.should eq(1)
    other.reload.comments_count.should eq(1)
  end

  it "destroys callback-free children with one DELETE statement" do
    human = BatchHuman.create(name: "parent")
    3.times { |n| BatchKid.create(human_id: human.id.not_nil!, name: "kid #{n}") }
    deletes = [] of String
    counter = 0
    Altair::Record.on_query do |sql, _|
      counter += 1
      deletes << sql if sql.lstrip.upcase.starts_with?("DELETE")
    end
    human.delete
    counter.should eq(2)
    deletes.size.should eq(2)
    BatchKid.all.to_a.should be_empty
  end
end
