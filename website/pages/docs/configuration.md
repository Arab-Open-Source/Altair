# Configuration

Altair is configured by code *and* by files. Sensitive or environment-specific
values live in `.env` and `config/database.yml`; the rest is typed properties
on `config`, each with a sane default and most tunable per environment.

## The layered picture

At boot the framework merges settings from low to high precedence:

1. **Defaults** — every `config.*` property has a sane default.
2. **`.env`** — `.env` sets dev/test defaults; **`.env.<environment>`**
   (e.g. `.env.production`) overrides it.
3. **Real environment variables** — a variable already in the process
   environment always wins over any `.env` file, so

   ```sh
   export SECRET_KEY_BASE="$(openssl rand -hex 64)" altair server
   ```

   beats a checked-in fallback.
4. **`config/database.yml`** — the active environment's section is merged
   into the database settings.

`altair new` generates both `.env` and `config/database.yml`, so a fresh
project is file-driven from day one.

## `.env`

`KEY=VALUE` pairs loaded into the process environment. Handles `export`,
quoted and unquoted values and `#` comments:

```ini
# .env — dev/test defaults
SECRET_KEY_BASE=change-me-dev-secret
DATABASE_URL=sqlite3://./db/blog.db
```

```ini
# .env.production — overrides for production
SECRET_KEY_BASE=8f2a…  # keep out of the repository
```

## `config/database.yml`

Per-environment database settings. Only the section matching the active
environment is applied:

```yaml
production:
  url: postgresql://user:pass@localhost/blog_production
  pool: 25
  initial_pool: 4
  max_idle_pool: 4
  checkout_timeout: 5.0
  query_timeout: 5.0

test:
  url: sqlite3://./db/test.db
```

Recognised keys are the `url` and the `db_*` pool settings (`pool`,
`initial_pool`, `max_idle_pool`, `checkout_timeout`, `query_timeout`).

## The `config` object

Everything is a typed property on the application's `config`, so a typo is
a compile error:

```crystal
class Blog < Altair::Application
  config.name = "Blog"
  config.port = 3000
  config.secret_key_base = ENV["SECRET_KEY_BASE"] || "dev-only-secret"

  config.db_url = "sqlite3://./db/blog.db"
  config.db_max_pool_size = 10

  config.login_path = "/login"
  config.max_body_size = 10.megabytes
end
```

### Per-environment settings

Environments carry their own bags, addressed as
`config.environments.<env>.<setting>`. Development and test default to debug
on; production defaults to eager loading on:

```crystal
config.environments.production.eager_load = true
config.environments.production.max_body_size = 100.megabytes
```

or programmatically with `config.environment(name)`.

### The middleware stack

`config.middleware` holds the stack run on every request before routing,
each entry a factory proc. The default stack is logging, request-id
assignment, the default security headers, CORS and static files:

```crystal
config.middleware = [
  ->(app : Altair::Application) : Altair::Middleware { Altair::Middleware::Logger.new(app) },
  ->(app : Altair::Application) : Altair::Middleware { Altair::Middleware::Static.new(app) },
]
```

Assign an empty array to disable them all, or build your own stack. CORS is
a pass-through until `config.cors.origins` is filled (see
[Security](/docs/security.html)).

### Development console

The development server prints a boxed banner once at boot and one
aligned line per request. Colors are auto-detected from `STDOUT.tty?`
and `NO_COLOR`/`TERM`, or forced via `config.logger_colors`.

```crystal
class Blog < Altair::Application
  config.logger_colors = true              # nil = auto, true/false = forced
  config.logger_timestamps = true          # HH:MM:SS prefix
  config.logger_request_counter = true     # #0001 prefix
  config.logger_compact = false            # compact single-line without alignment
  config.slow_request_threshold = 20.milliseconds # highlight slower requests
end
```

Slow requests are highlighted and suffixed with `[SLOW]`; status codes
and HTTP methods are colored by family (2xx green, 3xx blue, 4xx yellow,
5xx red; GET green, POST blue, etc.).

## Reference

A selection of the settings available:

| Property | Default | Meaning |
|----------|---------|---------|
| `port` / `host` | `3000` / `0.0.0.0` | Where the server listens |
| `parallel_execution` | `true` | Resize the execution context to available workers on boot |
| `secret_key_base` | env `SECRET_KEY_BASE` | Signs session cookies, CSRF tokens and JWTs |
| `session_cookie_name` | `_altair_session` | The session cookie's name |
| `session_expiry` | `nil` | Cookie lifetime; `nil` = browser session |
| `session_cookie_secure` | on in production | The cookie's `Secure` attribute |
| `login_path` | `/login` | Where `require_login` redirects |
| `max_body_size` | `2 MB` | Request body limit (raise it for uploads) |
| `db_url` | `nil` | The database connection URL |
| `db_*_pool_size` | warm defaults | Connection pool tuning |
| `router_cache_size` | `1024` | Memoized route lookups (`0` disables) |
| `security_headers` | `nosniff` / `SAMEORIGIN` / referrer policy | Headers stamped by `SecurityHeaders` |
| `request_id_header` | `X-Request-Id` | Header carrying the request id |
| `cors` | origin pass-through | Cross-origin settings (see Security) |
| `logger_colors` | `nil` (auto) | Console colors (`nil` = auto, `true`/`false` = forced) |
| `logger_compact` | `false` | Compact request lines without alignment |
| `logger_timestamps` | `true` | `HH:MM:SS` prefix on request lines |
| `logger_request_counter` | `false` | Sequential `#0001` prefix |
| `slow_request_threshold` | `20ms` | Highlight requests slower than this |