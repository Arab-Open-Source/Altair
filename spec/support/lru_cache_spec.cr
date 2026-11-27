require "../spec_helper"

describe Altair::Support::LRUCache do
  it "deletes an existing key and reports missing keys" do
    cache = Altair::Support::LRUCache(String, Int32).new(2)
    cache.put("a", 1)
    cache.put("b", 2)

    cache.delete("a").should be_true
    cache.size.should eq(1)
    cache.get("a").should be_nil
    cache.get("b").should eq(2)
    cache.delete("missing").should be_false
  end

  it "keeps the linked list consistent after deleting middle, head, and tail entries" do
    cache = Altair::Support::LRUCache(String, Int32).new(3)
    cache.put("a", 1)
    cache.put("b", 2)
    cache.put("c", 3)

    cache.delete("b").should be_true
    cache.get("a").should eq(1)
    cache.get("c").should eq(3)
    cache.delete("c").should be_true
    cache.delete("a").should be_true
    cache.size.should eq(0)

    cache.put("d", 4)
    cache.get("d").should eq(4)
  end
end
