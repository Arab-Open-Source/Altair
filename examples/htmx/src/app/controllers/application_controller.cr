# htmx — the shared controller base.
#
# One line includes the generated route helpers, so actions can call
# `tasks_path` and `task_path(id)` bare.
abstract class ApplicationController < Altair::Controller
  include HtmxApp::RouteHelpers
end
