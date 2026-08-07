# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Config::DotEnv`, the `.env` file loader. A
# `.env` file in the application root sets environment variables without a
# shell export ceremony — the standard 12-factor way to keep deployment
# secrets out of the repository. An optional `.env.<environment>` overrides
# the base file for the current environment.
module Altair
  class Config
    # Loads `KEY=VALUE` pairs from `.env` files into the process
    # environment. `.env` sets dev/test defaults; `.env.<environment>` wins
    # for the active environment; and a variable already present in the
    # real environment always wins over either file (so `DATABASE_URL`
    # exported by the shell beats a checked-in fallback).
    class DotEnv
      # The name used by the environment-specific file, e.g. `.env.test`.
      def self.env_suffix(env : Env = Altair.env) : String
        ".#{env.to_s.downcase}"
      end

      # Loads `.env` and `.env.<environment>` from `root` into the process
      # environment. Existing variables are never overwritten. Returns the
      # number of variables that were set.
      def self.load(root : Path, env : Env = Altair.env) : Int32
        merged = {} of String => String
        load_file(root, ".env", merged)
        load_file(root, ".env#{env_suffix(env)}", merged)
        loaded = 0
        merged.each do |key, value|
          next if ENV.has_key?(key)
          ENV[key] = value
          loaded += 1
        end
        loaded
      end

      # Reads one `.env`-style file into `merged`. Later entries win, so an
      # environment-specific file overrides the base `.env`.
      private def self.load_file(root : Path, name : String, merged : Hash(String, String)) : Nil
        path = root.join(name)
        return unless File.exists?(path)
        parse(File.read(path)).each do |key, value|
          merged[key] = value
        end
      end

      # Parses `.env` content into a hash. Handles `KEY=VALUE` and
      # `export KEY=VALUE` lines, quoted and unquoted values, and `#`
      # comments. Values are returned exactly as written (trimmed and
      # unquoted) so the environment sees them verbatim.
      def self.parse(content : String) : Hash(String, String)
        vars = {} of String => String
        content.each_line do |raw|
          line = raw.strip
          next if line.empty? || line.starts_with?('#')
          line = line.lchop("export ").rstrip if line.starts_with?("export ")
          next if line.empty?
          index = line.index('=')
          next unless index
          key = line[0...index].strip
          value = line[(index + 1)..]
          value = strip_value(value)
          next if key.empty?
          vars[key] = value
        end
        vars
      end

      # Strips surrounding quotes and an inline comment from a value.
      private def self.strip_value(value : String) : String
        value = value.strip
        if value.size >= 2
          if (value.starts_with?('"') && value.ends_with?('"')) ||
             (value.starts_with?('\'') && value.ends_with?('\''))
            value = value[1..-2]
          else
            comment = value.index(" #")
            value = value[0...comment].rstrip if comment
          end
        end
        value
      end
    end
  end
end
