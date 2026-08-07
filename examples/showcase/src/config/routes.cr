# Showcase — the route table.
#
# The routing DSL, end to end. The generated path helpers (`posts_path`,
# `new_session_path`, `post_publish_path`, and so on) are real methods,
# mixed into `ApplicationController` below, so a typo in a route is a
# compile error.
class Showcase
  routes do
    root to: PagesController.index

    get "/about", to: PagesController.about
    get "/stream", to: PagesController.stream, named: :stream
    get "/docs/*path", to: PagesController.docs, named: :docs
    # A parameter with a constraint: `/archive/:year` only matches a
    # four-digit year, so `/archive/bananas` is a 404, not a params parse.
    get "/archive/:year", to: PostsController.by_year, constraints: {year: /\d{4}/}, named: :archive

    # A permanent redirect: `/forum` answers 301 straight to `/posts`.
    redirect "/forum", to: "/posts"

    # Auth. `resource :session` is singular — only one login per session.
    resources :users, only: [:new, :create, :show]
    resource :session, only: [:new, :create, :destroy]

    # Posts, with a nested comments resource, a `publish` member action and
    # a `recent` collection action. GET /posts.json also matches, with
    # `params["format"] == "json"`, and the index action responds in kind.
    resources :posts do
      resources :comments, only: [:create, :destroy]
      member do
        post :publish
      end
      collection do
        get :recent
      end
    end

    # A stateless JSON API backed by signed JWTs (Altair::Auth::JWT).
    post "/api/token", to: ApiController.token
    get "/api/me", to: ApiController.me
  end
end

abstract class ApplicationController < Altair::Controller
  include Showcase::RouteHelpers
end
