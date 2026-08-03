# Altair — the batteries-included web framework for Crystal.
#
# Specs for a model whose primary key is a `:bigint` column. The `id`
# attribute must be typed `Int64` end to end: reading the generated value
# after insert, finding by a wide id, updating, and deleting.
require "./model_fixtures_spec"

describe Altair::Record::Model, "bigint primary key" do
  before_each do
    RecordSpec.setup_database
  end

  it "reads the id as an Int64 after insert" do
    event = Event.create(name: "first")
    event.id.should be_a(Int64)
    event.id.should_not be_nil
  end

  it "finds by a wide id" do
    event = Event.create(name: "wide")
    Event.find(event.id.not_nil!).not_nil!.name.should eq("wide")
    Event.find!(event.id.not_nil!).id.should eq(event.id)
    Event.exists?(event.id.not_nil!).should be_true
  end

  it "updates and deletes by a wide id" do
    event = Event.create(name: "before")
    event.update(name: "after").should be_true
    Event.find(event.id.not_nil!).not_nil!.name.should eq("after")
    event.delete.should be_true
    Event.count.should eq(0)
  end
end
