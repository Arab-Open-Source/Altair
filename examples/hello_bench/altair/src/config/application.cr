class HelloBench < Altair::Application
  config.name = "Hello Bench"
  config.port = ENV["PORT"]?.try(&.to_i) || 4202

  routes do
    root to: HelloController.index
  end
end
