# Blog — the comments controller.
#
# A single create action: the form lives on the post page and posts here.
# Validation failures re-render the post with the error inline; the
# comment is never stored.
class CommentsController < ApplicationController
  def create : Nil
    if post = find_post
      comment = Comment.create(post_id: post.id, body: params["body"]?)
      if comment.errors.empty?
        redirect_to post_path(post.id.not_nil!)
      else
        body = page_html(<<-HTML)
          <h1>#{post.title}</h1>
          <p>Post ##{post.id} — <a href="#{edit_post_path(post.id.not_nil!)}">edit</a></p>
          #{comments_html(post, comment)}
          HTML
        render html: body, status: ::HTTP::Status::UNPROCESSABLE_ENTITY
      end
    else
      render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  private def find_post : Post?
    if id = params["post_id"]?.try(&.to_i?)
      Post.find(id)
    end
  end
end
