# Hello World — a working Altair application.
#
# This is the smallest possible Altair application: a single application
# subclass in `config/application.cr` and a one-line entry point. Run it from
# this directory:
#
# ```
# crystal run src/hello_world.cr
# ```
#
# then open http://localhost:3000 — you should see the Altair welcome page.
require "../../../src/altair"
require "./config/application"

HelloWorld.run!
