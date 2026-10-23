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

# Global-state isolation between spec files. Files execute alphabetically,
# and the framework's instrumentation hooks (`Record.on_query`,
# `on_checkout`, `on_query_event`) are process-global registries — a
# registration without cleanup kept firing in every later file. Snapshot
# the registries before each example and restore them after, so
# registrations stay scoped to the example that made them. Files that need
# hooks across several examples register inside `before_each` instead.
private module SpecHandlerState
  class_property snapshot : Tuple(Array(Proc(String, Time::Span, Nil)), Array(Proc(Altair::Record::QueryEvent, Nil)), Array(Proc(Proc(Nil), Nil)))?
end

Spec.before_each do
  SpecHandlerState.snapshot = Altair::Record.handlers_snapshot
end

Spec.after_each do
  if snapshot = SpecHandlerState.snapshot
    Altair::Record.restore_handlers(snapshot)
    SpecHandlerState.snapshot = nil
  end
end

class SpecApp < Altair::Application
  config.name = "SpecApp"
  config.db_url = "sqlite3://./spec/record/test.db"
  config.db_max_pool_size = 1
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

  def preview : Nil
  end

  def publish : Nil
  end

  def export : Nil
  end

  def share : Nil
  end

  def review : Nil
  end

  def digest : Nil
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

class AddressesController < StubController
end

class NotesController < StubController
end

class AccountsController < StubController
end

class AvatarsController < StubController
end

class SettingsController < StubController
end

class UsersController < StubController
end

module Admin
  class PostsController < StubController
  end

  class StatsController < StubController
  end

  class ChaptersController < StubController
  end

  class NotesController < StubController
  end

  class ProfilesController < StubController
  end

  class SettingsController < StubController
  end
end

module Api
  module V1
    class UsersController < StubController
    end
  end
end
