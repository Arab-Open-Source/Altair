# Blog — the posts controller.
#
# The same REST actions as hello_world, but backed by SQLite through the
# `Post` model. Every value travels as a bind parameter — the SQL strings
# are constant — and validation failures are reported inline. The index
# eager-loads each post's comments in one batched query, so the comment
# counts never trigger a query per post.
class PostsController < ApplicationController
  before_action :require_login, only: [:create, :update, :destroy]

  def index : Nil
    rows = Post.all.includes(:comments).to_a.sort_by { |post| -post.id.not_nil! }.map do |post|
      count = post.comments.size
      <<-HTML
        <li>
          <a href="#{post_path(post.id.not_nil!)}">#{post.title}</a>
          (#{count} comment#{count == 1 ? "" : "s"})
          <a href="#{edit_post_path(post.id.not_nil!)}">edit</a>
          <form action="#{post_path(post.id.not_nil!)}" method="post">
            <input type="hidden" name="_method" value="DELETE">
            <button>delete</button>
          </form>
        </li>
        HTML
    end.join
    render html: page_html(<<-HTML)
      <h1>Posts</h1>
      <ul>#{rows}</ul>
      <p><a href="#{new_post_path}">New post</a> · <a href="/search">Search</a> · <a href="/">Home</a></p>
      HTML
  end

  def new : Nil
    render html: page_html("<h1>New post</h1>#{form_html("/posts")}")
  end

  # The v0.4.0 query DSL end to end: a LIKE over titles with an OR branch
  # folding into it, a negated clause, ordering and a bound — every value
  # below travels as a bind parameter.
  def search : Nil
    query = (params["q"]? || "").strip
    pattern = "%#{query}%"
    posts = Post.all
      .where(:title, :like, pattern)
      .or_where(:body, :like, pattern)
      .where_not(title: "")
      .order(:id, :desc)
      .limit(20).to_a
    rows = posts.map do |post|
      "<li><a href=\"#{post_path(post.id.not_nil!)}\">#{post.title}</a></li>"
    end.join
    empty_state = query.empty? ? "<p>Type something to search.</p>" : "<p>No posts matched \"#{query}\".</p>"
    render html: page_html(<<-HTML)
      <h1>Search</h1>
      <form action="/search" method="get">
        <input name="q" value="#{query}"> <button>Search</button>
      </form>
      #{rows.empty? ? empty_state : "<ul>#{rows}</ul>"}
      HTML
  end

  def create : Nil
    post = Post.new(title: params["title"]?)
    if post.save
      PostPublishedJob.enqueue(post_id: post.id.not_nil!.to_i64, title: post.title.to_s)
      redirect_to post_path(post.id.not_nil!)
    else
      render html: page_html("<h1>New post</h1>#{form_html("/posts", post)}"), status: ::HTTP::Status::UNPROCESSABLE_ENTITY
    end
  end

  def show : Nil
    if post = find_post
      render html: page_html(<<-HTML)
        <h1>#{post.title}</h1>
        <p>Post ##{post.id} — <a href="#{edit_post_path(post.id.not_nil!)}">edit</a></p>
        #{comments_html(post)}
        HTML
    else
      render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  def edit : Nil
    if post = find_post
      render html: page_html("<h1>Edit post</h1>#{form_html(post_path(post.id.not_nil!), post, method: "PUT")}")
    else
      render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  def update : Nil
    if post = find_post
      post.title = params["title"]?
      if post.save
        redirect_to post_path(post.id.not_nil!)
      else
        render html: page_html("<h1>Edit post</h1>#{form_html(post_path(post.id.not_nil!), post, method: "PUT")}"), status: ::HTTP::Status::UNPROCESSABLE_ENTITY
      end
    else
      render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  def destroy : Nil
    if post = find_post
      post.delete
      redirect_to posts_path
    else
      render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  private def find_post : Post?
    if id = params["id"]?.try(&.to_i?)
      Post.find(id)
    end
  end

  private def form_html(action : String, post : Post = Post.new, method : String = "POST") : String
    error = post.errors[:title].first? ? "<p class=\"error\">#{post.errors[:title].first}</p>" : ""
    <<-HTML
      <form action="#{action}" method="post">
        <input type="hidden" name="_method" value="#{method}">
        <label>Title <input name="title" value="#{post.title}"></label>
        <button>Save</button>
      </form>
      #{error}
      HTML
  end
end
