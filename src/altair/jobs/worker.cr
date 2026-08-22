# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Jobs::Worker`, the long-running loop that
# claims due jobs from the queue and executes them. Each claimed row runs
# exactly once (the queue's conditional update guarantees it), failures
# retry with exponential backoff inside the job's attempt budget, and the
# loop parks between empty polls, waking on shutdown signals.
module Altair
  module Jobs
    class Worker
      @stopped = false

      getter poll_interval : Time::Span
      getter queues : Array(String)

      def initialize(@poll_interval : Time::Span = 1.second,
                     @queues : Array(String) = ["default"])
      end

      # Runs the worker until `stop` is called. Blocks the calling fiber.
      def run : Nil
        install_signal_handlers
        Log.for("altair.jobs").info { "worker started on queues #{queues.join(", ")}" }
        until @stopped
          worked = work_one
          sleep(poll_interval) unless worked
        end
        Log.for("altair.jobs").info { "worker stopped" }
      end

      # Claims and executes at most one job. Returns whether a job was
      # found — callers use it to decide whether to poll again immediately
      # or park. Specs drive this directly instead of spinning `run`.
      def work_one : Bool
        return false if @stopped
        claimed = Queue.claim(queues)
        return false unless claimed

        execute(claimed)
        true
      end

      # Requests a graceful stop; the current job finishes first.
      def stop : Nil
        @stopped = true
      end

      # Executes one claimed job: decode through the registry, call
      # `perform`, then mark done — or record the failure for retry.
      def execute(claimed : ClaimedJob) : Nil
        klass = Job.registry[claimed.job_class]?
        unless klass
          Log.for("altair.jobs").error { "unknown job class #{claimed.job_class} (job ##{claimed.id})" }
          Queue.fail(claimed.id, Altair::Error.new("unknown job class #{claimed.job_class}"), 1)
          return
        end

        job = klass.from_payload(claimed.payload)
        started = Time.instant
        job.perform
        Queue.complete(claimed.id)
        Log.for("altair.jobs").info do
          "#{claimed.job_class} finished in #{Time.instant - started} (job ##{claimed.id})"
        end
      rescue ex
        budget = klass ? klass.max_attempts : 1
        Queue.fail(claimed.id, ex, budget)
        Log.for("altair.jobs").warn do
          "#{claimed.job_class} failed (#{ex.class}: #{ex.message}) — retry scheduled (job ##{claimed.id})"
        end
      end

      private def install_signal_handlers : Nil
        Signal::INT.trap { stop }
        Signal::TERM.trap { stop }
      end
    end
  end
end
