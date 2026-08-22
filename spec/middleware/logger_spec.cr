# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Middleware::Logger`: one line per request with the
# method, path and final status, written through the application's logger.
require "../spec_helper"
require "log/io_backend"

private def capture_logger : Tuple(IO::Memory, Log, Proc(Nil))
  io = IO::Memory.new
  backend = Log::IOBackend.new(io, dispatcher: Log::DispatchMode::Sync)
  Log.builder.bind("altair.spec.logger", :info, backend)
  log = Log.for("altair.spec.logger")
  {io, log, -> { Log.builder.clear }}
end

private def logger_request(method : String = "GET", path : String = "/posts") : Altair::HTTP::Request
  Altair::HTTP::Request.new(HTTP::Request.new(method, path))
end

private def logger_response(status : ::HTTP::Status = ::HTTP::Status::OK) : Altair::HTTP::Response
  response = Altair::HTTP::Response.new(HTTP::Server::Response.new(IO::Memory.new))
  response.status = status
  response
end

describe Altair::Middleware::Logger do
  it "logs the method, path and status of the request" do
    io, log, unbind = capture_logger
    logger = Altair::Middleware::Logger.new(SpecApp.instance)
    config = SpecApp.instance.config
    original_logger = config.logger
    original_colors = config.logger_colors
    original_timestamps = config.logger_timestamps?
    original_counter = config.logger_request_counter?
    config.logger = log
    config.logger_colors = false
    config.logger_timestamps = false
    config.logger_request_counter = false
    begin
      logger.call(logger_request("GET", "/posts"), logger_response(::HTTP::Status::NOT_FOUND), -> { })
      body = io.to_s
      body.should contain("GET")
      body.should contain("/posts")
      body.should contain("404")
    ensure
      unbind.call
      config.logger = original_logger
      config.logger_colors = original_colors
      config.logger_timestamps = original_timestamps
      config.logger_request_counter = original_counter
    end
  end

  it "runs the chain before logging" do
    io, log, unbind = capture_logger
    logger = Altair::Middleware::Logger.new(SpecApp.instance)
    config = SpecApp.instance.config
    original_logger = config.logger
    original_colors = config.logger_colors
    config.logger = log
    config.logger_colors = false
    ran = false
    begin
      logger.call(logger_request("POST", "/books"), logger_response(::HTTP::Status::CREATED), -> { ran = true })
      ran.should be_true
      body = io.to_s
      body.should contain("POST")
      body.should contain("/books")
      body.should contain("201")
    ensure
      unbind.call
      config.logger = original_logger
      config.logger_colors = original_colors
    end
  end

  it "appends the request id when one is assigned" do
    io, log, unbind = capture_logger
    logger = Altair::Middleware::Logger.new(SpecApp.instance)
    config = SpecApp.instance.config
    original_logger = config.logger
    original_colors = config.logger_colors
    config.logger = log
    config.logger_colors = false
    request = logger_request("GET", "/posts")
    request.request_id = "req-7"
    begin
      logger.call(request, logger_response, -> { })
      body = io.to_s
      body.should contain("GET")
      body.should contain("/posts")
      body.should contain("200")
      body.should contain("(req-7)")
    ensure
      unbind.call
      config.logger = original_logger
      config.logger_colors = original_colors
    end
  end

  it "highlights slow requests" do
    io, log, unbind = capture_logger
    logger = Altair::Middleware::Logger.new(SpecApp.instance)
    config = SpecApp.instance.config
    original_logger = config.logger
    original_colors = config.logger_colors
    original_threshold = config.slow_request_threshold
    config.logger = log
    config.logger_colors = false
    config.slow_request_threshold = 0.milliseconds
    begin
      logger.call(logger_request("GET", "/slow"), logger_response, -> { sleep 1.millisecond })
      io.to_s.should contain("[SLOW]")
    ensure
      unbind.call
      config.logger = original_logger
      config.logger_colors = original_colors
      config.slow_request_threshold = original_threshold
    end
  end

  it "logs in compact mode without timestamp" do
    io, log, unbind = capture_logger
    logger = Altair::Middleware::Logger.new(SpecApp.instance)
    config = SpecApp.instance.config
    original_logger = config.logger
    original_colors = config.logger_colors
    original_compact = config.logger_compact?
    config.logger = log
    config.logger_colors = false
    config.logger_compact = true
    begin
      logger.call(logger_request("GET", "/compact"), logger_response, -> { })
      body = io.to_s
      body.should contain("GET")
      body.should contain("/compact")
      body.should contain("200")
    ensure
      unbind.call
      config.logger = original_logger
      config.logger_colors = original_colors
      config.logger_compact = original_compact
    end
  end
end
