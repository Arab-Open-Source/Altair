# Altair — the batteries-included web framework for Crystal.
#
# Specs for the `password_auth` model macro: staged plain passwords never
# persist, hashing lands in the digest column through before_save, length
# and confirmation validate as ordinary record errors, and
# `authenticate_password` gates on the stored digest.
require "./../spec_helper"
require "./../record/model_fixtures_spec"

class AuthUser < Altair::Record::Model
  table :auth_users

  validates_presence_of :email
  password_auth min_length: 8
end

describe "password_auth" do
  before_each do
    conn = Altair::Record.connection
    conn.exec("DROP TABLE IF EXISTS auth_users")
    conn.exec(
      "CREATE TABLE auth_users (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT, " \
      "password_digest TEXT)"
    )
  end

  it "hashes a staged password into the digest column on save" do
    user = AuthUser.new(email: "a@b.c")
    user.password = "correct horse"
    user.password_digest.should be_nil

    user.save.should be_true
    digest = user.password_digest.not_nil!
    digest.should start_with(Altair::Auth::PasswordHasher::FORMAT)

    user.password.should be_nil
    Altair::Auth::PasswordHasher.verify("correct horse", digest).should be_true
  end

  it "rejects a too-short password with an ordinary record error" do
    user = AuthUser.new(email: "a@b.c")
    user.password = "short"
    user.save.should be_false
    user.errors[:password].should contain "is too short (minimum is 8 characters)"
    user.password_digest.should be_nil
  end

  it "requires a password on create when no digest exists" do
    user = AuthUser.new(email: "a@b.c")
    user.save.should be_false
    user.errors[:password].should contain "can't be blank"
  end

  it "allows saving without a password once a digest exists" do
    user = AuthUser.new(email: "a@b.c")
    user.password = "long enough"
    user.save.should be_true

    user.email = "updated@b.c"
    user.save.should be_true
    AuthUser.find!(user.id.not_nil!).email.should eq("updated@b.c")
  end

  it "validates the confirmation against the staged password" do
    user = AuthUser.new(email: "a@b.c")
    user.password = "long enough"
    user.password_confirmation = "longer but wrong"
    user.save.should be_false
    user.errors[:password_confirmation].should contain "doesn't match password"

    user.password_confirmation = "long enough"
    user.save.should be_true
  end

  it "skips confirmation validation when no confirmation was given" do
    user = AuthUser.new(email: "a@b.c")
    user.password = "no confirmation here"
    user.save.should be_true
  end

  it "rehashes when the password changes" do
    user = AuthUser.new(email: "a@b.c")
    user.password = "first password"
    user.save

    old_digest = user.password_digest.not_nil!
    user.password = "second password"
    user.save.should be_true
    new_digest = user.password_digest.not_nil!
    new_digest.should_not eq(old_digest)
    Altair::Auth::PasswordHasher.verify("second password", new_digest).should be_true
    Altair::Auth::PasswordHasher.verify("first password", new_digest).should be_false
  end

  it "authenticates through authenticate_password" do
    user = AuthUser.new(email: "a@b.c")
    user.password = "let me in"
    user.save

    reloaded = AuthUser.find!(user.id.not_nil!)
    reloaded.authenticate_password("let me in").should be_true
    reloaded.authenticate_password("wrong").should be_false
    reloaded.authenticate_password("").should be_false
  end

  it "reports stale digests only at older iteration counts" do
    user = AuthUser.new(email: "a@b.c")
    user.password = "current iterations"
    user.save
    user.password_digest_stale?.should be_false
  end

  it "never stores the plain password anywhere on the persisted row" do
    user = AuthUser.new(email: "a@b.c")
    user.password = "invisible secret"
    user.save

    row = Altair::Record.connection.query_one(
      "SELECT * FROM auth_users WHERE id = #{Altair::Record.connection.adapter.placeholder(0)}",
      user.id.not_nil!
    ) { |rs|
      columns = rs.column_names
      columns.each { rs.read }
      columns.join(",")
    }
    row.should_not contain("invisible secret")
  end
end
