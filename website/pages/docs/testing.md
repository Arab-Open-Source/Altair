# Testing

Altair ships testing helpers so application specs read as intent instead of socket plumbing. The helpers live in `Altair::Test` and mirror the patterns the framework's own suite uses.

## Booting an application

`Altair::Test.boot` binds the application on an ephemeral port, waits until it accepts, yields the port, and restores the shared application instance afterwards:

```crystal
require "spec_helper"

class MyApp < Altair::Application
  routes do
    get "/ping", to: PingController.ping
  end
end

class PingController < Altair::Controller
  def ping : Nil
    render text: "pong"
  end
end

describe "ping" do
  it "answers pong" do
    Altair::Test.boot(MyApp) do |port|
      response = Altair::Test.get(port, "/ping")
      response.status_code.should eq(200)
      response.body.should eq("pong")
    end
  end
end
```

The block form guarantees cleanup — the server closes and `Altair.application_instance` is restored even when the example raises.

## Request helpers

Small wrappers over `HTTP::Client` with the base URL already filled in:

```crystal
Altair::Test.get(port, "/posts")
Altair::Test.post(port, "/posts", form: "title=Hello")
Altair::Test.post_json(port, "/api/token", body: %({"email":"a@b.com"}))
Altair::Test.put(port, "/posts/1", form: "title=Edited")
Altair::Test.patch(port, "/posts/1", form: "title=Patched")
Altair::Test.delete(port, "/posts/1")
```

All helpers accept an optional `headers` argument (`HTTP::Headers`) and return `HTTP::Client::Response`.

## The cookie-jar client

`Altair::Test::Client` keeps the server's cookies between requests, so a sign-in carries into every later request without manual header plumbing, and follows redirects the way a browser does when asked:

```crystal
client = Altair::Test::Client.new(port)                     # or: follow_redirects: true
client.post("/login", form: "email=a@b.com&password=secret")
client.get("/me").body.should contain("a@b.com")            # session carried

destroyed = client.get("/logout")                           # expired cookies leave the jar
client.get("/me").status_code.should eq(302)
```

Redirects follow only when `follow_redirects: true`; 301/302/303 downgrade to GET (so POST-then-redirect lands on the page), 307/308 keep the method, and the jar rides along every hop.

## Configuring the booted app

The `configure:` proc runs on the fresh instance before the server is built — where per-spec settings belong:

```crystal
Altair::Test.boot(SessionApp, configure: ->(app : SessionApp) {
  app.config.secret_key_base = "test-secret"
}) do |port|
  # sessions work here
end
```

## Database helpers

`Altair::Test.migrate!` applies pending migrations against the application's configured database — the same engine `db:migrate` runs:

```crystal
Altair::Test.migrate!(MyApp)
```

`Altair::Test.transactional { }` wraps a block in a transaction that is always rolled back, so every example starts from the same data; nested calls join the outer transaction through savepoints:

```crystal
Altair::Test.transactional do
  Post.create(title: "only this example sees me")
end
```

Background jobs have their own test seam: set `Altair::Jobs::Queue.test_mode = true` and enqueues collect in memory (`Queue.enqueued`, `Queue.clear_enqueued!`) instead of hitting the table; drain them synchronously with a `Worker#execute` loop over sorted calls.

## Isolation

Each `boot` saves the current `Altair.application_instance`, sets it to `nil` so the application builds a fresh instance, and restores the original in an `ensure` block. Nested boots are not supported — finish one before starting the next.

For specs that need to reset state between examples without a server, use the same pattern the framework uses internally:

```crystal
before_each do
  # clear database, reset singletons, etc.
end
```

## Tips

- Prefer `Altair::Test.boot` over hand-rolled `HTTP::Server.new` + `spawn` + polling — it handles the readiness probe and the `ensure` cleanup.
- Keep specs fast by booting once per `describe` when the application does not mutate global state; otherwise boot per `it`.
- Pair with `Altair::Record` fixtures: create rows via `Model.create` inside the `boot` block, then exercise the controller over real HTTP.
