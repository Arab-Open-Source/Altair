# Altair — application-level exception handlers.
#
# `Altair::Core::ErrorHandlers` is the registry behind the `rescue_from`
# application DSL. Every registration pairs an exception class with a
# response: a fixed status, a handler method on the application, or a
# block. Registrations are stored **per application class** — one
# application runs per process, but the isolation means several application
# classes (as in the test suite) never leak handlers into each other. The
# request handler reads its own application's registrations when an
# unhandled exception reaches the application boundary.
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
        app_class : Altair::Application.class,
        exception_class : Exception.class,
        status : ::HTTP::Status?,
        handler : Handler?

      @@registrations = [] of Registration

      # Registers an exception class to be handled by `status` or by
      # `handler`, scoped to the given application class. Called by the
      # `rescue_from` macro at class-load time.
      def self.register(klass : Altair::Application.class, exception_class : Exception.class, status : ::HTTP::Status? = nil, handler : Handler? = nil) : Nil
        @@registrations << Registration.new(klass, exception_class, status, handler)
      end

      # The application's registered handlers, in declaration order.
      # Registrations are checked from first to last, so applications list
      # the most specific exceptions first.
      def self.registrations(klass : Altair::Application.class) : Array(Registration)
        @@registrations.select { |registration| registration.app_class == klass }
      end

      # Removes every registration the application class holds. Test-only
      # helper for re-defining an application between specs without
      # leaking registrations.
      def self.reset(klass : Altair::Application.class) : Nil
        @@registrations.reject! { |registration| registration.app_class == klass }
      end
    end
  end
end
