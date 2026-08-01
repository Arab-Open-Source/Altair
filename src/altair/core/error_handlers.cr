# Altair — application-level exception handlers.
#
# `Altair::Core::ErrorHandlers` is the registry behind the `rescue_from`
# application DSL. Every registration pairs an exception class with a
# response: a fixed status, a handler method on the application, or a
# block. The registry is class-level and global to the process — one
# application runs per process — and is read by the request handler when
# an unhandled exception reaches the application boundary.
module Altair
  module Core
    module ErrorHandlers
      # The handler signature: the application instance (so handler
      # methods can be invoked on it), the exception, the framework
      # request (nil when the failure happened before the request could
      # be read) and the response wrapper the handler writes to.
      alias Handler = Proc(Altair::Application, Exception, Altair::HTTP::Request?, Altair::HTTP::Response, Nil)

      # A single `rescue_from` registration. Exactly one of `status` or
      # `handler` is set.
      record Registration,
        exception_class : Exception.class,
        status : ::HTTP::Status?,
        handler : Handler?

      @@registrations = [] of Registration

      # Registers an exception class to be handled by `status` or by
      # `handler`. Called by the `rescue_from` macro at class-load time.
      def self.register(exception_class : Exception.class, status : ::HTTP::Status? = nil, handler : Handler? = nil) : Nil
        @@registrations << Registration.new(exception_class, status, handler)
      end

      # All registered handlers, in declaration order. Registrations are
      # checked from first to last, so applications list the most specific
      # exceptions first.
      def self.registrations : Array(Registration)
        @@registrations
      end
    end
  end
end
