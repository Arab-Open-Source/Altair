# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Middleware::ConditionalGet`, the opt-in
# automatic ETag middleware. When `config.conditional_get.enabled` is set,
# successful GET/HEAD bodies up to `max_buffer_size` bytes are buffered,
# fingerprinted with SHA-256, and served with a strong `ETag`. A request
# whose `If-None-Match` matches answers `304 Not Modified` with no body.
# Larger, streamed or non-200 responses pass through untouched.
#
# The middleware must wrap the chain *before* anything is written, because
# a 304 can only be decided while the response is still fully in memory.
class Altair::Middleware::ConditionalGet < Altair::Middleware
  # Writes through to the sink once the buffer exceeds its cap; until then
  # the body accumulates so the finished response can be fingerprinted.
  private class BoundedBuffer < IO
    getter overflowed = false
    getter buffer : IO::Memory

    def initialize(@sink : IO, @max_size : Int32)
      @buffer = IO::Memory.new
    end

    def write(slice : Bytes) : Nil
      if @overflowed
        @sink.write(slice)
      elsif @buffer.size + slice.size > @max_size
        @overflowed = true
        @sink.write(@buffer.to_slice)
        @sink.write(slice)
      else
        @buffer.write(slice)
      end
    end

    def read(slice : Bytes) : Nil
      raise IO::Error.new("BoundedBuffer is write-only")
    end
  end

  def call(request : Altair::HTTP::Request, response : Altair::HTTP::Response, chain : Proc(Nil)) : Nil
    return chain.call unless app.config.conditional_get.enabled?
    return chain.call unless {"GET", "HEAD"}.includes?(request.method)

    config = app.config.conditional_get
    raw = response.raw
    sink = raw.output
    buffer = BoundedBuffer.new(sink, config.max_buffer_size)
    raw.output = buffer
    chain.call
    raw.output = sink

    if buffer.overflowed
      # The bytes already streamed through; nothing left to decide.
      return
    end
    unless response.status.ok?
      # Not a cacheable success: replay the buffered body untouched.
      sink.write(buffer.buffer.to_slice)
      return
    end

    etag = Altair::HTTP::ETag.generate(buffer.buffer.to_slice)
    response.headers["ETag"] = etag
    if Altair::HTTP::ETag.matches?(request.headers["If-None-Match"]?, etag)
      response.status = ::HTTP::Status::NOT_MODIFIED
      return
    end

    response.headers["Content-Length"] = buffer.buffer.size.to_s
    sink.write(buffer.buffer.to_slice)
  end
end
