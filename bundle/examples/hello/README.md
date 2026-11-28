# Hello route

The smallest Altair application: one route, a JSON health endpoint and no
database. The file has no `shard.yml`; it compiles against the generated
project's dependencies.

```bash
# from the generated project root
crystal run examples/altair/hello/app.cr
curl http://localhost:3000/hello
curl http://localhost:3000/health
```

Use `PORT=4000` to change the listener. Stop the server with Ctrl-C.
