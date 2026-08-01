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
    SpecApp.instance.config.logger = log
    begin
      logger.call(logger_request("GET", "/posts"), logger_response(::HTTP::Status::NOT_FOUND), -> { })
      io.to_s.should contain("GET /posts -> 404")
    ensure
      unbind.call
      SpecApp.instance.config.logger = Log.for("altair")
    end
  end

  it "runs the chain before logging" do
    io, log, unbind = capture_logger
    logger = Altair::Middleware::Logger.new(SpecApp.instance)
    SpecApp.instance.config.logger = log
    ran = false
    begin
      logger.call(logger_request("POST", "/books"), logger_response(::HTTP::Status::CREATED), -> { ran = true })
      ran.should be_true
      io.to_s.should contain("POST /books -> 201")
    ensure
      unbind.call
      SpecApp.instance.config.logger = Log.for("altair")
    end
  end
end
