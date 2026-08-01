# Hello World — a working Altair application.
#
# This is the smallest possible Altair application: an application subclass
# in `config/application.cr` with a few routes, controllers in
# `app/controllers/` and a one-line entry point. Run it from this directory:
#
# ```
# crystal run src/hello_world.cr
# ```
#
# then open http://localhost:3000 — you should see the pages controller
# answer. Try:
#
# ```
# curl localhost:3000/hello/altair
# curl localhost:3000/posts
# curl localhost:3000/posts/5
# curl localhost:3000/posts/5/edit
# curl -X POST localhost:3000/posts/5   # → 405 with the Allow header
# curl localhost:3000/nope              # → 404
# ```
require "../../../src/altair"
require "./config/application"
require "./app/controllers/pages_controller"
require "./app/controllers/posts_controller"

HelloWorld.run!
