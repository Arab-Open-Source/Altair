# Altair — the batteries-included web framework for Crystal.
#
# Specs for `enum_attribute`: a string column exposed as a compile-time
# checked nested enum. Assignments accept only declared members (anything
# else is a compile error), the column stores the member name in
# snake_case, unknown stored values read back as nil, and the dirty
# tracking baseline round-trips through the enum.
require "./model_fixtures_spec"

describe Altair::Record::Model, "enum_attribute" do
  before_each do
    RecordSpec.setup_database
  end

  it "defines a nested enum with one member per value" do
    Workflow::State::Pending.to_s.should eq("Pending")
    Workflow::State::InReview.to_s.should eq("InReview")
  end

  it "assigns and reads members through a typed accessor" do
    workflow = Workflow.new
    workflow.state = Workflow::State::InReview
    workflow.state.should eq(Workflow::State::InReview)
  end

  it "stores the snake_case member name and round-trips on reload" do
    workflow = Workflow.create(state: "in_review")
    reloaded = Workflow.find(workflow.id.not_nil!).not_nil!
    reloaded.state.should eq(Workflow::State::InReview)
  end

  it "reads an unset column as nil" do
    workflow = Workflow.create
    workflow.state.should be_nil
    Workflow.find(workflow.id.not_nil!).not_nil!.state.should be_nil
  end

  it "reads an unknown stored value as nil" do
    workflow = Workflow.create
    Altair::Record.connection.exec(
      "UPDATE workflows SET state = 'bogus' WHERE id = ?", workflow.id
    )
    Workflow.find(workflow.id.not_nil!).not_nil!.state.should be_nil
  end

  it "finds records through the typed finder overload" do
    Workflow.create(state: "pending")
    found = Workflow.find_by_state(Workflow::State::Pending)
    found.should_not be_nil
    found.not_nil!.state.should eq(Workflow::State::Pending)
  end

  it "marks assignments dirty and restores the previous member" do
    workflow = Workflow.create(state: "pending")
    reloaded = Workflow.find(workflow.id.not_nil!).not_nil!
    reloaded.changed?.should be_false
    reloaded.state = Workflow::State::InReview
    reloaded.changed?.should be_true
    reloaded.attribute_changed?(:state).should be_true
    reloaded.restore_attributes(:state)
    reloaded.state.should eq(Workflow::State::Pending)
    reloaded.changed?.should be_false
  end
end
