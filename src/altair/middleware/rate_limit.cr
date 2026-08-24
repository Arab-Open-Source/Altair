# Altair — the rate-limit middleware.
#
# Enforces the rules declared on `config.rate_limit` before routing. With
# no rules it is a pass-through — the framework pays nothing until an
# application asks to be protected. Allowed responses carry the standard
# `X-RateLimit-Limit` / `-Remaining` / `-Reset` headers; denied ones answer
# 429 with `Retry-After`.
#
# The client key is the connection's remote address by default. When a
# proxy you control sets `X-Forwarded-For`, enable
# `config.rate_limit.trusted_headers` — never trust that header from
# arbitrary clients, they can spoof themselves fresh buckets.
class Altair::Middleware::RateLimit < Altair::Middleware
  @store : Altair::RateLimit::Store?

  def call(request : Altair::HTTP::Request, response : Altair::HTTP::Response, chain : Proc(Nil)) : Nil
    rl = app.config.rate_limit
    return chain.call if rl.empty?

    rule = rl.rule_for(request.path)
    return chain.call unless rule

    hit = store_for(rl).hit(client_key(request), rule.limit, rule.period)
    stamp(response, rule, hit)
    return if hit.allowed

    retry_after = hit.reset_in.ceil.to_i.clamp(1..)
    response.headers["Retry-After"] = retry_after.to_s
    response.status = ::HTTP::Status::TOO_MANY_REQUESTS
    response.text("Too many requests — try again in #{retry_after} second(s).")
  end

  private def stamp(response : Altair::HTTP::Response, rule : Altair::RateLimit::Rule, hit : Altair::RateLimit::Hit) : Nil
    response.headers["X-RateLimit-Limit"] = rule.limit.to_s
    response.headers["X-RateLimit-Remaining"] = hit.remaining.to_s
    response.headers["X-RateLimit-Reset"] = hit.reset_in.ceil.to_i.clamp(0..).to_s
  end

  private def store_for(rl : Altair::Config::RateLimit) : Altair::RateLimit::Store
    @store ||= begin
      case rl.backend
      when :redis
        url = rl.redis_url || ENV["ALTAIR_REDIS_URL"]?
        unless url
          raise Altair::Error.new(
            "rate limit store :redis needs config.rate_limit.redis_url or ENV[\"ALTAIR_REDIS_URL\"]"
          )
        end
        Altair::RateLimit::RedisStore.new(url)
      else
        Altair::RateLimit::MemoryStore.new
      end
    end
  end

  private def client_key(request : Altair::HTTP::Request) : String
    rl = app.config.rate_limit
    if rl.trusted_headers? && (forwarded = request.headers["X-Forwarded-For"]?)
      return forwarded.split(",").first?.to_s.strip
    end
    # IP without the ephemeral port — the port changes per connection and
    # would make every request look like a brand-new client.
    case address = request.remote_address
    when ::Socket::IPAddress then address.address
    when nil                 then "unknown"
    else                          address.to_s
    end
  end
end
