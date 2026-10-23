# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Middleware::Compression`, the opt-in response
# compression middleware. When `config.compression.enabled` is set it
# negotiates `Accept-Encoding` and swaps the response output for a gzip or
# deflate writer before the chain renders, so routed responses and static
# files alike leave the server compressed. Framework-generated error pages
# bypass the middleware chain entirely and are never compressed.
#
# Defaults are safe: the middleware is off until enabled, and a client that
# sends no `Accept-Encoding` gets an uncompressed response.
require "compress/gzip"
require "compress/zlib"

class Altair::Middleware::Compression < Altair::Middleware
  def call(request : Altair::HTTP::Request, response : Altair::HTTP::Response, chain : Proc(Nil)) : Nil
    if (encoding = negotiate(request.headers["Accept-Encoding"]?)) && app.config.compression.enabled?
      response.headers["Content-Encoding"] = encoding
      vary = response.headers.get?("Vary")
      if vary.nil? || !vary.includes?("Accept-Encoding")
        response.headers.add("Vary", "Accept-Encoding")
      end
      raw = response.raw
      raw.output = wrap(raw.output, encoding)
    end
    chain.call
  end

  private def negotiate(accept_encoding : String?) : String?
    return nil unless accept_encoding
    return nil if accept_encoding =~ /\bgzip\s*;\s*q\s*=\s*0(?:\.0+)?\b/
    return "gzip" if accept_encoding =~ /\bgzip\b/
    return nil if accept_encoding =~ /\bdeflate\s*;\s*q\s*=\s*0(?:\.0+)?\b/
    return "deflate" if accept_encoding =~ /\bdeflate\b/
    nil
  end

  private def wrap(output : IO, encoding : String) : IO
    level = app.config.compression.level
    case encoding
    when "gzip"
      if level
        ::Compress::Gzip::Writer.new(output, level: level, sync_close: true)
      else
        ::Compress::Gzip::Writer.new(output, sync_close: true)
      end
    else
      if level
        ::Compress::Zlib::Writer.new(output, level: level, sync_close: true)
      else
        ::Compress::Zlib::Writer.new(output, sync_close: true)
      end
    end
  end
end
