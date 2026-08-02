# htmx — an Altair application that never reloads the page.
#
# This example shows the Phase 3 view stack in the browser: `.ecr` views
# compiled by the `templates` macro, escaping by default, layouts with
# `yield`, partials and the helpers — plus the framework's htmx layer
# (fragment rendering, `hx_*` attributes and `HX-Trigger`). Every action
# answers with a fragment when the request carries `HX-Request` and with a
# full page otherwise, so the app works with or without JavaScript. Run it
# from this directory:
#
# ```
# crystal run src/htmx.cr
# ```
#
# then open http://localhost:3001. Add, edit and delete tasks — the list
# swaps in place, nothing reloads.
require "altair"
require "./config/application"
require "./app/controllers/application_controller"
require "./app/controllers/tasks_controller"

HtmxApp.run!
