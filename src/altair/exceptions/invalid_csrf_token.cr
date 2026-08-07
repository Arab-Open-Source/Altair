# Altair — the battery-included web framework for Crystal.
#
# Raised when a state-changing request arrives without a valid
# authenticity token: the CSRF check either found no token at all or the
# submitted token did not match the one in the session. The request
# handler answers it with `422 Unprocessable Entity`.
module Altair
  module HTTP
    class InvalidCsrfToken < Error
      def initialize(message : String = "The authenticity token is missing or invalid")
        super(message, ::HTTP::Status::UNPROCESSABLE_ENTITY)
      end
    end
  end
end
