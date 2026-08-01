# Hello World — the posts controller.
#
# A complete in-memory resource: posts live in an array (no database before
# the ORM phase) and the seven RESTful actions from `resources :posts` are
# implemented as instance methods on `Altair::Controller`. Note the use of
# the generated helpers — `posts_path`, `new_post_path`, `post_path(5)`,
# `edit_post_path(5)` — and of `render`, `redirect_to` and `head` instead
# of touching the response object directly.
class PostsController < ApplicationController
  class Post
    property id : Int32
    property title : String

    def initialize(@id : Int32, @title : String)
    end
  end

  @@posts = Array(Post).new
  @@next_id = 1

  def index : Nil
    rows = @@posts.map do |post|
      <<-HTML
        <li>
          <a href="#{post_path(post.id)}">#{post.title}</a>
          <a href="#{edit_post_path(post.id)}">edit</a>
          <form action="#{post_path(post.id)}" method="post">
            <input type="hidden" name="_method" value="DELETE">
            <button>delete</button>
          </form>
        </li>
      HTML
    end.join
    render html: <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <link rel="stylesheet" href="/css/app.css">
          <title>Posts</title>
        </head>
        <body>
          <h1>Posts</h1>
          <ul>#{rows}</ul>
          <p><a href="#{new_post_path}">New post</a> · <a href="/">Home</a></p>
        </body>
      </html>
      HTML
  end

  def new : Nil
    render html: page_html("<h1>New post</h1>#{form_html("/posts")}")
  end

  def create : Nil
    @@posts << Post.new(@@next_id, params["title"])
    @@next_id += 1
    redirect_to posts_path
  end

  def show : Nil
    if post = find(params["id"].to_i)
      render html: page_html(<<-HTML)
        <h1>#{post.title}</h1>
        <p>Post ##{post.id} — <a href="#{edit_post_path(post.id)}">edit</a></p>
      HTML
    else
      render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  def edit : Nil
    if post = find(params["id"].to_i)
      render html: page_html("<h1>Edit post</h1>#{form_html(post_path(post.id), title: post.title, method: "PUT")}")
    else
      render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  def update : Nil
    if post = find(params["id"].to_i)
      post.title = params["title"]
      redirect_to post_path(post.id)
    else
      render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  def destroy : Nil
    if post = find(params["id"].to_i)
      @@posts.delete(post)
      redirect_to posts_path
    else
      render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  private def find(id : Int32) : Post?
    @@posts.find { |post| post.id == id }
  end

  private def page_html(body : String) : String
    <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <link rel="stylesheet" href="/css/app.css">
          <title>Posts</title>
        </head>
        <body>
          #{body}
          <p><a href="#{posts_path}">Back to posts</a></p>
        </body>
      </html>
      HTML
  end

  private def form_html(action : String, title : String = "", method : String = "POST") : String
    <<-HTML
      <form action="#{action}" method="post">
        <input type="hidden" name="_method" value="#{method}">
        <label>Title <input name="title" value="#{title}"></label>
        <button>Save</button>
      </form>
    HTML
  end
end
