# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Middleware::Logger`, the request logger. It is
# the first middleware in the default stack: it times the request, lets the
# rest of the pipeline run, then writes a single line per request through
# the application's logger. The line is aligned for scanning, with optional
# colors, a timestamp, a request counter and slow-request highlighting:
#
# ```
# 05:18:45  GET      /                     200   0.1ms
# 05:18:46  POST     /tasks                201   0.3ms
# ```
#
# Because it wraps the whole pipeline, every response is logged — routed
# actions, 404s and 405s alike. Swap `config.logger` on the application to
# redirect these lines.
class Altair::Middleware::Logger < Altair::Middleware
  # Monotonic counter for `config.logger_request_counter`.
  @@counter = Atomic(Int32).new(0)

  def call(request : Altair::HTTP::Request, response : Altair::HTTP::Response, chain : Proc(Nil)) : Nil
    started = Time.instant
    chain.call
    elapsed_ms = (Time.instant - started).total_milliseconds
    app.config.logger.info { format_line(request, response, elapsed_ms) }
  end

  private def format_line(request : Altair::HTTP::Request, response : Altair::HTTP::Response, elapsed_ms : Float64) : String
    config = app.config

    if config.structured_logs?
      return format_json(request, response, elapsed_ms)
    end

    colors = Altair::Support::ANSI.enabled?(config.logger_colors)
    elapsed_str = "#{elapsed_ms.round(1)}ms"
    status = response.status.value
    method = request.method
    path = request.path

    # Compact mode — minimal, no alignment or timestamp.
    if config.logger_compact?
      method_c = colorize_method(method, colors)
      status_c = colorize_status(status, colors)
      slow = elapsed_ms > config.slow_request_threshold.total_milliseconds
      elapsed_c = slow ? Altair::Support::ANSI.colorize(elapsed_str, :yellow, colors) : elapsed_str
      slow_suffix = slow ? " [SLOW]" : ""
      return "#{method_c} #{path} #{status_c} #{elapsed_c}#{slow_suffix}"
    end

    String.build do |io|
      if config.logger_timestamps?
        now = Time.local
        time_str = "%02d:%02d:%02d" % {now.hour, now.minute, now.second}
        io << Altair::Support::ANSI.colorize(time_str, :dim, colors) << "  "
      end

      if config.logger_request_counter?
        count = @@counter.add(1) + 1
        counter_str = "#%04d" % count
        io << Altair::Support::ANSI.colorize(counter_str, :dim, colors) << "  "
      end

      if config.logger_show_client_ip?
        # Remote address is not yet plumbed through Altair::HTTP::Request;
        # keep the hook for future wiring.
      end

      method_c = colorize_method(method.ljust(7), colors)
      display_path = if path.size > 22
                       "…" + path[(path.size - 21)..]
                     else
                       path
                     end
      path_c = display_path.ljust(22)
      status_c = colorize_status(status.to_s.rjust(3), colors)

      io << method_c << "  " << path_c << "  " << status_c << "  "

      slow = elapsed_ms > config.slow_request_threshold.total_milliseconds
      if slow
        io << Altair::Support::ANSI.colorize(elapsed_str.rjust(7), :yellow, colors)
        io << Altair::Support::ANSI.colorize(" [SLOW]", :yellow, colors)
      else
        io << elapsed_str.rjust(7)
      end

      if id = request.request_id
        io << " (" << id << ")"
      end
    end
  end

  # One JSON object per request — safe for log aggregators. Never includes
  # cookies, Authorization headers or request bodies.
  private def format_json(request : Altair::HTTP::Request, response : Altair::HTTP::Response, elapsed_ms : Float64) : String
    String.build do |io|
      io << "{\"method\":\""
      io << request.method << "\",\"path\":\""
      io << request.path << "\",\"status\":"
      io << response.status.value << ",\"duration_ms\":"
      io << elapsed_ms.round(1)
      if id = request.request_id
        io << ",\"request_id\":\"" << id << "\""
      end
      io << "}"
    end
  end

  private def colorize_method(text : String, enabled : Bool) : String
    color = case text.strip
            when "GET"     then :green
            when "POST"    then :blue
            when "PUT"     then :yellow
            when "PATCH"   then :magenta
            when "DELETE"  then :red
            when "OPTIONS" then :cyan
            else                :reset
            end
    Altair::Support::ANSI.colorize(text, color, enabled)
  end

  private def colorize_status(text : String, enabled : Bool) : String
    code = text.strip.to_i?
    color = if code.nil?
              :reset
            else
              case code
              when 200..299 then :green
              when 300..399 then :blue
              when 400..499 then :yellow
              when 500..599 then :red
              else               :reset
              end
            end
    Altair::Support::ANSI.colorize(text, color, enabled)
  end

  private def colorize_status(code : Int32, enabled : Bool) : String
    colorize_status(code.to_s, enabled)
  end
end
