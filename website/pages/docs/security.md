# Security

The default middleware stack ships six layers, four of them security
layers, safe-by-default and each overridable through `config`. Combined
with [CSRF protection](/docs/sessions.html) and the signed session
cookie, a generated project is hardened without writing a line of it
yourself.

## Security headers

`Altair::Middleware::SecurityHeaders` stamps conservative headers on every
response:

- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: SAMEORIGIN`
- `Referrer-Policy: strict-origin-when-cross-origin`

Each header is only written when the application did not set it itself.
The set is driven by `config.security_headers`, so it is a plain hash you
can extend or replace:

```crystal
config.security_headers["X-Content-Type-Options"] = "nosniff"
config.security_headers["Content-Security-Policy"] = "default-src 'self'"
```

Set the hash to `{} of String => String` to disable the layer entirely.

## Request ids

`Altair::Middleware::RequestId` gives every request an identifier you can
carry end-to-end:

- An inbound `X-Request-Id` header is **honored** (echoed back, not replaced).
- Otherwise a fresh UUID is generated.
- The value is exposed as `request.request_id`, echoed back on the response
  header, and appended to the request log line — so a log entry and the
  response header correlate across distributed traces.

The header name is configurable via `config.request_id_header`:

```crystal
config.request_id_header = "X-Correlation-Id"
```

## CORS

`Altair::Middleware::Cors` is a **pass-through until you opt in** by naming
the origins you trust. Fill `config.cors.origins` and it stamps
`Access-Control-Allow-*` on permitted requests and answers preflight
`OPTIONS` directly (methods, headers, credentials, max age):

```crystal
config.cors.origins = ["https://app.example.com"]
config.cors.credentials = true        # admit cookies cross-origin
config.cors.max_age = 3600            # seconds, preflight caching
```

Or allow any origin:

```crystal
config.cors.origins = ["*"]
```

Notes:

- Origins are exact-matched against the `Origin` header; `"*"` grants any.
- With `credentials = true` and a `"*"` entry, the **exact** origin is
  echoed instead of the wildcard — browsers refuse wildcard-plus-credentials.
- `config.cors.methods` and `config.cors.headers` tailor the preflight
  answer; requested headers are honored when the client names extra ones.
- Combine CORS with the framework's signed session cookie, which carries
  `SameSite=Lax` by default, to keep cross-origin sessions honest.

## Rate limiting

`Altair::Middleware::RateLimit` is a **pass-through until you configure it**.
Declare rules on `config.rate_limit` — every value travels as a bind
parameter internally, and the middleware enforces the most restrictive
matching rule per request:

```crystal
config.rate_limit.configure do |rl|
  rl.store :memory          # or :redis for multi-instance deployments
  rl.limit 100, per: 1.minute
  rl.limit 5, per: 1.minute, only: ["/login"]
end
```

* `store :memory` — per-process, evicts dead keys lazily.
* `store :redis` — shared via `Altair::Redis` (set `redis_url` or `ALTAIR_REDIS_URL`).
* `only:` scopes a rule to path prefixes (`"/login"` matches `/login` and
  `/login/*`); unmatched paths are free.
* `trusted_headers = true` makes `X-Forwarded-For` the client key — only
  enable behind a proxy you control.

Allowed responses carry `X-RateLimit-Limit` / `-Remaining` / `-Reset`;
denied ones answer `429 Too Many Requests` with `Retry-After`.

See `examples/rate_limit_demo` for a runnable demo.

## The full stack

The default `config.middleware` runs, in order:

| Layer | Job |
|-------|-----|
| `Logger` | Request logging with the request id appended |
| `RequestId` | Assign and echo a request identifier |
| `RateLimit` | Sliding-window rate limiting (pass-through by default) |
| `SecurityHeaders` | Stamp safe-by-default response headers |
| `Cors` | Opt-in cross-origin support (pass-through by default) |
| `Static` | Serve `public/` files as-is |

See [Configuration](/docs/configuration.html) for building your own stack.
