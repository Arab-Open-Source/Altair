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
