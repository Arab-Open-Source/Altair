# Hello World

A working [Altair](https://github.com/hmh/altair) application. This example
shows the framework's routing layer in action: a Rails-style route DSL, path
parameters, named helpers, a full RESTful resource and the 404/405 protocol —
all verified over real HTTP.

## Requirements

- [Crystal](https://crystal-lang.org) `>= 1.21.0`

No other dependencies. The example uses Altair directly from the repository.

## Quick start

```bash
# from the repository root
crystal run examples/hello_world/src/hello_world.cr
```

The server boots on `http://localhost:3000`. Stop it with `Ctrl+C`.

> Tip: to build a single native binary instead of running from source:
>
> ```bash
> cd examples/hello_world
> crystal build src/hello_world.cr
> ./hello_world
> ```

## Routes

The routes are declared in `src/config/application.cr`:

```crystal
class HelloWorld < Altair::Application
  config.name = "Hello World"
  config.port = 3000

  routes do
    root to: "pages#index"
    get "/hello/:name", to: "pages#hello", named: :greeting
    resources :posts
  end
end
```

| Method | Path | Controller action | Description |
|--------|------|-------------------|-------------|
| `GET` | `/` | `pages#index` | Welcome page |
| `GET` | `/hello/:name` | `pages#hello` | Personalised greeting |
| `GET` | `/posts` | `posts#index` | List all posts |
| `GET` | `/posts/new` | `posts#new` | New-post form |
| `POST` | `/posts` | `posts#create` | Create a post |
| `GET` | `/posts/:id` | `posts#show` | Show one post |
| `GET` | `/posts/:id/edit` | `posts#edit` | Edit form |
| `PUT` | `/posts/:id` | `posts#update` | Update a post |
| `PATCH` | `/posts/:id` | `posts#update` | Update a post (partial) |
| `DELETE` | `/posts/:id` | `posts#destroy` | Delete a post |

The `resources :posts` line alone expands to the seven RESTful routes above
and generates the matching path helpers (`posts_path`, `new_post_path`,
`post_path(5)`, `edit_post_path(5)`).

## Trying it out

### With curl

```bash
# Welcome page
curl http://localhost:3000/

# Greeting with a path parameter
curl http://localhost:3000/hello/altair

# Create two posts
curl -X POST -d "title=First post" http://localhost:3000/posts
curl -X POST -d "title=Second post" http://localhost:3000/posts

# List posts
curl http://localhost:3000/posts

# Show and edit one post
curl http://localhost:3000/posts/1
curl http://localhost:3000/posts/1/edit

# Update a post (PUT)
curl -X PUT -d "title=Renamed post" http://localhost:3000/posts/1

# Wrong method on an existing path → 405 with an Allow header
curl -i -X POST http://localhost:3000/posts/1

# Unknown path → 404
curl http://localhost:3000/nope

# Delete a post
curl -X DELETE http://localhost:3000/posts/2
```

### With Postman

Create a new request for each row below. For the form-bearing requests use
the **Body** tab and select **x-www-form-urlencoded**.

| Method | URL | Body | Expected |
|--------|-----|------|----------|
| `GET` | `http://localhost:3000/` | — | `200` welcome page |
| `GET` | `http://localhost:3000/hello/altair` | — | `200` "Hello, altair!" |
| `POST` | `http://localhost:3000/posts` | `title=My first post` | `302` → `/posts` |
| `GET` | `http://localhost:3000/posts` | — | `200` list |
| `GET` | `http://localhost:3000/posts/1` | — | `200` post details |
| `GET` | `http://localhost:3000/posts/new` | — | `200` new-post form |
| `GET` | `http://localhost:3000/posts/1/edit` | — | `200` edit form |
| `PUT` | `http://localhost:3000/posts/1` | `title=Renamed` | `302` → post page |
| `POST` | `http://localhost:3000/posts/1` | — | `405` + `Allow: GET, PUT, PATCH, DELETE` |
| `DELETE` | `http://localhost:3000/posts/2` | — | `302` → `/posts` |
| `GET` | `http://localhost:3000/nope` | — | `404` |

> **The `_method` override.** Forms cannot send `PUT`, `PATCH` or `DELETE`,
> so Altair honours the conventional `_method` form field. Simulate a PUT
> with a POST that includes `_method=PUT`:
>
> ```
> POST http://localhost:3000/posts/1
> Body (x-www-form-urlencoded): title=Updated&_method=PUT
> ```

## Project structure

```
src/
├── hello_world.cr               # entry point
├── config/
│   └── application.cr           # configuration + routes
└── app/
    └── controllers/
        ├── pages_controller.cr  # static pages
        └── posts_controller.cr  # in-memory RESTful resource
```

## How it works

- **Routes are compile-time.** Every call inside `routes do` is a Crystal
  macro, so a typo in `to: "posts#shw"` fails at compile time, not at
  request time, and path helpers are real methods checked by the compiler.
- **Controllers are plain classes.** Each action is a class method receiving
  the framework's `request` and `response` wrappers. A full `BaseController`
  with rendering helpers arrives in a later phase of the framework.
- **Posts live in memory.** There is no database yet — the post store is a
  class-level array, so posts reset on restart.
- **404 and 405 come from the router.** Unknown paths answer `404`; known
  paths with the wrong method answer `405` with an `Allow` header.

## License

This example is part of [Altair](LICENSE), which is released under the MIT
License.
