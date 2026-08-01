# Altair — the batteries-included web framework for Crystal.
#
# Specs for named-route helpers: paths with no params, one param, multiple
# params, static suffixes after params and namespace-prefixed helpers.
require "../spec_helper"

class NamedRoutesApp < Altair::Application
  routes do
    get "/dashboard", to: "pages#dashboard", named: :dashboard
    get "/posts/:id", to: "posts#show", named: :post
    get "/books/:book_id/chapters/:chapter_id", to: "chapters#show", named: :chapter
    get "/files/:path/edit", to: "files#edit", named: :file
    get "/users/:user_id/posts/:post_id/comments/:comment_id", to: "comments#show", named: :comment
  end
end

describe "named-route helpers" do
  it "builds a static path" do
    NamedRoutesApp.dashboard_path.should eq("/dashboard")
  end

  it "builds a path with a single parameter" do
    NamedRoutesApp.post_path(5).should eq("/posts/5")
  end

  it "accepts string parameters" do
    NamedRoutesApp.post_path("hello world").should eq("/posts/hello world")
  end

  it "builds a path with multiple parameters in declaration order" do
    NamedRoutesApp.chapter_path(3, 7).should eq("/books/3/chapters/7")
  end

  it "builds a path with a static segment after a parameter" do
    NamedRoutesApp.file_path(42).should eq("/files/42/edit")
  end

  it "builds a path with three parameters" do
    NamedRoutesApp.comment_path(1, 2, 3).should eq("/users/1/posts/2/comments/3")
  end
end
