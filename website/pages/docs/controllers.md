# Controllers

Controllers turn a matched route into a response. Each action is an instance
method on a class that subclasses `Altair::Controller`, called once per
request with the request's `params`. Routes reference actions with typed
references (`to: PostsController.index`), so a wrong action name is a compile
error, not a runtime 500.

```crystal
class PostsController < ApplicationController
  def index : Nil
    posts = Post.all.to_a
    render :index, locals: {posts: posts}
  end

  def show : Nil
    if post = Post.find(params.fetch("id", Int32))
      render :show, locals: {post: post}
    else
      render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
    end
  end
end
```

## Parameters

`params` merges the route parameters, the query string and the form body,
with route values taking precedence. Fetch with a type to keep actions
compile-time safe — a malformed value becomes a 422, never a 500:

```crystal
params["title"]?          # String? — absent key is nil
params["id"]              # String  — absent key raises KeyError
params.fetch("id", Int32)     # Integer, or 422 on bad input
params.fetch?("id", Int32)    # Integer?, or nil on bad input
params.permit("title", "body")
params.require("post").permit("title", "body")
```

An `application/json` request body joins the same params: `request.json`
holds the parsed body, and its top-level scalar values are merged (query and
form values win on conflicts):

```crystal
request.json            # JSON::Any? — nil when the body is not JSON
params["name"]?         # a top-level JSON value, as a String
```

`request.format` reports the format the client asked for — the path suffix
(`/posts.json`), else the `Accept` header, else `:html`:

```crystal
case request.format
when :json then render json: post
when :text then render text: "…"
else            render :show
end
```

## Rendering

An action ends by rendering something. Plain strings and helpers:

```crystal
render html: "<h1>Hello</h1>"
render text: "plain", status: ::HTTP::Status::NOT_FOUND
render json: %({"ok": true})
render json: {ok: true, id: 42}   # any JSON-able object is serialized
redirect_to posts_path
redirect_back fallback: posts_path   # honors Referer, same-host only
head ::HTTP::Status::NO_CONTENT      # bodyless answer; later writes ignored
no_content                           # shorthand for 204
```

When the controller declares templates, `render` takes the action name plus
its locals:

```crystal
render :index, locals: {posts: Post.all.to_a}
render :index, layout: false, locals: {posts: Post.all.to_a}
render "form", locals: {post: post}   # a partial, returns a String
```

## Callbacks

Filters run around the action. `only:` / `except:` restrict the actions a
filter applies to, and a before callback that writes a response (render,
redirect, head) halts the chain — the action and its after callbacks are
skipped:

```crystal
class Admin::PostsController < PostsController
  before_action :require_login, only: [:new, :create]
  after_action :audit_action

  skip_before_action :require_login   # inherited filters can be removed
end
```

Filters are inherited across the controller hierarchy, and a skip declared
in one subclass does not affect its siblings. A filter is a plain public
method; any response it writes answers the request.

## respond_to

One action, several format handlers. The block declares a handler per
format; the one matching `request.format` runs, and a request for an
undeclared format answers 406:

```crystal
def show : Nil
  post = Post.find(params.fetch("id", Int32))
  respond_to do |format|
    format.html { render :show, locals: {post: post} }
    format.json { render json: post }
    format.text { render text: post.to_s }
  end
end
```

## Streaming

`stream` opens a chunked response body — every write to the yielded `IO`
reaches the client as it happens, with the content type set first:

```crystal
def events : Nil
  stream("text/event-stream") do |io|
    io << "data: hello\n\n"
    io.flush
  end
end
```

## Exceptions to responses

A controller can map a raised exception to a response. The handler method
receives the exception (cast to the registered type), and subclass
exceptions match:

```crystal
class PostsController < Altair::Controller
  rescue_from MissingPost, handle_with: :render_missing

  def render_missing(e : MissingPost) : Nil
    render text: "No such post", status: ::HTTP::Status::NOT_FOUND
  end
end
```

`only:` / `except:` restrict the actions a handler answers for, handlers
inherit across the hierarchy, and an unhandled exception re-raises to the
application's error pages. At the application level, `rescue_from` maps an
exception to a fixed status:

```crystal
class Blog < Altair::Application
  rescue_from KeyError, to: 404
end
```

## Templates

The `templates` macro declares the view files and compiles them into typed
render methods — a wrong local name or type is a compile error:

```crystal
class PostsController < ApplicationController
  templates "posts",
    root: __DIR__ + "/../views",
    layout: "application",
    index: {posts: Array(Post)},
    show: {post: Post}
end
```

This renders `views/posts/index.ecr` and `views/posts/show.ecr`, each
receiving exactly the declared locals. See the [Views guide](/docs/views.html).
