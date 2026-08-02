# Altair — the batteries-included web framework for Crystal.
#
# Specs for the `namespace` macro: path prefixes, controller prefixes,
# helper prefixes and nested namespaces.
require "../spec_helper"

class NamespaceApp < Altair::Application
  routes do
    namespace :admin do
      resources :posts
      get "/stats", to: "stats#index", named: :stats
    end
    namespace :api do
      namespace :v1 do
        resources :users
      end
    end
    get "/about", to: "pages#about"
  end
end

describe "namespace" do
  it "prefixes paths and controllers" do
    NamespaceApp.route_set.routes.select(&.pattern.starts_with?("/admin")).map { |route| "#{route.method} #{route.pattern} -> #{route.action}" }.should eq([
      "GET /admin/posts -> admin/posts#index",
      "GET /admin/posts/new -> admin/posts#new",
      "POST /admin/posts -> admin/posts#create",
      "GET /admin/posts/:id -> admin/posts#show",
      "GET /admin/posts/:id/edit -> admin/posts#edit",
      "PUT /admin/posts/:id -> admin/posts#update",
      "PATCH /admin/posts/:id -> admin/posts#update",
      "DELETE /admin/posts/:id -> admin/posts#destroy",
      "GET /admin/stats -> admin/stats#index",
    ])
  end

  it "prefixes the generated helpers" do
    NamespaceApp.admin_posts_path.should eq("/admin/posts")
    NamespaceApp.new_admin_post_path.should eq("/admin/posts/new")
    NamespaceApp.admin_post_path(5).should eq("/admin/posts/5")
    NamespaceApp.edit_admin_post_path(5).should eq("/admin/posts/5/edit")
    NamespaceApp.admin_stats_path.should eq("/admin/stats")
  end

  it "namespaces named routes inside the namespace" do
    NamespaceApp.route_set.routes.find!(&.pattern.==("/admin/stats")).name.should eq("stats")
  end

  it "supports nested namespaces" do
    NamespaceApp.route_set.routes.map(&.pattern).should contain("/api/v1/users")
    NamespaceApp.route_set.routes.map(&.action).should contain("api/v1/users#index")
    NamespaceApp.api_v1_users_path.should eq("/api/v1/users")
    NamespaceApp.api_v1_user_path(3).should eq("/api/v1/users/3")
  end

  it "leaves routes outside the namespace untouched" do
    NamespaceApp.route_set.routes.last.pattern.should eq("/about")
    NamespaceApp.route_set.routes.last.action.should eq("pages#about")
  end
end
