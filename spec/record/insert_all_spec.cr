# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Model.insert_all`: bulk inserts that bypass validations and
# callbacks, auto-fill timestamps, reject unknown columns, bind JSON
# values through the adapter's coercion layer, and chunk large sets inside
# one transaction so a bulk load stays all-or-nothing.
require "./model_fixtures_spec"

describe Altair::Record::Model, ".insert_all" do
  before_each do
    RecordSpec.setup_database
  end

  it "inserts many rows in one call and returns the count" do
    inserted = Post.insert_all([
      {title: "one", views: 1, published: true},
      {title: "two", views: 2, published: false},
      {title: "three", views: 3, published: true},
    ])
    inserted.should eq(3)
    Post.count.should eq(3)
    Post.find_by_title("two").not_nil!.views.should eq(2)
  end

  it "auto-fills created_at and updated_at like create" do
    before = Time.utc
    Post.insert_all([{title: "stamped", views: 0, published: false}])
    post = Post.find_by_title("stamped").not_nil!
    post.created_at.not_nil!.should be_close(before, 5.seconds)
    post.updated_at.not_nil!.should be_close(before, 5.seconds)
  end

  it "keeps caller-supplied timestamps instead of overwriting them" do
    stamp = Time.utc(2020, 1, 1)
    Post.insert_all([{title: "old", views: 0, published: false, created_at: stamp}])
    post = Post.find_by_title("old").not_nil!
    post.created_at.not_nil!.year.should eq(2020)
  end

  it "returns zero without touching the database for no rows" do
    Post.insert_all([] of {title: String, views: Int32, published: Bool}).should eq(0)
    Post.exists?.should be_false
  end

  it "binds missing attributes as NULL" do
    Post.insert_all([{title: "sparse", views: 4, published: false}])
    post = Post.find_by_title("sparse").not_nil!
    post.rating.should be_nil
    post.user_id.should be_nil
  end

  it "raises on an unknown column" do
    expect_raises(ArgumentError, "nonesuch") do
      Post.insert_all([{title: "x", views: 0, published: false, nonesuch: 1}])
    end
    Post.count.should eq(0)
  end

  it "rejects rows targeting the primary key" do
    expect_raises(ArgumentError, "id") do
      Post.insert_all([{id: 9, title: "x", views: 0, published: false}])
    end
    Post.count.should eq(0)
  end

  it "bypasses validations as a documented bulk path" do
    Post.insert_all([{title: "reserved", views: 0, published: false}])
    Post.find_by_title("reserved").should_not be_nil
  end

  it "binds JSON values through the adapter coercion" do
    payload = JSON.parse(%({"bulk": [1, 2]}))
    Payload.insert_all([{name: "a", data: payload}, {name: "b"}])
    Payload.find_by_name("a").not_nil!.data.should eq(payload)
    Payload.find_by_name("b").not_nil!.data.should be_nil
  end

  it "chunks sets past the bind limit inside one transaction" do
    rows = (1..120).map { |i| {title: "row #{i}", views: i, published: true} }
    Post.insert_all(rows).should eq(120)
    Post.count.should eq(120)
    Post.all.where(views: 120).count.should eq(1)
  end
end
