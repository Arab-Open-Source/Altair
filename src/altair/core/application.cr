# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Application`, the heart of every Altair
# application. An application subclasses it in `config/application.cr`,
# configures itself through the `config` accessor and boots with `run!`:
#
# ```
# class Blog < Altair::Application
#   config.name = "Blog"
#   config.port = 3000
# end
#
# Blog.run!
# ```
#
# The class behaves like a conventional application object: `instance`
# returns the single application instance (creating it lazily on first
# access), `config` exposes the configuration and `run!` boots the HTTP
# server. Defining a second application subclass raises
# `Altair::ConfigurationError` — one process runs exactly one application.
module Altair
  @@application_instance : Altair::Application?

  def self.application_instance : Altair::Application?
    @@application_instance
  end

  def self.application_instance=(instance : Altair::Application?) : Altair::Application?
    @@application_instance = instance
  end
end

abstract class Altair::Application
  # The application configuration object.
  getter config : Altair::Config

  # The application root directory, detected from the current working
  # directory at boot time. Override it when the application runs from a
  # different location.
  property root : Path

  # Returns the single application instance, creating it on first access.
  # Subsequent calls return the same object, and calling it through a
  # different application subclass raises `Altair::ConfigurationError`.
  def self.instance : self
    if existing = Altair.application_instance
      unless existing.is_a?(self)
        raise Altair::ConfigurationError.new("an Altair::Application instance has already been created")
      end
      existing
    else
      Altair.application_instance = new
    end
  end

  # The application configuration, accessible from the subclass body
  # (`config.name = "Blog"`) and from anywhere in the application.
  def self.config : Altair::Config
    instance.config
  end

  # The application's registered routes, in definition order. Routes are
  # declared with the `routes` DSL and are fully built when the application
  # class is loaded. The method is named `route_set` so it never clashes
  # with the `routes` DSL macro.
  def self.route_set : Altair::Routing::RouteSet
    Altair::Routing.route_set_for(self)
  end

  # Adds a middleware to the end of the application's middleware stack,
  # from the class body:
  #
  # ```
  # class Blog < Altair::Application
  #   use Altair::Middleware::Logger
  #   use Altair::Middleware::Static
  # end
  # ```
  #
  # The middleware class is expanded at compile time into a factory proc,
  # so middleware may keep any constructor they like.
  macro use(middleware_class)
    config.middleware << ->(app : Altair::Application) { {{ middleware_class }}.new(app) }
  end

  # Registers an application-level exception handler: when an exception of
  # the given class (or a subclass) reaches the request boundary, it is
  # answered with the mapped response instead of a 500. Three forms:
  #
  # ```
  # class Blog < Altair::Application
  #   rescue_from KeyError, to: 422                        # fixed status
  #   rescue_from Post::NotFound, handler: :post_not_found # method on the app
  #   rescue_from Altair::Error do |exception, request, response|
  #     response.status = ::HTTP::Status::BAD_REQUEST
  #     response.text("framework error")
  #   end
  # end
  # ```
  #
  # `handler:` methods and blocks receive `(exception, request, response)`
  # and write to the response themselves. Registrations are checked in
  # declaration order, so list the most specific exceptions first.
  macro rescue_from(exception_class, to = nil, handler = nil, &block)
    {% if block %}
      {% if to || handler %}
        {% raise "rescue_from: a block cannot be combined with `to:` or `handler:`" %}
      {% end %}
      {% if block.args.size != 3 %}
        {% raise "rescue_from: block handlers must declare exactly three parameters — |exception, request, response|" %}
      {% end %}
      Altair::Core::ErrorHandlers.register(
        {{@type}},
        {{ exception_class.id }},
        nil,
        ->(app : Altair::Application, {{ block.args[0].id }} : Exception, {{ block.args[1].id }} : Altair::HTTP::Request?, {{ block.args[2].id }} : Altair::HTTP::Response) {
          {{ block.body }}
        }
      )
    {% else %}
      {% if to && handler %}
        {% raise "rescue_from: give either `to:` or `handler:`, not both" %}
      {% elsif to %}
        Altair::Core::ErrorHandlers.register({{@type}}, {{ exception_class.id }}, ::HTTP::Status.new({{ to }}), nil)
      {% elsif handler %}
        Altair::Core::ErrorHandlers.register(
          {{@type}},
          {{ exception_class.id }},
          nil,
          ->(app : Altair::Application, exception : Exception, request : Altair::HTTP::Request?, response : Altair::HTTP::Response) {
            app.as({{ @type }}).{{ handler.id }}(exception, request, response)
          }
        )
      {% else %}
        {% raise "rescue_from: give `to:`, `handler:` or a block" %}
      {% end %}
    {% end %}
  end

  # Boots the application: builds the server and blocks until it shuts
  # down.
  def self.run! : Nil
    instance.start
  end

  # Boots the HTTP server for this application instance and blocks until
  # the server is closed. Prints the boot banner once, on its own line,
  # before the server starts listening.
  def start : Nil
    handler = Altair::Core::RequestHandler.new(self)
    server = Altair::Server.new(self, handler)
    server.bind
    puts server.banner
    server.start
  end

  # Creates the application instance, wires up the configuration and
  # resolves the root directory. Raises `Altair::ConfigurationError` when
  # an application instance already exists.
  def initialize
    raise Altair::ConfigurationError.new("an Altair::Application instance has already been created") if Altair.application_instance
    @config = Altair::Config.new
    @root = Path.new(Dir.current)
    apply_environment_config
  end

  private def apply_environment_config
    settings = @config.environment(Altair.env)
    @config.debug = settings.debug?
    if limit = settings.max_body_size
      @config.max_body_size = limit
    end
  end
end
