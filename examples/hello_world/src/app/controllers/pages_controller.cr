# Hello World — the pages controller.
#
# Controllers are plain classes with class methods, one per action, each
# receiving the framework's request and response wrappers. Real controller
# dispatch arrives in a later phase; for now this shows the contract.
class PagesController
  def self.index(request : Altair::HTTP::Request, response : Altair::HTTP::Response) : Nil
    response.html("<h1>Welcome to Hello World</h1><p>Altair is running.</p>")
  end

  def self.hello(request : Altair::HTTP::Request, response : Altair::HTTP::Response) : Nil
    name = request.params["name"]
    response.html("<h1>Hello, #{name}!</h1><p>You are on the greeting page.</p>")
  end
end
