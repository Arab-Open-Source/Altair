# Curated starter example — copied by `altair new --with-examples`.
require "altair"

class HelloExampleApp < Altair::Application
  config.name = "HelloExample"
  config.port = (ENV["PORT"]? || "3000").to_i
  config.observability = true

  routes do
    get "/hello" do |_request, response|
      response.print("Hello from Altair")
    end
  end
end

HelloExampleApp.run!
