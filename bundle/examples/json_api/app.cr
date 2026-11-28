# Curated starter example — copied by `altair new --with-examples`.
require "altair"

class JsonApiExampleApp < Altair::Application
  config.name = "JsonApiExample"
  config.port = (ENV["PORT"]? || "3000").to_i
  config.observability = true
  config.cors.origins = ["*"]

  routes do
    get "/api/status" do |_request, response|
      response.json(%({"status":"ok","framework":"altair"}))
    end
  end
end

JsonApiExampleApp.run!
