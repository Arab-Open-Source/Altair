# Altair — the batteries-included web framework for Crystal.
#
# Raised when a request must carry an authenticated identity but does not —
# the server-side companion to the `authenticate!` controller helper. The
# request handler answers it with `401 Unauthorized`.
module Altair
  module HTTP
    class Unauthorized < Error
      def initialize(message : String = "Authentication is required")
        super(message, ::HTTP::Status::UNAUTHORIZED)
      end
    end
  end
end
