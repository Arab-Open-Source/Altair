# Altair — the batteries-included web framework for Crystal.
#
# Minimal ANSI helpers for the development console. Colors are emitted
# only when STDOUT is a TTY and `NO_COLOR` is unset, or when
# `config.logger_colors` forces them on/off.
module Altair
  module Support
    module ANSI
      COLORS = {
        reset:   "\e[0m",
        green:   "\e[32m",
        blue:    "\e[34m",
        yellow:  "\e[33m",
        magenta: "\e[35m",
        red:     "\e[31m",
        cyan:    "\e[36m",
        dim:     "\e[2m",
        bold:    "\e[1m",
      }

      # Whether the current process should emit colors.
      def self.enabled?(override : Bool? = nil) : Bool
        return override unless override.nil?
        return false if ENV["NO_COLOR"]?
        return false if ENV["TERM"]? == "dumb"
        STDOUT.tty?
      end

      # Wraps `text` in the given color when colors are enabled.
      def self.colorize(text : String, color : Symbol, enabled : Bool) : String
        return text unless enabled
        code = COLORS[color]? || ""
        return text if code.empty?
        "#{code}#{text}#{COLORS[:reset]}"
      end
    end
  end
end
