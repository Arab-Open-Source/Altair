# htmx — the application configuration.
#
# The only routes are the ones the demo needs: the index page, and the
# create / edit / destroy flows that htmx drives with fragments.
class HtmxApp < Altair::Application
  config.name = "Altair + htmx demo"
  config.port = 3001

  routes do
    root to: "tasks#index"
    post "/tasks", to: "tasks#create"
    get "/tasks/:id/edit", to: "tasks#edit"
    post "/tasks/:id", to: "tasks#update"
    delete "/tasks/:id", to: "tasks#destroy"
  end
end
