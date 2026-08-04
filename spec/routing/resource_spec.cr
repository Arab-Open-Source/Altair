# Altair — the batteries-included web framework for Crystal.
#
# Specs for `resource`, the singular resource declaration. `resource
# :profile` expands to the six standard actions on `/profile` — no index,
# no `:id` — dispatching to the plural `ProfilesController`, and generates
# the no-argument helpers `profile_path`, `new_profile_path` and
# `edit_profile_path`. Member and collection routes inside the block carry
# no id; nested resources hang off the singular path without a parent
# parameter. Covers registration, helpers, `only:` / `except:`, namespaces,
# nesting and real HTTP dispatch.
require "../spec_helper"

class ResourceApp < Altair::Application
  routes do
    resource :profile
    resource :account, only: [:show, :edit] do
      member do
        get :preview
      end
      collection do
        get :export
      end
      resources :comments, only: [:index, :create]
    end
    resource :settings, except: :destroy
    namespace :admin do
      resource :profile
    end
    resources :users do
      resource :avatar
    end
  end
end

describe "singular resource" do
  it "registers the six routes without an index or an id" do
    ResourceApp.route_set.routes.select(&.pattern.starts_with?("/profile")).map do |route|
      "#{route.method} #{route.pattern} -> #{route.action}"
    end.should eq([
      "GET /profile/new -> profiles#new",
      "POST /profile -> profiles#create",
      "GET /profile -> profiles#show",
      "GET /profile/edit -> profiles#edit",
      "PUT /profile -> profiles#update",
      "PATCH /profile -> profiles#update",
      "DELETE /profile -> profiles#destroy",
    ])
  end

  it "dispatches to the plural controller" do
    ResourceApp.route_set.routes.select(&.pattern.==("/profile")).map(&.action).should eq([
      "profiles#create", "profiles#show", "profiles#update", "profiles#update", "profiles#destroy",
    ])
  end

  it "generates no-argument path helpers" do
    ResourceApp.profile_path.should eq("/profile")
    ResourceApp.new_profile_path.should eq("/profile/new")
    ResourceApp.edit_profile_path.should eq("/profile/edit")
  end

  it "respects only: on a singular resource" do
    ResourceApp.route_set.routes.map(&.pattern).should_not contain("/account/new")
    ResourceApp.account_path.should eq("/account")
    ResourceApp.edit_account_path.should eq("/account/edit")
  end

  it "respects except: on a singular resource" do
    ResourceApp.route_set.routes.any? { |route| route.method == "DELETE" && route.pattern == "/settings" }.should be_false
    ResourceApp.settings_path.should eq("/settings")
    ResourceApp.new_settings_path.should eq("/settings/new")
    ResourceApp.edit_settings_path.should eq("/settings/edit")
  end

  it "supports member routes without an id" do
    route = ResourceApp.route_set.routes.find!(&.pattern.==("/account/preview"))
    route.method.should eq("GET")
    ResourceApp.preview_account_path.should eq("/account/preview")
  end

  it "names collection routes after the singular resource" do
    ResourceApp.export_account_path.should eq("/account/export")
  end

  it "nests resources under a singular resource without a parent id" do
    ResourceApp.route_set.routes.select(&.pattern.starts_with?("/account/comments")).map do |route|
      "#{route.method} #{route.pattern} -> #{route.action}"
    end.should eq([
      "GET /account/comments -> comments#index",
      "POST /account/comments -> comments#create",
    ])
    ResourceApp.account_comments_path.should eq("/account/comments")
  end

  it "namespaces singular resources and their helpers" do
    ResourceApp.route_set.routes.select(&.pattern.starts_with?("/admin/profile")).map do |route|
      "#{route.method} #{route.pattern} -> #{route.action}"
    end.should eq([
      "GET /admin/profile/new -> admin/profiles#new",
      "POST /admin/profile -> admin/profiles#create",
      "GET /admin/profile -> admin/profiles#show",
      "GET /admin/profile/edit -> admin/profiles#edit",
      "PUT /admin/profile -> admin/profiles#update",
      "PATCH /admin/profile -> admin/profiles#update",
      "DELETE /admin/profile -> admin/profiles#destroy",
    ])
    ResourceApp.admin_profile_path.should eq("/admin/profile")
    ResourceApp.new_admin_profile_path.should eq("/admin/profile/new")
    ResourceApp.edit_admin_profile_path.should eq("/admin/profile/edit")
  end

  it "nests a singular resource under a plural resource" do
    ResourceApp.route_set.routes.select(&.pattern.starts_with?("/users/:user_id/avatar")).map do |route|
      "#{route.method} #{route.pattern} -> #{route.action}"
    end.should eq([
      "GET /users/:user_id/avatar/new -> avatars#new",
      "POST /users/:user_id/avatar -> avatars#create",
      "GET /users/:user_id/avatar -> avatars#show",
      "GET /users/:user_id/avatar/edit -> avatars#edit",
      "PUT /users/:user_id/avatar -> avatars#update",
      "PATCH /users/:user_id/avatar -> avatars#update",
      "DELETE /users/:user_id/avatar -> avatars#destroy",
    ])
    ResourceApp.user_avatar_path(3).should eq("/users/3/avatar")
    ResourceApp.new_user_avatar_path(3).should eq("/users/3/avatar/new")
    ResourceApp.edit_user_avatar_path(3).should eq("/users/3/avatar/edit")
  end
