# Altair — the batteries-included web framework for Crystal.
#
# Specs for the middleware chain contract: middlewares run in order, each
# may short-circuit the chain, and exceptions from inner middlewares
# propagate outwards.
require "../spec_helper"

private class TraceMiddleware < Altair::Middleware
  def initialize(app, @label : String, @trace : Array(String))
    super(app)
  end

  def call(request : Altair::HTTP::Request, response : Altair::HTTP::Response, chain : Proc(Nil)) : Nil
    @trace << "#{@label}:before"
    chain.call
    @trace << "#{@label}:after"
  end
end

private class BlockingMiddleware < Altair::Middleware
  def initialize(app, @trace : Array(String))
    super(app)
  end

  def call(request : Altair::HTTP::Request, response : Altair::HTTP::Response, chain : Proc(Nil)) : Nil
    @trace << "blocking"
  end
end

private class RaisingMiddleware < Altair::Middleware
  def call(request : Altair::HTTP::Request, response : Altair::HTTP::Response, chain : Proc(Nil)) : Nil
    raise "boom"
  end
end

private def middleware_request : Altair::HTTP::Request
  Altair::HTTP::Request.new(HTTP::Request.new("GET", "/"))
end

private def middleware_response : Altair::HTTP::Response
  Altair::HTTP::Response.new(HTTP::Server::Response.new(IO::Memory.new))
end

describe Altair::Middleware do
  it "runs middlewares in order, around the final handler" do
    trace = [] of String
    first = TraceMiddleware.new(SpecApp.instance, "first", trace)
    second = TraceMiddleware.new(SpecApp.instance, "second", trace)

    first.call(middleware_request, middleware_response, -> {
      second.call(middleware_request, middleware_response, -> { trace << "final" })
    })

    trace.should eq(["first:before", "second:before", "final", "second:after", "first:after"])
  end

  it "composes the configured stack around the final handler" do
    trace = [] of String
    stack = [
      ->(app : Altair::Application) { TraceMiddleware.new(app, "first", trace) },
      ->(app : Altair::Application) { TraceMiddleware.new(app, "second", trace) },
    ]
    final = ->(_request : Altair::HTTP::Request, _response : Altair::HTTP::Response) { trace << "final" }

    chain = stack.reverse.reduce(final) do |inner, factory|
      middleware = factory.call(SpecApp.instance)
      ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
        middleware.call(request, response, -> { inner.call(request, response) })
      }
    end

    chain.call(middleware_request, middleware_response)
    trace.should eq(["first:before", "second:before", "final", "second:after", "first:after"])
  end

  it "lets a middleware short-circuit the chain" do
    trace = [] of String
    blocker = BlockingMiddleware.new(SpecApp.instance, trace)
    downstream = TraceMiddleware.new(SpecApp.instance, "downstream", trace)

    blocker.call(middleware_request, middleware_response, -> {
      downstream.call(middleware_request, middleware_response, -> { trace << "final" })
    })

    trace.should eq(["blocking"])
  end

  it "propagates exceptions raised by inner middlewares" do
    raiser = RaisingMiddleware.new(SpecApp.instance)
    expect_raises(Exception, "boom") do
      raiser.call(middleware_request, middleware_response, -> { raise "unreachable" })
    end
  end

  it "exposes the application" do
    TraceMiddleware.new(SpecApp.instance, "x", [] of String).app.should be(SpecApp.instance)
  end
end
