# Blog — the migration runner script.
#
# Applies and rolls back migrations against the application database, then
# regenerates `db/schema.cr`. Run from the example directory:
#
# ```
# crystal run scripts/db.cr migrate
# crystal run scripts/db.cr rollback
# ```
require "altair"
require "../db/schema"
require "../src/app/models/comment"
require "../src/app/models/post"
require "../src/app/controllers/application_controller"
require "../src/app/controllers/comments_controller"
require "../src/app/controllers/posts_controller"
require "../src/config/application"
require "../db/migrations/20260802000001_create_posts"
require "../db/migrations/20260802000002_add_comments"
require "../db/migrations/20260802000003_add_timestamps_to_posts"

conn = Altair::Record::Connection.for(Blog.instance)
runner = Altair::Record::Migrations::Runner.new(
  conn,
  Path.new("db/migrations"),
  Path.new("db/schema.cr"),
  conn.adapter
)

case ARGV[0]?
when "migrate"
  count = runner.migrate
  puts count.zero? ? "Already up to date." : "Applied #{count} migration(s)."
when "rollback"
  if runner.rollback
    puts "Rolled back one migration."
  else
    puts "Nothing to roll back."
  end
else
  abort "usage: crystal run scripts/db.cr migrate|rollback"
end

conn.close
