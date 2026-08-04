# Hello World — the pages controller.
#
# Static pages rendered as plain HTML. The `index` page links the
# stylesheet served by the static-files middleware from `public/`.
class PagesController < ApplicationController
  def index : Nil
    render html: <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <link rel="stylesheet" href="/css/app.css">
          <title>Hello World</title>
        </head>
        <body>
          <h1>Hello World</h1>
          <p>Altair is running — controllers dispatch per request, the
          router matched this route, and this stylesheet was served from
          <code>public/</code>.</p>
          <p><a href="/posts">Visit the posts</a></p>
        </body>
      </html>
      HTML
  end

  def hello : Nil
    name = params["name"]
    render html: <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <link rel="stylesheet" href="/css/app.css">
          <title>Hello, #{name}</title>
        </head>
        <body>
          <h1>Hello, #{name}!</h1>
          <p>This page was rendered by <code>PagesController#hello</code>,
          and <code>params["name"]</code> came from the URL.</p>
          <p><a href="/">Back home</a></p>
        </body>
      </html>
      HTML
  end

  # Renders a page from the built-in docs via a glob route: `/docs/*path`
  # captures everything after `/docs/` into `params["path"]`, joined with
  # slashes. Nested paths resolve to the last segment, so
  # `/docs/guides/record` and `/docs/record` show the same page. Unknown
  # pages answer 404.
  def docs : Nil
    path = params["path"]
    page = path.split("/").last
    body = case page
           when "routing"
             "The router matches URL segments against pre-parsed patterns, so a typo in a path is a 404, not a crash."
           when "views"
             "Views render with auto-escaping out of the box, and partials make pages composable."
           when "record"
             "Record is the ORM — adapters, migrations and associations with eager loading."
           when "conventions"
             "Routes are compile-time and controllers dispatch per request."
           else
             render text: "No such page: #{path}", status: ::HTTP::Status::NOT_FOUND
             return
           end
    render html: <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <link rel="stylesheet" href="/css/app.css">
          <title>#{page}</title>
        </head>
        <body>
          <h1>#{page}</h1>
          <p>#{body}</p>
          <p><a href="/docs/routing">routing</a> · <a href="/docs/views">views</a> ·
          <a href="/docs/record">record</a> · <a href="/docs/conventions">conventions</a></p>
          <p><a href="/">Back home</a></p>
        </body>
      </html>
      HTML
  end

  # Temporary route to demo the 500 error page in development. Delete once
  # it has served its purpose.
  def boom : Nil
    raise "boom went off — demo of the 500 error page"
  end
end
