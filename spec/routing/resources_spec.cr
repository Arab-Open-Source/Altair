# Altair — the batteries-included web framework for Crystal.
#
# Specs for the `resources` macro: one line expanding to the seven
# RESTful routes in conventional order, plus the `only:` and `except:` filters
# and the generated helpers.
require "../spec_helper"

class ResourcesApp < Altair::Application
  routes do
    resources :posts
    resources :articles, only: [:index, :show]
    resources :comments, except: [:destroy]
    resources :people
  end
end

describe "resources" do
  it "expands to the seven RESTful routes in conventional order" do
    ResourcesApp.route_set.routes.select(&.pattern.starts_with?("/posts")).map { |route| "#{route.method} #{route.pattern} -> #{route.action}" }.should eq([
      "GET /posts -> posts#index",
      "GET /posts/new -> posts#new",
      "POST /posts -> posts#create",
      "GET /posts/:id -> posts#show",
      "GET /posts/:id/edit -> posts#edit",
      "PUT /posts/:id -> posts#update",
      "PATCH /posts/:id -> posts#update",
      "DELETE /posts/:id -> posts#destroy",
    ])
  end

  it "honours `only:`" do
    ResourcesApp.route_set.routes.map(&.pattern).select(&.starts_with?("/articles")).should eq([
      "/articles",
      "/articles/:id",
    ])
  end

  it "honours `except:`" do
    deleted = ResourcesApp.route_set.routes.select(&.method.==("DELETE"))
    deleted.map(&.pattern).should_not contain("/comments/:id")
    ResourcesApp.route_set.routes.map(&.pattern).should contain("/comments/:id")
  end

  it "singularizes the helper names" do
    ResourcesApp.posts_path.should eq("/posts")
    ResourcesApp.new_post_path.should eq("/posts/new")
    ResourcesApp.post_path(5).should eq("/posts/5")
    ResourcesApp.edit_post_path(5).should eq("/posts/5/edit")
  end

  it "generates no helpers for actions excluded by `only:`" do
    ResourcesApp.articles_path.should eq("/articles")
    ResourcesApp.article_path(7).should eq("/articles/7")
  end

  it "handles irregular plurals" do
    ResourcesApp.people_path.should eq("/people")
    ResourcesApp.person_path(9).should eq("/people/9")
  end
end
