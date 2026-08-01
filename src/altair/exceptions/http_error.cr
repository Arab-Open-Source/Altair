# Altair — the batteries-included web framework for Crystal.
#
# This file defines the HTTP exception hierarchy. `Altair::HTTP::Error` is
# the base class for every HTTP-level error and carries the `HTTP::Status`
# that should be sent back to the client. `Altair::HTTP::NotFound` is the
# canonical "resource does not exist" error and will be raised by the router
# once routing lands in a later phase.
module Altair
  module HTTP
    class Error < Altair::Error
      getter status : ::HTTP::Status

      def initialize(message : String, @status : ::HTTP::Status)
        super(message)
      end
    end

    class NotFound < Error
      def initialize(message : String = "The requested resource could not be found")
        super(message, ::HTTP::Status::NOT_FOUND)
      end
    end
  end
end
