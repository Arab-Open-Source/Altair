# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Jobs::Queue`, the persistence and claiming
# layer for background jobs. Jobs live in an `altair_jobs` table created
# lazily on first use (the same pattern as `schema_migrations`), every
# value binds as a parameter, and claiming is a conditional `UPDATE` so
# concurrent workers can never run the same row twice. A test mode swaps
# the table for an in-memory list drained synchronously in specs.
require "json"

module Altair
  module Jobs
    # Enqueues, claims and completes jobs. The steady path talks to the
    # application's database through `Altair::Record.connection`.
    class Queue
      record PendingCall, job_name : String, payload : String, queue : String, run_at : Time

      # Whether enqueues collect in memory for specs instead of the table.
      class_property? test_mode : Bool = false

      # The in-memory inbox used by test mode.
      def self.enqueued : Array(PendingCall)
        @@enqueued ||= [] of PendingCall
      end

      def self.clear_enqueued! : Nil
        enqueued.clear
      end

      # Creates the jobs table when missing. Idempotent and cheap; called
      # by the enqueue/claim paths so projects never migrate for jobs.
      private def self.ensure_table : Nil
        connection.exec(
          "CREATE TABLE IF NOT EXISTS altair_jobs (" \
          "id INTEGER PRIMARY KEY AUTOINCREMENT, " \
          "job_class TEXT NOT NULL, payload TEXT NOT NULL, " \
          "queue TEXT NOT NULL DEFAULT 'default', " \
          "run_at TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending', " \
          "attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, " \
          "created_at TEXT, updated_at TEXT)"
        )
      end

      # Inserts one job row, due immediately unless `run_at` is given.
      # Returns the row id.
      def self.enqueue(job_class : String, payload : String,
                       queue : String = "default", run_at : Time = Time.utc) : Int64
        if test_mode?
          enqueued << PendingCall.new(job_class, payload, queue, run_at)
          return -(enqueued.size.to_i64)
        end
        ensure_table
        now = Time.utc.to_s("%FT%T.%9NZ")
        result = connection.exec(
          "INSERT INTO altair_jobs (job_class, payload, queue, run_at, status, attempts, created_at, updated_at) " \
          "VALUES (?, ?, ?, ?, 'pending', 0, ?, ?)",
          job_class, payload, queue, run_at.to_s("%FT%T.%9NZ"), now, now
        )
        connection.last_insert_id(result)
      end

      # Atomically claims the oldest pending, due job from the given
      # queues: only the worker whose conditional `UPDATE` affects one row
      # runs it. Returns nil when nothing is claimable.
      def self.claim(queues : Array(String), now : Time = Time.utc) : ClaimedJob?
        ensure_table
        placeholders = queues.map_with_index { |_q, index| adapter.placeholder(index + 2) }
        loop do
          candidate = connection.query_one?(
            "SELECT id, job_class, payload FROM altair_jobs " \
            "WHERE status = 'pending' AND run_at <= #{adapter.placeholder(0)} " \
            "AND queue IN (#{placeholders.join(", ")}) ORDER BY id LIMIT 1",
            values: [now.to_s("%FT%T.%9NZ")] + queues
          ) do |rs|
            {id: rs.read(Int64), job_class: rs.read(String), payload: rs.read(String)}
          end
          return nil unless candidate

          claimed = connection.exec(
            "UPDATE altair_jobs SET status = 'running', updated_at = #{adapter.placeholder(0)} " \
            "WHERE id = #{adapter.placeholder(1)} AND status = 'pending'",
            now.to_s("%FT%T.%9NZ"), candidate[:id]
          )
          if claimed.rows_affected == 1
            return ClaimedJob.new(candidate[:id], candidate[:job_class], candidate[:payload])
          end
          # Another worker won this row between SELECT and UPDATE; look again.
        end
      end

      # Marks a claimed job done.
      def self.complete(id : Int64) : Nil
        return if test_mode?
        connection.exec(
          "UPDATE altair_jobs SET status = 'done', updated_at = ? WHERE id = ?",
          Time.utc.to_s("%FT%T.%9NZ"), id
        )
      end

      # Records a failure: schedules the retry with exponential backoff
      # while the attempt budget lasts, then parks the job as failed.
      def self.fail(id : Int64, error : Exception, max_attempts : Int32) : Nil
        return if test_mode?
        row = connection.query_one?(
          "SELECT attempts FROM altair_jobs WHERE id = ?", id
        ) { |rs| rs.read(Int32) }
        return unless row
        attempts = row + 1
        if attempts >= max_attempts
          connection.exec(
            "UPDATE altair_jobs SET status = 'failed', attempts = ?, last_error = ?, updated_at = ? WHERE id = ?",
            attempts, "#{error.class}: #{error.message}", Time.utc.to_s("%FT%T.%9NZ"), id
          )
        else
          backoff = Retry.backoff(attempts)
          retry_at = (Time.utc + backoff).to_s("%FT%T.%9NZ")
          connection.exec(
            "UPDATE altair_jobs SET status = 'pending', attempts = ?, run_at = ?, last_error = ?, updated_at = ? WHERE id = ?",
            attempts, retry_at, "#{error.class}: #{error.message}", Time.utc.to_s("%FT%T.%9NZ"), id
          )
        end
      end

      # Status counts for observability (`{"pending" => 3, ...}`).
      def self.stats(queues : Array(String)? = nil) : Hash(String, Int64)
        ensure_table
        counts = Hash(String, Int64).new(0)
        sql = "SELECT status, COUNT(*) FROM altair_jobs"
        args = [] of String
        if queues && !queues.empty?
          placeholders = queues.map_with_index { |_q, index| adapter.placeholder(index + 1) }
          sql += " WHERE queue IN (#{placeholders.join(", ")})"
          queues.each { |q| args << q }
        end
        sql += " GROUP BY status"
        connection.query(sql, values: args.empty? ? nil : args) do |rs|
          rs.each do
            status = rs.read(String)
            count = rs.read(Int64)
            counts[status] = count
          end
        end
        counts
      end

      private def self.connection : Altair::Record::Connection
        Altair::Record.connection
      end

      private def self.adapter
        connection.adapter
      end
    end

    # One job claimed by a worker, carrying its stored payload.
    record ClaimedJob, id : Int64, job_class : String, payload : String

    # Retry scheduling helpers shared by the queue and worker.
    module Retry
      # Exponential backoff with a floor of one second and a cap of five
      # minutes: attempt 1 retries in 2s, attempt 2 in 4s, ...
      def self.backoff(failed_attempts : Int32, base : Time::Span = 2.seconds,
                       cap : Time::Span = 5.minutes) : Time::Span
        span = base * (2**(failed_attempts - 1))
        span > cap ? cap : span
      end
    end
  end
end
