Rails.application.routes.draw do
  # Liveness probe used by the runner to wait for readiness.
  get "health" => "items#health", as: :health

  # GET /items/:id — one row by primary key.
  get "items/:id" => "items#show", as: :item

  # POST /items — insert one row from a JSON body.
  post "items" => "items#create", as: :items

  # Reveal health status on /up that returns 200 if the app boots with no
  # exceptions, otherwise 500. Used by load balancers and uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check
end