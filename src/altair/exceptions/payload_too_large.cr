# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::HTTP::PayloadTooLarge`, raised when a request
# body exceeds the application's configured `max_body_size`. The request
# wrapper reads the body with the limit applied, so both
# `Content-Length`-carrying and chunked requests are rejected before the
# body ever reaches the router.
module Altair
  module HTTP
    class PayloadTooLarge < Error
      def initialize(message : String = "The request body exceeds the configured limit")
        super(message, ::HTTP::Status::PAYLOAD_TOO_LARGE)
      end
    end
  end
end
