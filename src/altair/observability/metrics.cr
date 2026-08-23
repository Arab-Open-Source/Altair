# Altair — request metrics.
module Altair
  module Observability
    # Process-local counters exposed through the optional metrics endpoint.
    class Metrics
      @requests = Atomic(Int64).new(0_i64)
      @errors = Atomic(Int64).new(0_i64)
      @duration_us = Atomic(Int64).new(0_i64)

      # Records one completed HTTP request.
      def record(status : Int32, elapsed : Time::Span) : Nil
        @requests.add(1_i64)
        @errors.add(1_i64) if status >= 500
        @duration_us.add(elapsed.total_microseconds.to_i64)
      end

      # Renders the counters in the Prometheus text exposition format.
      def to_prometheus : String
        String.build do |io|
          io << "# TYPE altair_http_requests_total counter\n"
          io << "altair_http_requests_total " << @requests.get << '\n'
          io << "# TYPE altair_http_server_errors_total counter\n"
          io << "altair_http_server_errors_total " << @errors.get << '\n'
          io << "# TYPE altair_http_request_duration_microseconds_total counter\n"
          io << "altair_http_request_duration_microseconds_total " << @duration_us.get << '\n'
        end
      end

      # Clears counters, primarily for isolated test examples.
      def reset! : Nil
        @requests.set(0_i64)
        @errors.set(0_i64)
        @duration_us.set(0_i64)
      end
    end

    METRICS = Metrics.new

    # The process-local metrics registry.
    def self.metrics : Metrics
      METRICS
    end
  end
end
