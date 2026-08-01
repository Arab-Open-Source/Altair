# Altair — the batteries-included web framework for Crystal.
#
# Specs for the exception hierarchy: root class, configuration errors and
# HTTP errors carrying their status.
require "../spec_helper"

describe Altair::Error do
  it "is the root of the framework hierarchy" do
    Altair::ConfigurationError.new("boom").should be_a(Altair::Error)
    Altair::HTTP::NotFound.new.should be_a(Altair::Error)
  end

  it "is an Exception" do
    Altair::Error.new("boom").should be_a(Exception)
  end
end

describe Altair::HTTP::Error do
  it "carries the status to send back to the client" do
    error = Altair::HTTP::NotFound.new
    error.status.should eq(HTTP::Status::NOT_FOUND)
  end

  it "accepts a custom message" do
    Altair::HTTP::NotFound.new("no such post").message.should eq("no such post")
  end
end
