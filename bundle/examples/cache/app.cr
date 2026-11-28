# Curated starter example — copied by `altair new --with-examples`.
require "altair"

class CacheExampleApp < Altair::Application
  config.name = "CacheExample"
  config.port = (ENV["PORT"]? || "3000").to_i
  config.observability = true

  routes do
    get "/cached" do |_request, response|
      greeting = Altair.cache.fetch("greeting", expires_in: 60.seconds) { "Hello from cache" }
      response.print(greeting)
    end
  end
end

CacheExampleApp.run!
