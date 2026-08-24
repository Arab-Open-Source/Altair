# Altair — the batteries-included web framework for Crystal.
#
# Specs for the query DSL on `Altair::Record::Relation`: `where`, `order`,
# `limit`, `offset` and `find_each`. Queries run lazily on iteration.
require "./model_fixtures_spec"

private def queries(&block : -> Nil) : Int32
  count = 0
  Altair::Record.on_query { |_sql, _duration| count += 1 }
  block.call
  count
end

describe Altair::Record::Relation do
  before_each do
    RecordSpec.setup_database
    Post.create(title: "alpha", views: 3, published: true)
    Post.create(title: "beta", views: 30, published: false)
    Post.create(title: "gamma", views: 12, published: true)
    Post.create(title: "delta", views: 45, published: false)
  end

  it "filters by column equality" do
    Post.all.where(published: true).map(&.title.not_nil!).sort!.should eq(["alpha", "gamma"])
  end

  it "filters by multiple keyword pairs" do
    Post.all.where(title: "gamma", published: true).map(&.title.not_nil!).should eq(["gamma"])
  end

  it "filters with a comparison operator" do
    Post.all.where(:views, :>=, 15).map(&.title.not_nil!).sort!.should eq(["beta", "delta"])
  end

  it "orders by a column" do
    Post.all.order(:views, :desc).map(&.views).should eq([45, 30, 12, 3])
  end

  it "limits and offsets the rows" do
    Post.all.order(:views, :desc).limit(2).map(&.views).should eq([45, 30])
    Post.all.order(:views, :desc).limit(2).offset(1).map(&.views).should eq([30, 12])
  end

  it "chains where clauses with AND" do
    Post.all.where(published: true).where(:views, :>=, 11).map(&.title.not_nil!).should eq(["gamma"])
  end

  it "keeps the relation lazy and caches after iteration" do
    relation = Post.all.where(published: true)
    Post.create(title: "epsilon", views: 1, published: true)
    relation.map(&.title.not_nil!).sort!.should eq(["alpha", "epsilon", "gamma"])
  end

  it "yields every row in bounded batches" do
    yielded = [] of String
    Post.all.find_each(batch_size: 3) { |post| yielded << post.title.not_nil! }
    yielded.sort.should eq(["alpha", "beta", "delta", "gamma"])
  end

  it "applies the scoped where filters to every batch" do
    yielded = [] of String
    Post.all.where(published: true).find_each(batch_size: 2) { |post| yielded << post.title.not_nil! }
    yielded.sort.should eq(["alpha", "gamma"])
  end

  it "keeps the eager loading across batches" do
    posts = Post.all.to_a
    posts.each { |post| Comment.create(post_id: post.id, body: "a nice body") }
    count = queries do
      touched = 0
      Post.all.includes(:comments).find_each(batch_size: 2) do |post|
        touched += post.comments.size
      end
      touched.should eq(4)
    end
    count.should eq(4)
  end

  it "yields every row with a batch size of one" do
    yielded = [] of String
    Post.all.find_each(batch_size: 1) { |post| yielded << post.title.not_nil! }
    yielded.sort.should eq(["alpha", "beta", "delta", "gamma"])
  end

  it "yields an exact multiple of the batch size" do
    yielded = [] of String
    Post.all.find_each(batch_size: 2) { |post| yielded << post.title.not_nil! }
    yielded.sort.should eq(["alpha", "beta", "delta", "gamma"])
  end

  it "counts the scoped rows with a single query" do
    count = queries { Post.all.where(published: true).count.to_i.should eq(2) }
    count.should eq(1)
  end

  it "uses the cached records once loaded, without another query" do
    count = queries do
      relation = Post.all.where(published: true)
      relation.to_a.size.should eq(2)
      relation.count.should eq(2_i64)
      relation.size.should eq(2)
    end
    count.should eq(1)
  end

  it "counts within limit and offset" do
    Post.all.count.should eq(4)
    Post.all.limit(3).count.should eq(3)
    Post.all.limit(2).offset(2).count.should eq(2)
    Post.all.offset(3).count.should eq(1)
  end
end
