# Altair — the batteries-included web framework for Crystal.
#
# Shared setup for the framework's test suite. The suite pins the active
# environment to `Test` and defines `SpecApp`, the single application used
# across all specs — mirroring how a real Altair project defines its one and
# only application subclass.
require "spec"
require "http/client"
require "../src/altair"

Altair.env = Altair::Env::Test

class SpecApp < Altair::Application
  config.name = "SpecApp"
end

# Compile-time stubs for the routing DSL specs. The DSL wires routes to
# controller classes (`posts#show` dispatches
# `PostsController.new(request, response).show`); the specs only inspect
# route registration and the generated helpers, so the actions are defined
# but never invoked. Real controller dispatch is covered by the controller
# specs.
abstract class StubController < Altair::Controller
  def index : Nil
  end

  def show : Nil
  end

  def new : Nil
  end

  def create : Nil
  end

  def edit : Nil
  end

  def update : Nil
  end

  def destroy : Nil
  end

  def hello : Nil
  end

  def about : Nil
  end

  def dashboard : Nil
  end
end

class PagesController < StubController
end

class RegistryController < StubController
end

class PostsController < StubController
end

class ArticlesController < StubController
end

class CommentsController < StubController
end

class PeopleController < StubController
end

class ChaptersController < StubController
end

class FilesController < StubController
end

class StatsController < StubController
end

module Admin
  class PostsController < StubController
  end

  class StatsController < StubController
  end
end

module Api
  module V1
    class UsersController < StubController
    end
  end
end
