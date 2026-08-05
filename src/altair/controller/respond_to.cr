# Altair — format-aware responses.
#
# `Altair::Controller::FormatResponder` backs the controller's `respond_to`
# helper: an action declares one block per format it can serve, and the
# requested format (`request.format`: path suffix, then `Accept`, then
# `:html`) picks which block runs. Formats with no block answer 406
# Not Acceptable.
module Altair
  abstract class Controller
    # Collects format handlers inside a `respond_to` block; `answer` runs
    # the one matching `request.format`.
    class FormatResponder
      @handlers = {} of Symbol => Proc(Nil)

      def initialize(@request : Altair::HTTP::Request, @response : Altair::HTTP::Response)
      end

      # Registers a handler for the `html` format.
      def html(&block : -> Nil) : Nil
        @handlers[:html] = block
      end

      # Registers a handler for the `json` format.
      def json(&block : -> Nil) : Nil
        @handlers[:json] = block
      end

      # Registers a handler for the `text` format.
      def text(&block : -> Nil) : Nil
        @handlers[:text] = block
      end

      # Runs the handler for the requested format, answering 406 Not
      # Acceptable when none was declared for it.
      def answer : Nil
        if handler = @handlers[@request.format]?
          handler.call
        else
          @response.status = ::HTTP::Status::NOT_ACCEPTABLE
        end
      end
    end
  end
end
