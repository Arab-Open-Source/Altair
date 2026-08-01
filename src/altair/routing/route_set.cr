# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Routing::RouteSet`, the collection of routes
# belonging to one application class, and the registry that maps every
# `Altair::Application` subclass to its own route set. Routes are
# registered while the application class body is evaluated — before any
# request arrives — so registration is lock-free. Registering the same
# method and pattern twice raises `Altair::ConfigurationError`.
module Altair
  module Routing
    @@route_sets = {} of Altair::Application.class => RouteSet

    # Returns the route set belonging to the given application class,
    # creating it on first access.
    def self.route_set_for(klass : Altair::Application.class) : RouteSet
      @@route_sets[klass] ||= RouteSet.new
    end

    class RouteSet
      # The registered routes, in definition order.
      getter routes : Array(Route) = [] of Route

      # Registers a route and returns it. Raises
      # `Altair::ConfigurationError` when a route with the same method
      # and pattern is already registered.
      def register(method : String, pattern : String, handler : Route::Handler, action : String? = nil, name : String? = nil) : Route
        if @routes.any? { |route| route.method == method && route.pattern == pattern }
          raise Altair::ConfigurationError.new("duplicate route: #{method} #{pattern}")
        end
        route = Route.new(method: method, pattern: pattern, handler: handler, action: action, name: name)
        @routes << route
        route
      end
    end
  end
end
