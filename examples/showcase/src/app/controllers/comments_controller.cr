# Showcase — the comments controller.
#
# A nested resource: routes live under `/posts/:post_id/comments`, and the
# post id comes from the URL (`params["post_id"]`). Comments require a
# signed-in author; `redirect_back` returns the visitor to the post they
# were reading after a submission.
class CommentsController < ApplicationController
  before_action :require_login

  # POST /posts/:post_id/comments
  def create : Nil
    if post = Post.find(params.fetch("post_id", Int32))
      comment = Comment.new(
        body: params["body"]? || "",
        post_id: post.id,
        user_id: current_user.not_nil!.id
      )
      if comment.save
        flash["notice"] = "Comment added."
      else
        flash["alert"] = "Comment could not be added."
      end
      redirect_back(fallback: post_path(post.id.not_nil!))
    else
      render text: "Post not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  # DELETE /posts/:post_id/comments/:id — comment authors and post owners
  # may remove a comment.
  def destroy : Nil
    if comment = Comment.find(params.fetch("id", Int32))
      post = comment.post
      owner_id = current_user_id.try(&.to_i)
      if post && owner_id && (comment.user_id == owner_id || post.user_id == owner_id)
        comment.delete
        flash["notice"] = "Comment deleted."
      else
        flash["alert"] = "You cannot delete that comment."
      end
      redirect_back(fallback: post ? post_path(post.id.not_nil!) : posts_path)
    else
      render text: "Comment not found", status: ::HTTP::Status::NOT_FOUND
    end
  end
end
