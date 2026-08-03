require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # The benchmark runs plain HTTP on the host (no TLS terminates in front).
  config.force_ssl = false
  config.assume_ssl = false

  # Only serve operational logs to a pipe the runner can tail; the k6 load
  # itself asserts on HTTP status, so we keep request logs minimal.
  config.log_level = :error

  # Production-safe: never cache assets, only API responses.
  config.action_controller.perform_caching = false

  # Set the logging destination(s)
  config.log_tags = [] #for environments with no log_tags

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Disable Active Record's verbose query logging; k6 measures HTTP, and the
  # log noise would distort the request path.
  ActiveRecord::Base.logger = nil

  # Avoid every request adding an extra "Host" or logger write in production.
  config.logger = Logger.new(IO::NULL)
end