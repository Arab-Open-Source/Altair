# Hello World — a working Altair application.
#
# The application configuration: subclass `Altair::Application`, tune the
# settings, and the framework takes care of the rest. The class body runs at
# compile time, so everything here is checked by the compiler before the
# application ever boots.
class HelloWorld < Altair::Application
  config.name = "Hello World"
  config.port = 3000
end
