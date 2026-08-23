require "../spec_helper"

describe Altair::Cache::MemoryStore do
  it "reads, overwrites and deletes values" do
    store = Altair::Cache::MemoryStore.new
    store.read("home").should be_nil
    store.write("home", "first").should eq("first")
    store.read("home").should eq("first")
    store.write("home", "second")
    store.read("home").should eq("second")
    store.delete("home").should be_true
    store.read("home").should be_nil
  end

  it "computes a missing value once and retains it" do
    store = Altair::Cache::MemoryStore.new
    calls = 0
    store.fetch("homepage") { calls += 1; "rendered" }.should eq("rendered")
    store.fetch("homepage") { calls += 1; "new" }.should eq("rendered")
    calls.should eq(1)
  end

  it "expires values and clears the store" do
    store = Altair::Cache::MemoryStore.new
    store.write("short", "value", 0.seconds)
    store.read("short").should be_nil
    store.write("one", "1")
    store.write("two", "2")
    store.clear
    store.read("one").should be_nil
    store.read("two").should be_nil
  end
end
