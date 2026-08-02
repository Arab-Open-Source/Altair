# Blog — the posts controller.
#
# The same REST actions as hello_world, but backed by SQLite through
# `Altair::Record.connection` instead of an in-memory array. Every value
# travels as a bind parameter — the SQL strings are constant.
class PostsController < ApplicationController
  def index : Nil
    posts = [] of NamedTuple(id: Int64, title: String)
    Altair::Record.connection.query("SELECT id, title FROM posts ORDER BY id DESC") do |rs|
      rs.each do
        posts << {id: rs.read(Int64), title: rs.read(String)}
      end
    end
    rows = posts.map do |post|
      "<li>#{post[:id]}: #{post[:title]}</li>"
    end.join
    render html: <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <title>Blog</title>
        </head>
        <body>
          <h1>Blog</h1>
          <form action="/posts" method="post">
            <input name="title" placeholder="Title">
            <button>Add post</button>
          </form>
          <ul>#{rows}</ul>
        </body>
      </html>
      HTML
  end

  def create : Nil
    title = params["title"]?.to_s.strip
    unless title.empty?
      Altair::Record.connection.exec("INSERT INTO posts (title) VALUES (?)", title)
    end
    redirect_to "/"
  end
end
