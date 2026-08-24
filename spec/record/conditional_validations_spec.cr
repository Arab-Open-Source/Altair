# Altair — conditional validation specs.
#
# Specs for `if:` / `unless:` predicates and `allow_nil:` on the
# validation macros, plus `case_sensitive: false` uniqueness matching.
require "./model_fixtures_spec"

class TrustedUser < Altair::Record::Model
  table :users

  class_property? strict = false

  validates_length_of :name, minimum: 5, if: :strict?

  def strict? : Bool
    @@strict
  end
end

class GuestUser < Altair::Record::Model
  table :users

  class_property? as_guest = true

  validates_presence_of :name, unless: :as_guest?

  def as_guest? : Bool
    @@as_guest
  end
end

class NilTolerantProfile < Altair::Record::Model
  table :profiles

  validates_format_of :bio, with: /@/, allow_nil: true
end

class CasefoldUser < Altair::Record::Model
  table :users

  validates_uniqueness_of :name, case_sensitive: false
end

describe "conditional validations" do
  before_each do
    RecordSpec.setup_database
    TrustedUser.strict = false
    GuestUser.as_guest = true
  end

  it "skips a rule while its if: predicate is false" do
    TrustedUser.create(name: "abc").should_not be_nil
  end

  it "applies the rule once its if: predicate turns true" do
    TrustedUser.strict = true
    TrustedUser.new(name: "abc").valid?.should be_false
    TrustedUser.new(name: "abcdef").valid?.should be_true
  end

  it "skips a rule while its unless: predicate is true" do
    GuestUser.new(name: nil).valid?.should be_true
  end

  it "applies the rule once its unless: predicate turns false" do
    GuestUser.as_guest = false
    GuestUser.new(name: nil).valid?.should be_false
  end

  it "allows nil through an allow_nil: rule but still rejects bad values" do
    NilTolerantProfile.new(bio: nil).valid?.should be_true
    NilTolerantProfile.new(bio: "no at sign here").valid?.should be_false
  end

  it "matches uniqueness case-insensitively with case_sensitive: false" do
    CasefoldUser.create(name: "Sammy")
    CasefoldUser.new(name: "sammy").valid?.should be_false
    CasefoldUser.new(name: "Sammy").valid?.should be_false
    CasefoldUser.new(name: "Different").valid?.should be_true
  end
end
