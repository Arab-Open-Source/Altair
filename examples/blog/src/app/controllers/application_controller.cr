# Blog — the shared controller base.
#
# It brings in the application's generated path helpers, so actions can
# call `posts_path`, `new_post_path`, `post_path(5)` and friends as plain
# methods, and the shared page chrome both controllers render into.
abstract class ApplicationController < Altair::Controller
  # The shared page chrome every page renders into.
  private def page_html(body : String) : String
    <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <link rel="stylesheet" href="/css/app.css">
          <title>Blog</title>
        </head>
        <body>
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
