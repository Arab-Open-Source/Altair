# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Record::NDetector`, the development-mode N+1
# detector. It watches the `Altair::Record.on_query` hook for the same SQL
# firing repeatedly within one request — the signature of lazy association
# access inside a loop — and logs a warning once a statement passes the
# configured threshold. The detector only arms itself when the active
# environment is Development and `config.detect_n_plus_one` is enabled, so
# production servers never register the hook or pay its per-statement
# timing. Every value travels as a bind parameter, so a loop always fires
# the identical SQL string — that string is what the detector counts.
module Altair
  module Record
    class NDetector
      @@enabled = false
      @@registered = false
      @@threshold = 3
      @@lock = Mutex.new
      @@counts = {} of Fiber => Hash(String, Int32)

      # Whether the detector is currently armed.
      def self.enabled? : Bool
        @@enabled
      end

      # Arms the detector when the environment and configuration allow it,
      # registering the query hook once. Called whenever a request handler
      # is built for an application.
      def self.enable(env : Altair::Env, detect : Bool, threshold : Int32) : Nil
        @@lock.synchronize do
          @@threshold = threshold
          @@enabled = env.development? && detect && threshold > 0
          register if @@enabled && !@@registered
        end
      end

      # Starts a fresh counting window for the calling fiber's request.
      def self.begin_request : Nil
        return unless @@enabled
        @@lock.synchronize { @@counts[Fiber.current] = Hash(String, Int32).new(0) }
      end

      # Closes the counting window for the calling fiber's request.
      def self.end_request : Nil
        return unless @@enabled
        @@lock.synchronize { @@counts.delete(Fiber.current) }
      end

      private def self.register : Nil
        Altair::Record.on_query do |sql, _duration|
          if @@enabled
            if counts = @@lock.synchronize { @@counts[Fiber.current]? }
              n = counts[sql] += 1
              if n == @@threshold
                Log.for("altair.record").warn do
                  "likely N+1: the same SQL ran #{n} times in one request " \
                  "— eager load it with `includes` (#{sql})"
                end
              end
            end
          end
        end
        @@registered = true
      end
    end
  end
end
