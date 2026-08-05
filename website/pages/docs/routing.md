# Routing

The router parses URL segments directly — no regex over the whole path — and
every route is declared inside the application's `routes do` block, which
runs at compile time. A typo in a route is a compile error, and the generated
path helpers are real, type-checked methods.

```crystal
class Blog < Altair::Application
  config.port = 3000

  routes do
    root to: PagesController.index
    get "/hello/:name", to: PagesController.hello, named: :greeting
    resources :posts
  end
end
```

## Verb macros

`get`, `post`, `put`, `patch` and `delete` each register one route. Two
actions reference styles work everywhere:

- **Typed references** — `to: PostsController.index`. Renaming the action
  breaks the build, so a stale route can never be a silent 404.
- **Strings** — `to: "posts#index"`. The controller class and action are
  derived from the string.

`root to: PagesController.index` maps `/` to an action, and any of the macros
can also take a handler block `|request, response|` for one-off endpoints.

## Parameters

Segments starting with `:` capture one path part into `params`:

```crystal
get "/posts/:id", to: PostsController.show, named: :post
```

`/posts/42` sets `params["id"]` to `"42"`. Lookups follow the conventional
precedence — route parameters first, then the query string, then the body:

```crystal
params["title"]?        # String? — missing key is nil, never a crash
params["id"]            # String  — raises KeyError when absent
params.fetch("id", Int32)   # Integer, or a 422 for a malformed value
params.fetch?("id", Int32)  # Integer?, or nil for a malformed value
params.permit("title", "body")
params.require("post").permit("title", "body")
```

## Named routes and helpers

`named:` gives a route a generated path helper, callable in controllers and
views as a real method:

```crystal
get "/hello/:name", to: PagesController.hello, named: :greeting
# -> greeting_path("world") == "/hello/world"
```

`resources :posts` generates the conventional set:

| Helper | Path | Method |
|--------|------|--------|
| `posts_path` | `/posts` | `GET` / `POST` |
| `post_path(5)` | `/posts/5` | `GET` / `PATCH` / `PUT` / `DELETE` |
| `new_post_path` | `/posts/new` | `GET` |
| `edit_post_path(5)` | `/posts/5/edit` | `GET` |

## Format suffix

A trailing `.ext` is stripped before matching and exposed as
`params["format"]`, so `/posts/5.json` matches `GET /posts/:id` with
`id = 5` and `format = "json"`. The exact path is tried first, so a literal
dotted route like `/sitemap.xml` still matches unchanged.

## Resources, members and collections

`member` routes operate on one record, `collection` routes on the whole set:

```crystal
resources :posts do
  member { get :preview }            # GET  /posts/:id/preview
  collection { get :export }         # GET  /posts/export
  resources :comments, only: :create # POST /posts/:post_id/comments
end
```

The generated helpers follow the nesting: `preview_post_path(5)`,
`export_posts_path`, `post_comments_path(5)`. `only:` and `except:` restrict
the generated routes, and `constraints:` limits matching to the given
parameter regexes:

```crystal
resources :posts, constraints: { id: /\d+/ } do
  resources :comments
end
```

## Singular resources

`resource :profile` declares the singular form — the URL has no id, and the
helpers are `profile_path`, `new_profile_path`, `edit_profile_path`:

```crystal
resource :profile do
  member { get :history }   # GET /profile/history
end
```

## Glob segments

A `*segment` captures the rest of the path, joined with slashes. It must be
the last segment:

```crystal
get "/docs/*path", to: PagesController.docs, named: :docs
```

`/docs/routing/overview` sets `params["path"]` to `"routing/overview"`.

## Redirects

`redirect "/old", to: "/new"` registers the route under every method, so the
browser follows it for `GET` and `POST` alike:

```crystal
redirect "/legacy", to: "/posts"
```

## Not found and method not allowed

- A path no route matches answers **404**. In development the error page
  suggests routes whose patterns resemble what you typed.
- A path that matches but with the wrong verb answers **405** with an `Allow`
  header listing the accepted methods. `redirect` routes are registered
  under `ANY` and never appear in that list.
- `HEAD` requests match `GET` routes; the response body is dropped.

With no routes at all, `/` renders the welcome page.
