# Altair Showcase

A full-stack Altair application that exercises every phase in one running
thing: Record models and migrations, sessions / auth / CSRF, multipart
uploads, `.env` + `config/database.yml` configuration, security
middleware, a JSON + JWT API, streaming, and the whole routing DSL.

## Run it

```sh
shards install
bin/altair db:migrate   # create the database
bin/altair server       # http://localhost:4000
```

Then open http://localhost:4000. `PORT` and `SECRET_KEY_BASE` come from
`.env` (loaded by `Altair::Config::DotEnv` at boot); the database URL
comes from `config/database.yml` (applied by `Altair::Config::Database`).

## What it exercises

| Layer | In this example |
|---|---|
| Record | `User` / `Post` / `Comment` with associations, validations, timestamps, `includes` eager loading |
| Migrations | `db/migrations/*.cr`, regenerated `db/schema.cr` |
| Sessions | `sign_in` / `sign_out` / `current_user` / `logged_in?`, signed cookies |
| Flash | one-request `flash["notice"]` / `flash["alert"]` |
| CSRF | `protect_from_forgery` + automatic `_csrf` in `form_for` |
| Auth | `before_action :require_login`, `Altair::Auth::JWT` (HS256) |
| Uploads | `params.upload("image")` → `UploadedFile#save` into `public/uploads/` |
| Config | `.env` (`PORT`, `SECRET_KEY_BASE`), `config/database.yml`, security headers, request-id header |
| Middleware | default stack: Logger, RequestId, SecurityHeaders, Cors, Static |
| Router | `root`, named routes, glob (`/docs/*path`), `redirect`, `resources` + member/collection/nested, singular `resource`, `constraints`, implicit `.json` format |
| Controllers | typed `params.fetch`, `respond_to`, `render html/text/json`, `stream`, `redirect_back`, callbacks, `skip_before_action` |
| Views | layout + `yield`, partials, `form_for`, `link_to`, `button_to`, auto-escaping |

## Curl walkthrough

```sh
# The routing DSL
curl -i localhost:4000/                          # home feed
curl -i localhost:4000/forum                     # 301 redirect to /posts
curl -i localhost:4000/docs/routing              # glob route
curl -i localhost:4000/archive/bananas           # 404 (constraint: 4-digit year)
curl -i localhost:4000/nope                      # 404 with route suggestions (debug)

# Security headers + request id are on every response
curl -i localhost:4000/ | grep -i -E "x-content-type-options|x-frame-options|x-request-id|referrer-policy"

# The feed, as JSON via the implicit format suffix
curl localhost:4000/posts.json

# Live stream (server-sent events)
curl -N localhost:4000/stream

# Sign up
curl -i -c /tmp/showcase.jar \
  -b /tmp/showcase.jar \
  localhost:4000/users/new | grep -o 'name="_csrf" value="[^"]*"' > /tmp/csrf.txt
CSRF=$(grep -o 'value="[^"]*"' /tmp/csrf.txt | cut -d'"' -f2)
curl -i -b /tmp/showcase.jar -c /tmp/showcase.jar \
  -d "name=Ada&email=ada@example.com&password=secret&_csrf=$CSRF" \
  localhost:4000/users

# Without a token the sign-up is rejected (CSRF) — try it with an empty _csrf
curl -i -b /tmp/showcase.jar -d "name=Ada&email=ada@example.com&password=secret" localhost:4000/users

# Create a post with an image upload (multipart) and publish it
curl -i -b /tmp/showcase.jar -c /tmp/showcase.jar \
  localhost:4000/posts/new | grep -o 'name="_csrf" value="[^"]*"' > /tmp/csrf2.txt
CSRF2=$(grep -o 'value="[^"]*"' /tmp/csrf2.txt | cut -d'"' -f2)
curl -i -b /tmp/showcase.jar -c /tmp/showcase.jar \
  -F "title=Hello Altair" -F "body=Multipart uploads work." \
  -F "published=1" -F "image=@public/css/app.css;filename=hello.css" \
  -F "_csrf=$CSRF2" \
  localhost:4000/posts

curl localhost:4000/posts/1                      # the post
curl localhost:4000/posts/1 | grep -o '/uploads/[^"]*'   # uploaded file
curl localhost:4000/css/app.css                  # static files from public/

# Comment (nested resource), then delete it
curl -i -b /tmp/showcase.jar -c /tmp/showcase.jar \
  localhost:4000/posts/1 | grep -o 'name="_csrf" value="[^"]*"' > /tmp/csrf3.txt
CSRF3=$(grep -o 'value="[^"]*"' /tmp/csrf3.txt | cut -d'"' -f2)
curl -i -b /tmp/showcase.jar -c /tmp/showcase.jar \
  -d "body=Nice work&_csrf=$CSRF3" \
  localhost:4000/posts/1/comments

# The stateless JSON API: issue a JWT, then read the profile with it
curl -i -b /tmp/showcase.jar -d "email=ada@example.com&password=secret&_csrf=$CSRF3" \
  localhost:4000/api/token
TOKEN=$(curl -s -b /tmp/showcase.jar -d "email=ada@example.com&password=secret&_csrf=$CSRF3" \
  localhost:4000/api/token | ruby -rjson -e 'print JSON.parse(STDIN.read)["token"]')
curl -i -H "Authorization: Bearer $TOKEN" localhost:4000/api/me
curl -i localhost:4000/api/me                    # 401 without a token

# Sign out
curl -i -b /tmp/showcase.jar -c /tmp/showcase.jar \
  -d "_method=DELETE&_csrf=$CSRF3" localhost:4000/session
```

## Notes

- The `publish` member action toggles `published`; only published posts
  show on the feed, so drafts stay private.
- Passwords are stored in plain text because this is a demo — wire in a
  hashing library before doing anything real.
- The development N+1 detector warns on the console if a page fires more
  than `config.n_plus_one_threshold` identical queries.
