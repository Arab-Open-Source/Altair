# Rate Limit Demo

A working [Altair](https://github.com/Arab-Open-Source/Altair) application that
demonstrates the sliding-window rate limiter with both memory and Redis
backends, per-path rules, and trusted proxy handling — all verified over
real HTTP.

## Requirements

- [Crystal](https://crystal-lang.org) `>= 1.21.0`
- Optional: [Redis](https://redis.io) for the shared store (`ALTAIR_REDIS_URL`)

No other dependencies. The example uses Altair directly from the repository.

## Run

```bash
# from inside examples/rate_limit_demo/
crystal run src/rate_limit_demo.cr
```

The server boots on `http://localhost:3000`.

With the default `:memory` store (per-process):

```bash
curl -i http://localhost:3000/
curl -i http://localhost:3000/login
curl -i http://localhost:3000/api/data
curl -i http://localhost:3000/free
```

With Redis (shared across processes):

```bash
ALTAIR_REDIS_URL=redis://localhost:6379 crystal run src/rate_limit_demo.cr
```

## Rules

Declared in `src/config/application.cr`:

```crystal
config.rate_limit.configure do |rl|
  rl.store :memory          # or :redis
  rl.limit 100, per: 1.minute
  rl.limit 5, per: 1.minute, only: ["/login"]
  rl.limit 30, per: 1.minute, only: ["/api/data"]
end
```

* Global: 100/minute for every path.
* `/login`: 5/minute (most restrictive matching rule governs).
* `/api/data`: 30/minute.
* `/free`: outside every rule, never limited — a pass-through.

Unmatched paths are free; matched paths share the same sliding window per
client IP (or `X-Forwarded-For` when `trusted_headers` is enabled).

## Try it out

```bash
# Headers on allowed responses:
curl -i http://localhost:3000/api/data
# < X-RateLimit-Limit: 30
# < X-RateLimit-Remaining: 29
# < X-RateLimit-Reset: 58

# Hit the login limit (6th request gets 429):
for i in $(seq 1 6); do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/login; done
# 200
# 200
# 200
# 200
# 200
# 429
# < Retry-After: 42
# < X-RateLimit-Remaining: 0

# Free path is never limited:
for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/free; done
# 200 x10

# Per-client buckets (spoofed via X-Forwarded-For when trusted):
curl -H "X-Forwarded-For: 203.0.113.10" -i http://localhost:3000/login
```

## How it works

* **Middleware position:** `RateLimit` sits after `RequestId` and before
  `SecurityHeaders`/`Cors`/`Static`, so it runs before routing and stamps
  `X-RateLimit-*` on every governed response. With no rules it is a
  pass-through — the framework pays nothing until configured.
* **Client key:** `request.remote_address` by default (IP without the
  ephemeral port). With `trusted_headers = true`, the first value of
  `X-Forwarded-For` is used — never enable this unless a proxy you
  control sets the header.
* **Stores:** `MemoryStore` (Mutex-guarded, two windows per key) and
  `RedisStore` (INCR/EXPIRE via `Altair::Redis`) share the same
  `Store#hit` contract and sliding-window math, verified with injected
  clocks (no sleeps).

## Project structure

```
rate_limit_demo/
├── shard.yml
└── src/
    ├── rate_limit_demo.cr          # entry point
    ├── config/
    │   └── application.cr          # rate-limit rules + routes
    └── app/
        └── controllers/
            ├── application_controller.cr
            └── pages_controller.cr # index, login, api_data, free
```
