# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::HTTP::MethodNotAllowed`, raised by the router
# when a request path matches a registered route but the HTTP method is not
# accepted by that route — for example, a `POST` request to a path that only
# accepts `GET`. The exception carries the list of allowed methods so the
# response can include a proper `Allow` header.
module Altair
  module HTTP
    class MethodNotAllowed < Altair::HTTP::Error
      # The HTTP methods accepted by the matched path.
      getter allowed : Array(String)

      def initialize(@allowed : Array(String), message : String = "The request method is not allowed for this resource")
        super(message, ::HTTP::Status::METHOD_NOT_ALLOWED)
      end
    end
  end
end
