# Hello World — a working Altair application.
#
# This is the smallest possible Altair application: an application subclass
# in `config/application.cr`, instance controllers in `app/controllers/`,
# static files in `public/` and a one-line entry point. Run it from this
# directory:
#
# ```
# crystal run src/hello_world.cr
# ```
#
# then open http://localhost:3000 — the pages controller answers, the
# stylesheet is served from `public/` by the static-files middleware, and
# every request is logged. Try:
#
# ```
# curl localhost:3000/
# curl localhost:3000/hello/altair
# curl localhost:3000/css/app.css
# curl localhost:3000/posts
# curl localhost:3000/posts/new
# curl -X POST localhost:3000/posts -d "title=First+post"
# curl localhost:3000/posts/1
# curl localhost:3000/posts/1/edit
# curl -X POST localhost:3000/posts/1 -d "title=Updated&_method=PUT"
# curl -X POST localhost:3000/posts/1 -d "_method=DELETE"
# curl -X POST localhost:3000/posts/5   # → 405 with the Allow header
# curl localhost:3000/nope              # → 404
# ```
require "altair"
require "./config/application"
require "./app/controllers/application_controller"
require "./app/controllers/pages_controller"
require "./app/controllers/posts_controller"

HelloWorld.run!
