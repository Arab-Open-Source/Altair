# Altair — the batteries-included web framework for Crystal.
#
# Specs for decimal columns (`:decimal` -> `BigDecimal`), which flow through
# the adapter's coercion layer like JSON: bound as text and cast into the
# backend's decimal type, then parsed back. Precision must survive the
# round-trip.
require "./model_fixtures_spec"

describe Altair::Record::Model, "decimal columns" do
  before_each do
    RecordSpec.setup_database
  end

  it "round-trips a decimal on create and load" do
    amount = BigDecimal.new("1234567.89")
    saved = Account.create(name: "holder", balance: amount)
    reloaded = Account.find(saved.id.not_nil!).not_nil!
    reloaded.balance.should eq(amount)
  end

  it "persists a non-null decimal with its schema default" do
    account = Account.create(name: "empty")
    reloaded = Account.find(account.id.not_nil!).not_nil!
    reloaded.min_balance.should eq(BigDecimal.new("0"))
  end

  it "updates a decimal through the dirty-tracking path" do
    account = Account.create(name: "holder", balance: BigDecimal.new("10.5"))
    account.update(balance: BigDecimal.new("20.123")).should be_true
    reloaded = Account.find(account.id.not_nil!).not_nil!
    reloaded.balance.should eq(BigDecimal.new("20.123"))
  end
end
