# Blog — the background-jobs worker script.
#
# Drains the `altair_jobs` table until interrupted. Create a post through
# the web UI first — each new post enqueues a PostPublishedJob:
#
# ```
# crystal run scripts/db.cr -- migrate   # once, to create the schema
# crystal run src/blog.cr                # the server, in another terminal
# crystal run scripts/jobs.cr            # this worker
# ```
require "log"
require "altair"
require "../db/schema"
require "../src/app/models/comment"
require "../src/app/models/post"
require "../src/app/models/user"
require "../src/app/controllers/application_controller"
require "../src/app/controllers/comments_controller"
require "../src/app/controllers/posts_controller"
require "../src/app/controllers/sessions_controller"
require "../src/app/controllers/registrations_controller"
require "../src/app/jobs/post_published_job"
require "../src/config/application"

Log.setup(:info)

worker = Altair::Jobs::Worker.new(Blog.instance.config.jobs_poll_interval)
puts "Blog worker started — Ctrl-C to stop."
worker.run
