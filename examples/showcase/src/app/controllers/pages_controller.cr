# Showcase — the static and stream pages.
#
# Home, about, a glob-routed docs page and a server-sent events stream
# (`stream("text/event-stream")`). The home feed is the same `Post.all`
# the posts controller uses, so the whole stack is visible on one page.
class PagesController < ApplicationController
  templates "pages",
    root: __DIR__ + "/../views",
    layout: "application",
    index: {posts: Array(Post)}

  # GET / — the home page: the latest published posts plus login state.
  def index : Nil
    posts = Post.all.includes(:user).where(published: true).order(:id, :desc).limit(8).to_a
    render :index, locals: {posts: posts}
  end

  # GET /about — a static page.
  def about : Nil
    render html: <<-HTML
      <h1>About Showcase</h1>
      <p>Showcase is the full-stack Altair demo: Record, sessions, auth,
      CSRF, multipart uploads, `.env` configuration, security middleware,
      JSON + JWT, streaming and the routing DSL in one running app.</p>
      <p><a href="/">Back home</a></p>
      HTML
  end

  # GET /docs/*path — a glob route capturing every segment after `/docs/`.
  # Unknown pages answer 404.
  def docs : Nil
    body = case params["path"]
           when "routing"
             "Routes are parsed segment-by-segment at startup, so a typo is a 404, not a crash. Path helpers are compiler-checked methods."
           when "sessions"
             "Sessions are signed cookies. `protect_from_forgery` guards every state-changing request with a token; `sign_in` and `sign_out` manage the user id."
           when "record"
             "Record is the ORM: adapters, migrations, associations with eager loading and validations."
           else
             return render text: "No such page: #{params["path"]}", status: ::HTTP::Status::NOT_FOUND
           end
    render html: <<-HTML
      <h1>#{params["path"]}</h1>
      <p>#{body}</p>
      <p><a href="/">Back home</a></p>
      HTML
  end

  # GET /stream — a server-sent events feed, pushed chunk by chunk.
  def stream : Nil
    stream("text/event-stream") do |io|
      5.times do |index|
        io << "data: tick #{index + 1}\n\n"
        io.flush
        sleep 250.milliseconds
      end
    end
  end
end
