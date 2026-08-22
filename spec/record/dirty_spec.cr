# Altair — the batteries-included web framework for Crystal.
#
# Specs for the public dirty-tracking API: `changed?`,
# `changed_attributes`, `attribute_changed?` and `restore_attributes`.
# Originals snapshot on load and after every successful save, so restores
# always have a well-defined baseline.
require "./model_fixtures_spec"

describe Altair::Record::Model, "dirty tracking" do
  before_each do
    RecordSpec.setup_database
  end

  it "reports a new record as unchanged" do
    post = Post.new(title: "fresh")
    post.changed?.should be_false
    post.changed_attributes.should eq([] of Symbol)
  end

  it "marks assigned attributes as changed" do
    post = Post.new
    post.title = "Hello"
    post.changed?.should be_true
    post.attribute_changed?(:title).should be_true
    post.attribute_changed?(:views).should be_false
    post.changed_attributes.should eq([:title])
  end

  it "clears state after a load from the database" do
    Post.insert_all([{title: "loaded", views: 1, published: false}])
    post = Post.find_by_title("loaded").not_nil!
    post.changed?.should be_false
    post.changed_attributes.should eq([] of Symbol)
  end

  it "clears state after a successful save" do
    post = Post.new(title: "saving", views: 2, published: true)
    post.title = "saved"
    post.changed?.should be_true
    post.save.should be_true
    post.changed?.should be_false
    post.changed_attributes.should eq([] of Symbol)
  end

  it "restores a loaded attribute to its original value" do
    post = Post.create(title: "original", views: 5, published: true)
    reloaded = Post.find(post.id.not_nil!).not_nil!
    reloaded.title = "mutated"
    reloaded.views = 99
    reloaded.restore_attributes(:title)
    reloaded.title.should eq("original")
    reloader_views_kept = reloaded.views
    reloader_views_kept.should eq(99)
    reloaded.attribute_changed?(:title).should be_false
    reloaded.attribute_changed?(:views).should be_true
  end

  it "restores every changed attribute when no names are given" do
    post = Post.create(title: "keep", views: 1, published: false)
    reloaded = Post.find(post.id.not_nil!).not_nil!
    reloaded.title = "a"
    reloaded.views = 42
    reloaded.published = true
    reloaded.restore_attributes
    reloaded.changed?.should be_false
    reloaded.title.should eq("keep")
    reloaded.views.should eq(1)
    reloaded.published.should be_false
  end

  it "keeps a restored record saveable with only the surviving changes" do
    post = Post.create(title: "base", views: 1, published: false)
    reloaded = Post.find(post.id.not_nil!).not_nil!
    reloaded.title = "changed"
    reloaded.views = 9
    reloaded.restore_attributes(:title)
    reloaded.save.should be_true
    again = Post.find(post.id.not_nil!).not_nil!
    again.title.should eq("base")
    again.views.should eq(9)
  end

  it "raises when restoring an attribute the table does not have" do
    post = Post.create(title: "x", views: 0, published: false)
    expect_raises(ArgumentError, "nonesuch") do
      post.restore_attributes(:nonesuch)
    end
  end
end
