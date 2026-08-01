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

  # Temporary route to demo the 500 error page in development. Delete once
  # it has served its purpose.
  def boom : Nil
    raise "boom went off — demo of the 500 error page"
  end
end
