# Altair — the batteries-included web framework for Crystal.
#
# Specs for the `RouteHelpers` module the DSL generates on every
# application: helpers stay callable as class methods on the application
# subclass, and are also available as instance methods through the module,
# which controllers include to call them bare (`posts_path`, `root_path`).
require "../spec_helper"

class HelpersApp < Altair::Application
  routes do
    root to: "pages#index"
    get "/posts/:id", to: "posts#show", named: :post
    resources :articles, only: [:index, :show]
  end
end

class HelperConsumer
  include HelpersApp::RouteHelpers
end

describe "route helpers module" do
  it "keeps helpers callable on the application subclass" do
    HelpersApp.root_path.should eq("/")
    HelpersApp.post_path(7).should eq("/posts/7")
    HelpersApp.articles_path.should eq("/articles")
    HelpersApp.article_path(3).should eq("/articles/3")
  end

  it "exposes helpers as instance methods through RouteHelpers" do
    consumer = HelperConsumer.new
    consumer.root_path.should eq("/")
    consumer.post_path("abc").should eq("/posts/abc")
    consumer.articles_path.should eq("/articles")
    consumer.article_path(9).should eq("/articles/9")
  end
end
