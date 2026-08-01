# Hello World

A working [Altair](https://github.com/Arab-Open-Source/Altair) application. This example
shows the framework's request lifecycle end to end: a complete in-memory
posts resource with the seven RESTful actions, instance controllers that
dispatch per request, generated path helpers used as plain methods, and the
default middleware pipeline (request logging plus static files from
`public/`) — all verified over real HTTP.

## Requirements

- [Crystal](https://crystal-lang.org) `>= 1.21.0`

No other dependencies. The example uses Altair directly from the repository.

## Run

```bash
# from inside examples/hello_world/
crystal run src/hello_world.cr
```

The server boots on `http://localhost:3000`. Open it in a browser and stop
the server with `Ctrl+C`.

## Routes

The routes are declared in `src/config/application.cr`:

| Method | Path | Action | Description |
|--------|------|--------|-------------|
| `GET` | `/` | `pages#index` | Welcome page linking to the posts index |
| `GET` | `/hello/:name` | `pages#hello` | Personalised greeting from the URL parameter |
| `GET` | `/posts` | `posts#index` | List all posts, each with edit and delete links |
| `GET` | `/posts/new` | `posts#new` | New-post form posting to `/posts` |
| `POST` | `/posts` | `posts#create` | Create a post, then redirect to `/posts` |
| `GET` | `/posts/:id` | `posts#show` | Show one post, or `404` if it does not exist |
| `GET` | `/posts/:id/edit` | `posts#edit` | Edit form, or `404` if it does not exist |
| `PUT` | `/posts/:id` | `posts#update` | Update a post, then redirect to it |
| `PATCH` | `/posts/:id` | `posts#update` | Same as `PUT` |
| `DELETE` | `/posts/:id` | `posts#destroy` | Delete a post, then redirect to `/posts` |

The `resources :posts` line alone expands to the seven RESTful routes above
and generates the matching path helpers (`posts_path`, `new_post_path`,
`post_path(5)`, `edit_post_path(5)`).

## Controllers

Controllers are **instance controllers**: for every request the router
instantiates the target controller with the framework's `request` and
`response` wrappers and dispatches one action on it:

```crystal
PostsController.new(request, response).show
```

Actions are plain instance methods, so they can use `params`, call `render`
and `redirect_to`, and access the generated helpers without ceremony. The
shared base class brings those helpers in:

```crystal
abstract class ApplicationController < Altair::Controller
  include HelloWorld::RouteHelpers
end
```

Because `ApplicationController` includes the application's generated route
helpers, actions call `posts_path`, `post_path(5)`, `new_post_path` and
`edit_post_path(5)` bare. A representative action:

```crystal
def create : Nil
  @@posts << Post.new(@@next_id, params["title"])
  @@next_id += 1
  redirect_to posts_path
end

def show : Nil
  if post = find(params["id"].to_i)
    render html: page_html("<h1>#{post.title}</h1>")
  else
    render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
  end
end
```

Nothing touches the response object directly — `render` and `redirect_to`
cover the rendering side, and forms use the conventional `_method` override
for `PUT` and `DELETE` (`input type="hidden" name="_method"`).

## Middleware

The default middleware stack is enabled out of the box:

- **Request logging** — every request is logged to stdout, e.g.
  `INFO - altair: GET /posts -> 200 (0.1ms)`.
- **Static files** — anything under `public/` is served by the static-files
  middleware; the pages link `/css/app.css`, which is served this way.

The stack is a chain built around the router, so middlewares run before and
after every dispatched request. Customize it with
`use Altair::Middleware::Logger` (or your own middleware) in
`config.middleware` inside the application class.

## Try it out

With the server running, walk through the full lifecycle with curl:

```bash
# Welcome page (200, HTML)
curl http://localhost:3000/

# Greeting with a path parameter (200, "Hello, altair!")
curl http://localhost:3000/hello/altair

# Stylesheet served by the static-files middleware (200, text/css)
curl http://localhost:3000/css/app.css

# Empty list for now (200)
curl http://localhost:3000/posts

# New-post form (200)
curl http://localhost:3000/posts/new

# Create a post (302 -> /posts)
curl -X POST http://localhost:3000/posts -d "title=First+post"

# List shows the post (200)
curl http://localhost:3000/posts

# Show post 1 (200)
curl http://localhost:3000/posts/1

# Edit form pre-filled (200)
curl http://localhost:3000/posts/1/edit

# Update via the _method override (302 -> /posts/1)
curl -X POST http://localhost:3000/posts/1 -d "title=Updated&_method=PUT"

# Delete via the _method override (302 -> /posts)
curl -X POST http://localhost:3000/posts/1 -d "_method=DELETE"

# Wrong method on an existing path (405 + "Allow: GET, PUT, PATCH, DELETE")
curl -i -X POST http://localhost:3000/posts/1

# Unknown path (404)
curl http://localhost:3000/nope
```

For a GUI client such as Postman or Insomnia, create a request for each row
above; for the form-bearing requests (`POST`, and the `PUT`/`DELETE` via
`_method`) use the **Body** tab with **x-www-form-urlencoded**.

## Project structure

```
hello_world/
├── public/
│   └── css/
│       └── app.css             # stylesheet served by the static-files middleware
└── src/
    ├── hello_world.cr          # entry point: requires the app, then runs it
    ├── config/
    │   └── application.cr      # configuration, middleware and routes
    └── app/
        └── controllers/
            ├── application_controller.cr  # base class including HelloWorld::RouteHelpers
            ├── pages_controller.cr        # static pages (index, hello)
            └── posts_controller.cr        # in-memory RESTful resource
```

## How it works

- **Routes are compile-time.** Every call inside `routes do` is a macro, so
  a typo in `to: "pages#hom"` fails at compile time rather than at request
  time, and each route generates a dispatch handler and the path helpers as
  real, type-checked methods.
- **Controllers are per-request instances.** The router builds
  `PostsController.new(request, response)` and calls the matched action as
  an instance method, so actions have no boilerplate around them.
- **Middleware chains around the router.** Logging and static files wrap
  the router in the default stack; anything more is added via
  `config.middleware`.
- **404 and 405 come from the router.** Unknown paths answer `404`; known
  paths with the wrong method answer `405` with an `Allow` header. A welcome
  page is served only when the route set is empty.
- **Posts live in memory.** There is no database yet — the post store is a
  class-level array, so posts reset on restart.

## License

This example is part of [Altair](LICENSE), which is released under the MIT
License.
