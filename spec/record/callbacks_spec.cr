# Altair — the batteries-included web framework for Crystal.
#
# Specs for the callback DSL of `Altair::Record::Model`: save, create,
# update and destroy callbacks, their ordering, and mutation of the record
# before it is persisted.
require "./model_fixtures_spec"

describe Altair::Record::Model, "callbacks" do
  before_each do
    RecordSpec.setup_database
    Comment.events.clear
  end

  it "runs the save and create callbacks around an insert, in order" do
    Comment.create(post_id: 1, body: "hello")
    Comment.events.should eq([:before_save, :before_create, :after_create, :after_save])
  end

  it "runs the save and update callbacks around an update" do
    comment = Comment.create(post_id: 1, body: "hello")
    Comment.events.clear
    comment.update(body: "world").should be_true
    Comment.events.should eq([:before_save, :before_update, :after_update, :after_save])
  end

  it "runs the destroy callbacks" do
    comment = Comment.create(post_id: 1, body: "hello")
    Comment.events.clear
    comment.delete.should be_true
    Comment.events.should eq([:before_destroy, :after_destroy])
  end

  it "does not run create callbacks when validations fail" do
    Comment.create(post_id: 1)
    Comment.events.should be_empty
    Comment.count.should eq(0)
  end

  it "lets callbacks mutate the record before insert" do
    comment = Comment.create(post_id: 1, body: "hello")
    comment.body.should eq("hello!")
    Comment.find!(comment.id.not_nil!).body.should eq("hello!")
  end

  it "lets callbacks mutate the record before update" do
    comment = Comment.create(post_id: 1, body: "hello")
    comment.update(body: "world")
    comment.body.should eq("world!")
  end
end
