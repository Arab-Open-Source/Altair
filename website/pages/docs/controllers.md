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

## Rendering

An action ends by rendering something. Plain strings and helpers:

```crystal
render html: "<h1>Hello</h1>"
render text: "plain", status: ::HTTP::Status::NOT_FOUND
render json: %({"ok": true})
redirect_to posts_path
head ::HTTP::Status::NO_CONTENT
```

When the controller declares templates, `render` takes the action name plus
its locals:

```crystal
render :index, locals: {posts: Post.all.to_a}
render :index, layout: false, locals: {posts: Post.all.to_a}
render "form", locals: {post: post}   # a partial, returns a String
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

## Exceptions to responses

`rescue_from` maps a raised exception to a response instead of a bare 500:

```crystal
class Blog < Altair::Application
  rescue_from KeyError, to: 404
end
```

`KeyError` (a missing param or a missing record raised with `raise KeyError`)
now answers 404.
