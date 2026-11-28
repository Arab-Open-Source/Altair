# Testing

`Altair::Test.boot` starts the application on an ephemeral port with an
optional `configure:` hook and yields the port to the block. `Test::Client`
keeps a cookie jar and follows redirects.

```crystal
Altair::Test.boot(Blog, configure: ->(app : Blog) { app.config.secret_key_base = "test" }) do |port|
  client = Altair::Test::Client.new(port, follow_redirects: true)
  client.post("/login", form: "email=a@b.com&password=secret")
  client.get("/me").body.should contain("a@b.com")
end

Altair::Test.transactional { Post.create(title: "ephemeral") }
```

`Altair::Test.migrate!` prepares the test database. `transactional` wraps the
block in a transaction that rolls back, using savepoints when nested.
Reset global hooks and the shared application instance between examples.
