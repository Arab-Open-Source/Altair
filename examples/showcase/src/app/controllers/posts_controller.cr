# Showcase — the posts controller.
#
# Full CRUD with typed view locals, `respond_to` (HTML + JSON driven by the
# `:format` path suffix), a multipart image upload (`params.upload`), and
# the member / collection / nested routes. Every state-changing action
# requires a signed-in user and carries a CSRF token via `form_for`.
class PostsController < ApplicationController
  templates "posts",
    root: __DIR__ + "/../views",
    layout: "application",
    index: {posts: Array(Post)},
    show: {post: Post, comments: Array(Comment)},
    new: {post: Post},
    edit: {post: Post},
    form: {post: Post, action: String, method: Symbol}

  before_action :require_login, only: [:new, :create, :edit, :update, :destroy, :publish]

  # GET /posts — the feed of published posts, or the same feed as JSON
  # when the request carries a `:json` format (e.g. `/posts.json`).
  def index : Nil
    posts = Post.all.includes(:user).where(published: true).order(:id, :desc).to_a
    respond_to do |format|
      format.html { render :index, locals: {posts: posts} }
      format.json { render json: posts.map { |post| {id: post.id, title: post.title, body: post.body} } }
    end
  end

  # GET /posts/:id — a post with its comments, with the comment authors
  # eager-loaded through `includes` (one batched query, not N+1).
  def show : Nil
    if post = Post.find(params.fetch("id", Int32))
      comments = Comment.all.where(post_id: post.id).includes(:user).order(:id, :desc).to_a
      render :show, locals: {post: post, comments: comments}
    else
      render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  # GET /posts/new — the create form.
  def new : Nil
    render :new, locals: {post: Post.new}
  end

  # POST /posts — create a post, handling the optional image upload.
  def create : Nil
    post = Post.new(
      title: params["title"]? || "",
      body: params["body"]? || "",
      published: params["published"]? == "1",
      user_id: current_user.not_nil!.id
    )
    if image = params.upload("image")
      post.image = save_upload(image)
    end
    if post.save
      flash["notice"] = "Post created."
      redirect_to post_path(post.id.not_nil!)
    else
      response.status = ::HTTP::Status::UNPROCESSABLE_ENTITY
      render :new, locals: {post: post}
    end
  end

  # GET /posts/:id/edit — the edit form.
  def edit : Nil
    if post = Post.find(params.fetch("id", Int32))
      render :edit, locals: {post: post}
    else
      render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  # PUT /posts/:id — update a post, optionally replacing its image.
  def update : Nil
    if post = Post.find(params.fetch("id", Int32))
      post.title = params["title"]? || ""
      post.body = params["body"]? || ""
      post.published = params["published"]? == "1"
      if image = params.upload("image")
        post.image = save_upload(image)
      end
      if post.save
        flash["notice"] = "Post updated."
        redirect_to post_path(post.id.not_nil!)
      else
        response.status = ::HTTP::Status::UNPROCESSABLE_ENTITY
        render :edit, locals: {post: post}
      end
    else
      render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  # DELETE /posts/:id — remove a post (comments go with it).
  def destroy : Nil
    if post = Post.find(params.fetch("id", Int32))
      post.delete
      flash["notice"] = "Post deleted."
      redirect_to posts_path
    else
      render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  # POST /posts/:id/publish — a member route toggling the published flag.
  def publish : Nil
    if post = Post.find(params.fetch("id", Int32))
      post.published = !post.published
      post.save
      flash["notice"] = post.published ? "Post published." : "Post unpublished."
      redirect_to post_path(post.id.not_nil!)
    else
      render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  # POST /posts/recent — a collection route: the latest five posts.
  def recent : Nil
    posts = Post.all.includes(:user).where(published: true).order(:id, :desc).limit(5).to_a
    render :index, locals: {posts: posts}
  end

  # GET /archive/:year — posts from a single year; the route's `:year`
  # parameter is constrained to four digits.
  def by_year : Nil
    year = params["year"]
    posts = Post.all.includes(:user).where(published: true).order(:id, :desc).to_a
      .select { |post| post.created_at.try(&.year) == year.to_i }
    render :index, locals: {posts: posts}
  end

  private def save_upload(upload : Altair::HTTP::UploadedFile) : String
    dir = Path.new("public/uploads")
    Dir.mkdir_p(dir)
    ext = File.extname(upload.original_filename || "")
    name = "#{Time.utc.to_unix}_#{Random::Secure.hex(4)}#{ext}"
    upload.save(dir.join(name))
    "/uploads/#{name}"
  end
end
