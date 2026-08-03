# Altair — the batteries-included web framework for Crystal.
#
# Specs for JSON columns, which flow through the adapter's coercion layer:
# PostgreSQL binds and reads `JSON::Any` natively, while SQLite stores the
# text form; the model must round-trip identically on both.
require "./model_fixtures_spec"

describe Altair::Record::Model, "JSON columns" do
  before_each do
    RecordSpec.setup_database
  end

  it "round-trips a JSON payload on create and load" do
    payload = JSON.parse(%({"a": 1, "b": [true, "x"]}))
    saved = Payload.create(name: "p", data: payload)
    reloaded = Payload.find(saved.id.not_nil!).not_nil!
    reloaded.data.should eq(payload)
  end

  it "stores nil for an unset JSON column" do
    payload = Payload.create(name: "empty")
    reloaded = Payload.find(payload.id.not_nil!).not_nil!
    reloaded.data.should be_nil
  end

  it "updates a JSON column through the dirty-tracking path" do
    payload = Payload.create(name: "p", data: JSON.parse(%({"k": "v"})))
    payload.update(data: JSON.parse(%({"k": "v2"}))).should be_true
    reloaded = Payload.find(payload.id.not_nil!).not_nil!
    reloaded.data.should eq(JSON.parse(%({"k": "v2"})))
  end
end
