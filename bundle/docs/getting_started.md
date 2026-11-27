# Getting started

Altair requires Crystal 1.22.3 or newer. Install the CLI with the release
installer, then create a project:

```bash
altair new blog -d sqlite
cd blog
shards install
bin/altair db:migrate
bin/altair server
```

`altair new app -d postgresql` pins the organization-owned PostgreSQL driver
forks. `altair new app --api` omits views, static assets and asset references.
`--framework-path DIR` (or `ALTAIR_PATH`) uses a local framework checkout for
offline work.

Inside a project, generated path helpers are compile-checked methods such as
`post_path(5)`. Every value passed to the query layer is a bind parameter;
never interpolate values into SQL strings.

See `altair docs deployment` for the container path and `altair examples`
for the curated starter programs.
