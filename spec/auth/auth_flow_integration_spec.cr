# Altair — the batteries-included web framework for Crystal.
#
# End-to-end authentication over real HTTP: register, log in, reach a
# protected page through the session cookie, fail wrong credentials, and
# log out — mirroring exactly what `altair g auth` generates.
require "./../spec_helper"
require "./../record/model_fixtures_spec"

class AuthFlowUser < Altair::Record::Model
  table :auth_users

  validates_presence_of :email
  validates_uniqueness_of :email
  password_auth min_length: 8
end

class AuthSessionsController < Altair::Controller
  def new_action : Nil
    render html: "<h1>Sign in</h1><form action=\"/login\" method=\"post\">" \
                 "<input type=\"email\" name=\"email\"><input type=\"password\" name=\"password\">" \
                 "<button>Sign in</button></form>"
  end

  def create : Nil
    email = params["email"]?.to_s.strip.downcase
    password = params["password"]?.to_s
    if (user = find_user(email)) && user.authenticate_password(password)
      sign_in(user.id.not_nil!.to_s)
      redirect_to "/me"
    else
      render text: "Invalid email or password", status: ::HTTP::Status::UNPROCESSABLE_ENTITY
    end
  end

  def destroy : Nil
    sign_out
    redirect_to "/login"
  end

  private def find_user(email : String) : AuthFlowUser?
    AuthFlowUser.find_by_email(email)
  end
end

class AuthRegistrationsController < Altair::Controller
  def new_action : Nil
    render html: "<h1>Register</h1><form action=\"/register\" method=\"post\">" \
                 "<input type=\"email\" name=\"email\"><input type=\"password\" name=\"password\">" \
                 "<input type=\"password\" name=\"password_confirmation\"><button>Register</button></form>"
  end

  def create : Nil
    user = AuthFlowUser.new(email: params["email"]?.to_s.strip.downcase)
    user.password = params["password"]?
    user.password_confirmation = params["password_confirmation"]?
    if user.save
      sign_in(user.id.not_nil!.to_s)
      redirect_to "/me"
    else
      render text: user.errors.full_messages.join(", "), status: ::HTTP::Status::UNPROCESSABLE_ENTITY
    end
  end
end

class AuthProtectedController < Altair::Controller
  before_action :require_login

  def me : Nil
    render text: "user:#{current_user_id}"
  end
end

class AuthFlowApp < Altair::Application
  routes do
    get "/register", to: AuthRegistrationsController.new_action
    post "/register", to: AuthRegistrationsController.create
    get "/login", to: AuthSessionsController.new_action
    post "/login", to: AuthSessionsController.create
    delete "/logout", to: AuthSessionsController.destroy
    get "/me", to: AuthProtectedController.me
  end
end

private def with_app(& : Int32 -> Nil)
  Altair::Test.boot(AuthFlowApp, configure: ->(app : AuthFlowApp) {
    app.config.secret_key_base = "auth-flow-secret"
  }) do |port|
    yield port
  end
end

describe "authentication flow over HTTP" do
  before_each do
    conn = Altair::Record.connection
    conn.exec("DROP TABLE IF EXISTS auth_users")
    conn.exec(
      "CREATE TABLE auth_users (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT, " \
      "password_digest TEXT)"
    )
  end

  it "registers a new account and lands signed-in on the protected page" do
    with_app do |port|
      client = Altair::Test::Client.new(port, follow_redirects: true)
      response = client.post("/register",
        form: "email=Ada%40example.com&password=long-enough-pass&password_confirmation=long-enough-pass")
      response.status_code.should eq(200)
      response.body.should eq("user:1")

      row = Altair::Record.connection.query_one(
        "SELECT password_digest FROM auth_users WHERE id = 1"
      ) { |rs| rs.read(String?) }
      row.not_nil!.should start_with(Altair::Auth::PasswordHasher::FORMAT)
    end
  end

  it "rejects a registration whose confirmation mismatches" do
    with_app do |port|
      client = Altair::Test::Client.new(port)
      response = client.post("/register",
        form: "email=a@b.c&password=long-enough-pass&password_confirmation=different")
      response.status_code.should eq(422)
      response.body.should contain("doesn't match password")
    end
  end

  it "rejects duplicate emails" do
    with_app do |port|
      client = Altair::Test::Client.new(port)
      form = "email=same@example.com&password=long-enough-pass&password_confirmation=long-enough-pass"
      client.post("/register", form: form).status_code.should eq(302)

      second = client.post("/register", form: "email=same@example.com&password=another-long-pass&password_confirmation=another-long-pass")
      second.status_code.should eq(422)
      second.body.should contain("has already been taken")
    end
  end

  it "logs in with correct credentials and reaches /me" do
    with_app do |port|
      AuthFlowUser.create(email: "ada@example.com").tap do |user|
        user.password = "long-enough-pass"
        user.save
      end

      client = Altair::Test::Client.new(port, follow_redirects: true)
      response = client.post("/login", form: "email=ada%40example.com&password=long-enough-pass")
      response.status_code.should eq(200)
      response.body.should eq("user:#{AuthFlowUser.find_by_email!("ada@example.com").id}")
    end
  end

  it "answers 422 on wrong credentials" do
    with_app do |port|
      client = Altair::Test::Client.new(port)
      response = client.post("/login", form: "email=nobody@example.com&password=whatever-pass")
      response.status_code.should eq(422)
      response.body.should contain("Invalid email or password")
    end
  end

  it "redirects guests away from protected pages" do
    with_app do |port|
      client = Altair::Test::Client.new(port)
      response = client.get("/me")
      response.status_code.should eq(302)
      response.headers["Location"].should eq("/login")
    end
  end

  it "logs out and revokes access to the protected page" do
    with_app do |port|
      client = Altair::Test::Client.new(port)
      client.post("/register",
        form: "email=out@example.com&password=long-enough-pass&password_confirmation=long-enough-pass")
      client.get("/me").body.should contain("user:")

      client.delete("/logout")
      guest = client.get("/me")
      guest.status_code.should eq(302)
    end
  end
end
