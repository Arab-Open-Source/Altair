# JSON API endpoint

A JSON-only route with CORS enabled and no views or asset pipeline. The file
has no `shard.yml`; it compiles against the generated project's dependencies.

```bash
# from the generated project root
crystal run examples/altair/json_api/app.cr
curl http://localhost:3000/api/status
```

For a full API project, create it with `altair new my_api --api`.
