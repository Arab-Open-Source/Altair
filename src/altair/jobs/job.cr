# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Jobs::Job`, the base class of background jobs.
# A subclass declares its typed parameters once with `params`; the macro
# generates a typed constructor, a `self.enqueue` / `enqueue_in` /
# `enqueue_at` trio whose arguments are compile-time checked against that
# declaration, and the JSON payload codec the queue persists. Execution
# stays application code: implement `perform`.
#
# ```
# class SendWelcomeEmail < Altair::Jobs::Job
#   params user_id : Int64
#
#   def perform
#     user = User.find!(user_id)
#     # deliver...
#   end
# end
#
# SendWelcomeEmail.enqueue(user_id: 42)
# SendWelcomeEmail.enqueue_in(2.hours, user_id: 42)
# ```
require "json"

module Altair
  module Jobs
    abstract class Job
      # The compiled registry of job classes, keyed by their full class
      # name as stored in payloads. Filled by the `inherited` hook.
      def self.registry : Hash(String, Job.class)
        @@registry ||= {} of String => Job.class
      end

      macro inherited
        Altair::Jobs::Job.registry[{{ @type.name.stringify }}] = {{ @type }}
      end

      # Rebuilds a job instance from a stored payload. Every `params`
      # subclass overrides this; jobs without `params` hit the default
      # below — a clear runtime message instead of a compile-time
      # `Job+.class` virtual-dispatch failure when the worker claims a
      # row while the application defines no jobs (as regression #cm_061
      # proved with `twitter`).
      def self.from_payload(raw : String) : self
        raise Altair::Error.new(
          "#{self} declares no `params` — add a `params` declaration or " \
          "override `#{self}.from_payload`"
        )
      end

      # Declares this job's typed parameters and everything derived from
      # them: accessors, the constructor used by decoding, and the typed
      # `enqueue` family. Supported scalar types are `String`, `Int32`,
      # `Int64`, `Float64` and `Bool`; any other type must respond to
      # `.from_json`.
      #
      # ```
      # params user_id : Int64, email : String
      # ```
      macro params(*declarations)
        {% for decl in declarations %}
          {% unless decl.is_a?(TypeDeclaration) %}
            {% raise "params expects type declarations, e.g. `user_id : Int64`" %}
          {% end %}
          # The parameter's value, fixed for the life of the job instance.
          getter {{ decl.var }} : {{ decl.type }}
        {% end %}

        def initialize(
          {% for index in 0...(declarations.size) %}
            {% decl = declarations[index] %}
            @{{ decl.var }} : {{ decl.type }}{% if index < declarations.size - 1 %},{% end %}
          {% end %}
        )
        end

        # The JSON payload persisted by the queue: one field per parameter,
        # serialized through each value's own `to_json`.
        def payload_json : String
          JSON.build do |json|
            json.object do
              {% for decl in declarations %}
                json.field({{ decl.var.stringify }}) do
                  @{{ decl.var }}.to_json(json)
                end
              {% end %}
            end
          end
        end

        # Rebuilds a job instance from a stored payload.
        def self.from_payload(raw : String) : self
          document = JSON.parse(raw)
          new(
            {% for index in 0...(declarations.size) %}
              {% decl = declarations[index] %}
              __decode({{ decl.type }}, document[{{ decl.var.stringify }}]){% if index < declarations.size - 1 %},{% end %}
            {% end %}
          )
        end

        # Enqueues the job for the earliest possible run on the given queue.
        def self.enqueue(
          {% for index in 0...(declarations.size) %}
            {% decl = declarations[index] %}
            {{ decl.var }} : {{ decl.type }}{% if index < declarations.size - 1 %},{% end %}
          {% end %}
        ) : Int64
          job = new(
            {% for index in 0...(declarations.size) %}
              {% decl = declarations[index] %}
              {{ decl.var }}{% if index < declarations.size - 1 %},{% end %}
            {% end %}
          )
          Altair::Jobs::Queue.enqueue(name, job.payload_json, queue_name)
        end

        # Enqueues the job to run after `duration` has elapsed.
        def self.enqueue_in(duration : Time::Span,
                            {% for index in 0...(declarations.size) %}
                              {% decl = declarations[index] %}
                              {{ decl.var }} : {{ decl.type }}{% if index < declarations.size - 1 %},{% end %}
                            {% end %}
                           ) : Int64
          enqueue_at(Time.utc + duration,
            {% for index in 0...(declarations.size) %}
              {% decl = declarations[index] %}
              {{ decl.var }}{% if index < declarations.size - 1 %},{% end %}
            {% end %}
          )
        end

        # Enqueues the job to run at or after `time`.
        def self.enqueue_at(time : Time,
                            {% for index in 0...(declarations.size) %}
                              {% decl = declarations[index] %}
                              {{ decl.var }} : {{ decl.type }}{% if index < declarations.size - 1 %},{% end %}
                            {% end %}
                           ) : Int64
          job = new(
            {% for index in 0...(declarations.size) %}
              {% decl = declarations[index] %}
              {{ decl.var }}{% if index < declarations.size - 1 %},{% end %}
            {% end %}
          )
          Altair::Jobs::Queue.enqueue(name, job.payload_json, queue_name, run_at: time)
        end
      end

      # Decodes one JSON value into a declared parameter type.
      private macro __decode(type, source)
        {% if type.resolve == String %}
          {{ source }}.as_s
        {% elsif type.resolve == Int32 %}
          {{ source }}.as_i
        {% elsif type.resolve == Int64 %}
          begin
            decoded_any = {{ source }}
            decoded_any.as_i64? || decoded_any.as_i.to_i64
          end
        {% elsif type.resolve == Float64 %}
          {{ source }}.as_f
        {% elsif type.resolve == Bool %}
          {{ source }}.as_bool
        {% else %}
          {{ type }}.from_json(({{ source }}).to_json)
        {% end %}
      end

      # The job body. Runs inside the worker fiber; any raise marks the
      # execution failed and schedules a retry until the attempt budget is
      # spent.
      abstract def perform : Nil

      # The fully qualified name recorded in payloads and the registry.
      def self.name : String
        {{ @type.name.stringify }}
      end

      # The queue this job enqueues onto. Override for dedicated queues.
      def self.queue_name : String
        "default"
      end

      # The attempt budget before the job is parked as failed. Defaults to
      # the worker configuration; override per job to tighten or widen it.
      def self.max_attempts : Int32
        Altair.application_instance.try(&.config.jobs_max_attempts) || 5
      end
    end
  end
end
