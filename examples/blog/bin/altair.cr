require "altair"
require "../db/schema"
require "../db/migrations/**"
require "../src/app/models/**"
require "../src/app/controllers/**"
require "../src/app/jobs/**"
require "../src/config/application"

case ARGV[0]?
when "server"
  exit Altair::CLI::Project.server(Blog, ARGV[1..])
when "routes"
  Altair::CLI::Project.print_routes(Blog)
when "db:migrate"
  exit Altair::CLI::Project.migrate(Blog)
when "db:rollback"
  exit Altair::CLI::Project.rollback(Blog)
when "db:create"
  exit Altair::CLI::Project.create_databases
when "db:drop"
  exit Altair::CLI::Project.drop_databases
when "assets:precompile"
  exit Altair::CLI::Project.precompile_assets(Blog)
when "jobs:work"
  exit Altair::CLI::Project.jobs_work(Blog)
when "jobs:stats"
  exit Altair::CLI::Project.jobs_stats(Blog)
else
  exit Altair::CLI.run(ARGV)
end
