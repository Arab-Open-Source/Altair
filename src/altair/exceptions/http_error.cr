# Altair — the HTTP exception hierarchy.
#
# This file defines the HTTP exception hierarchy. `Altair::HTTP::Error` is
# the base class for every HTTP-level error and carries the `HTTP::Status`
# that should be sent back to the client. `Altair::HTTP::NotFound` is the
# canonical "resource does not exist" error. `Altair::HTTP::ParamsError`
# signals a parameter that is missing, malformed or not of the expected
# type — raised by the typed `Params#fetch` overloads.
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

    class ParamsError < Error
      def initialize(message : String)
        super(message, ::HTTP::Status::UNPROCESSABLE_ENTITY)
      end
    end
  end
end
