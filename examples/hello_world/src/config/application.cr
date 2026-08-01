# Hello World — the application configuration.
#
# Subclass `Altair::Application`, tune the settings and declare routes with
# the DSL. The class body runs at compile time, so everything here is
# checked by the compiler before the application ever boots: a typo in
# `to: "pages#hom"` fails to compile, and the generated path helpers are
# real methods.
#
# Routes point at controller actions with typed references
# (`to: PagesController.index`) — rename-safe and compiler-checked — or
# with the classic `"pages#index"` strings. `rescue_from` maps exceptions
# to responses instead of a bare 500.
#
# The default middleware stack (request logging + static files from
# `public/`) is on by default; see the README to customize it.
class HelloWorld < Altair::Application
  config.name = "Hello World"
  config.port = 3000

  rescue_from KeyError, to: 404

  routes do
    root to: PagesController.index
    get "/hello/:name", to: PagesController.hello, named: :greeting
    get "/boom", to: PagesController.boom
    resources :posts
  end
end
