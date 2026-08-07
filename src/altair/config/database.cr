# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Config::Database`, the `database.yml` loader.
# A `config/database.yml` in the application root holds per-environment
# database settings — url, pool sizes, timeouts — so a production database
# switch means editing a file, never application code. The active
# environment's section is merged into `Altair::Config`, keyed by the
# lowercase environment name (`development`, `production`, `test`).
require "yaml"

module Altair
  class Config
    # Reads `config/database.yml` from `root` and merges the active
    # environment's section into the configuration. A missing section or
    # file is a no-op, so a project without one keeps its default settings.
    # Recognised keys, all optional:
    #
    # ```yaml
    # production:
    #   url: postgresql://user:pass@localhost/blog_production
    #   pool: 10
    #   initial_pool: 4
    #   max_idle_pool: 4
    #   checkout_timeout: 5.0
    #   query_timeout: 5.0
    # ```
    class Database
      # Loads `config/database.yml` from `root` and applies the section
      # matching the active environment to `config`. Returns whether a
      # section was actually applied; a missing file or environment leaves
      # the configuration untouched.
      def self.apply(config : Altair::Config, root : Path, env : Env = Altair.env) : Bool
        path = root.join("config").join("database.yml")
        return false unless File.exists?(path)
        section = section_for(path, env)
        return false unless section

        if url = section["url"]?
          config.db_url = url.as_s?
        end
        config.db_max_pool_size = section["pool"].as_i if section["pool"]?
        config.db_initial_pool_size = section["initial_pool"].as_i if section["initial_pool"]?
        config.db_max_idle_pool_size = section["max_idle_pool"].as_i if section["max_idle_pool"]?
        if timeout = section["checkout_timeout"]?
          config.db_checkout_timeout = timeout.as_f.to_f64
        end
        if timeout = section["query_timeout"]?
          config.db_query_timeout = Time::Span.new(nanoseconds: (timeout.as_f.to_f64 * 1_000_000_000).to_i64)
        end
        true
      end

      # The environment section from `database.yml`, or `nil` when the file
      # or environment is absent.
      private def self.section_for(path : Path, env : Env) : YAML::Any?
        parsed = YAML.parse(File.read(path))
        return unless parsed.as_h?
        sections = parsed.as_h
        sections[env.to_s.downcase]?
      end
    end
  end
end