end

class ProfilesController < Altair::Controller
  include ResourceApp::RouteHelpers

  def new : Nil
    render text: "new profile"
  end

  def create : Nil
    render text: "created profile"
  end

  def show : Nil
    render text: "profile"
  end

  def edit : Nil
    render text: "edit profile"
  end

  def update : Nil
    render text: "updated profile"
  end

  def destroy : Nil
    render text: "destroyed profile"
  end
end

private def with_resource_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  app = ResourceApp.instance
  server = Altair::Server.new(app, Altair::Core::RequestHandler.new(app))
  server.bind("127.0.0.1", 0)
  port = server.port

  done = Channel(Nil).new
  spawn do
    server.start
    done.send(nil)
  end

  100.times do
    begin
      HTTP::Client.get("http://127.0.0.1:#{port}/profile")
      break
    rescue IO::Error
      sleep 10.milliseconds
    end
  end

  yield port
ensure
  server.try(&.http_server.close)
  Altair.application_instance = original
end

describe "singular resource integration" do
  it "dispatches all six actions" do
    with_resource_server do |port|
      HTTP::Client.get("http://127.0.0.1:#{port}/profile/new").body.should eq("new profile")
      HTTP::Client.post("http://127.0.0.1:#{port}/profile").body.should eq("created profile")
      HTTP::Client.get("http://127.0.0.1:#{port}/profile").body.should eq("profile")
      HTTP::Client.get("http://127.0.0.1:#{port}/profile/edit").body.should eq("edit profile")
      HTTP::Client.put("http://127.0.0.1:#{port}/profile").body.should eq("updated profile")
      HTTP::Client.patch("http://127.0.0.1:#{port}/profile").body.should eq("updated profile")
      HTTP::Client.delete("http://127.0.0.1:#{port}/profile").body.should eq("destroyed profile")
    end
  end

  it "answers 404 for a member route and for the plural path" do
    with_resource_server do |port|
      HTTP::Client.get("http://127.0.0.1:#{port}/profile/preview").status_code.should eq(404)
      HTTP::Client.get("http://127.0.0.1:#{port}/profiles").status_code.should eq(404)
    end
  end

  it "answers 405 for the wrong method on the singular path" do
    with_resource_server do |port|
      response = HTTP::Client.delete("http://127.0.0.1:#{port}/profile/new")
      response.status_code.should eq(405)
      response.headers["Allow"].should eq("GET")
    end
  end
end
