require "altair"
require "../db/schema"
require "../db/migrations/**"
require "../src/app/models/user"
require "../src/app/models/post"
require "../src/app/models/comment"
require "../src/app/controllers/application_controller"
require "../src/app/controllers/pages_controller"
require "../src/app/controllers/users_controller"
require "../src/app/controllers/sessions_controller"
require "../src/app/controllers/posts_controller"
require "../src/app/controllers/comments_controller"
require "../src/app/controllers/api_controller"
require "../src/config/application"
require "../src/config/routes"

case ARGV[0]?
when "server"
  Showcase.run!
when "routes"
  Altair::CLI::Project.print_routes(Showcase)
when "db:migrate"
  exit Altair::CLI::Project.migrate(Showcase)
when "db:rollback"
  exit Altair::CLI::Project.rollback(Showcase)
else
  exit Altair::CLI.run(ARGV)
end
