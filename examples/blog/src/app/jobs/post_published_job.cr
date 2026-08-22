# Blog — the background job announcing a newly published post.
#
# Enqueued by the posts controller on create; run it with:
#
# ```
# crystal run scripts/jobs.cr
# ```
class PostPublishedJob < Altair::Jobs::Job
  params post_id : Int64, title : String

  def perform : Nil
    Log.for("blog.jobs").info do
      "announcing post ##{post_id} — \"#{title}\""
    end
  end
end
