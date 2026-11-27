# Cache

Uses the in-memory cache store through `Altair.cache.fetch` with a TTL. No
database, views or external service are required. The file has no
`shard.yml`; it compiles against the generated project's dependencies.

```bash
# from the generated project root
crystal run examples/altair/cache/app.cr
curl http://localhost:3000/cached
```

Set `config.cache` to a Redis-backed store when multiple processes must share
values.
