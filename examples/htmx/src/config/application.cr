# htmx — the application configuration.
#
# The only routes are the ones the demo needs: the index page, and the
# create / edit / destroy flows that htmx drives with fragments. Routes
# use typed references to the controller actions, so renaming an action
# breaks the build instead of the page. A `KeyError` — a missing `id`,
# say — becomes a 404.
class HtmxApp < Altair::Application
  config.name = "Altair + htmx demo"
  config.port = 3001

  rescue_from KeyError, to: 404

  routes do
    root to: TasksController.index
    post "/tasks", to: TasksController.create
    get "/tasks/:id/edit", to: TasksController.edit
    post "/tasks/:id", to: TasksController.update
    delete "/tasks/:id", to: TasksController.destroy
  end
end
