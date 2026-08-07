# Showcase — the application configuration.
#
# The database URL and secret come from `config/database.yml` (+ `.env`),
# not this file: `Altair::Config::DotEnv.load` and
# `Altair::Config::Database.apply` run when the application instance is
# created, so `SECRET_KEY_BASE` and `DATABASE_URL` placed in `.env` are
# honoured without touching code. `ENV["DATABASE_URL"]` overrides the
# `url` in `database.yml`.
class Showcase < Altair::Application
  config.name = "Showcase"
  config.port = ENV["PORT"]?.try(&.to_i) || 4000

  # Sessions sign their cookies with `config.secret_key_base`. Read from
  # `.env` via `SECRET_KEY_BASE`, with a development fallback so the demo
  # boots before any configuration step.
  config.secret_key_base = ENV["SECRET_KEY_BASE"]? || "showcase-development-secret-change-me"

  # The safety headers sent on every response. `config.security_headers` is
  # a plain `String => String` map — override individual keys or clear it.
  config.security_headers = {
    "X-Content-Type-Options" => "nosniff",
    "X-Frame-Options"        => "SAMEORIGIN",
    "Referrer-Policy"        => "strict-origin-when-cross-origin",
  }

  # Requests carry a generated `X-Request-Id` (the client's header is
  # honoured when present), and request-log lines include it.
  config.request_id_header = "X-Request-Id"
end

# Predefined so `config/routes.cr` can include the generated path helpers
# before any route is declared.
module Showcase::RouteHelpers
end
