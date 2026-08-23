# Blog — the shared controller base.
#
# It brings in the application's generated path helpers, so actions can
# call `posts_path`, `new_post_path`, `post_path(5)` and friends as plain
# methods, and the shared page chrome both controllers render into.
abstract class ApplicationController < Altair::Controller
  include Altair::View::Helpers

  # The shared page chrome every page renders into. Styles come from the
  # asset pipeline (`assets/css/app.css` compiled by
  # `crystal run scripts/assets.cr`), and the header reflects the session.
  private def page_html(body : String) : String
    auth_nav = if logged_in?
                 <<-NAV
                   <a href="/posts">posts</a> ·
                   <form class="inline" action="/logout" method="post">
                     <input type="hidden" name="_method" value="DELETE">
                     <button class="link">sign out</button>
                   </form>
                   NAV
               else
                 %(<a href="/login">sign in</a> · <a href="/register">register</a>)
               end
    <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <link rel="stylesheet" href="#{asset_url("css/app.css")}">
          <title>Blog</title>
        </head>
        <body>
          <nav>#{auth_nav}</nav>
          #{body}
          <p><a href="#{posts_path}">Back to posts</a></p>
        </body>
      </html>
      HTML
  end

  # The comments section of a post: the list, an inline error when a
  # comment failed validation, and the new-comment form.
  private def comments_html(post : Post, comment : Comment = Comment.new) : String
    error = comment.errors[:body].first? ? "<p class=\"error\">#{comment.errors[:body].first}</p>" : ""
    list = post.comments.map do |item|
      "<li>#{item.body}</li>"
    end.join
    <<-HTML
      <h2>Comments</h2>
      <ul>#{list}</ul>
      #{error}
      <form action="#{post_comments_path(post.id.not_nil!)}" method="post">
        <label>Comment <input name="body"></label>
        <button>Add comment</button>
      </form>
      HTML
  end
end
