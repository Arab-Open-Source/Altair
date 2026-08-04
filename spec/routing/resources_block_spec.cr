# Altair — the batteries-included web framework for Crystal.
#
# Specs for the `resources` block: `member` and `collection` custom routes
# plus nested `resources` (e.g. `resources :posts do resources :comments
# end`). Covers route registration, generated helpers, the `only:` /
# `except:` filters inside blocks, namespace interaction and real HTTP
# dispatch.
require "../spec_helper"

class ResourcesBlockApp < Altair::Application
  routes do
    resources :posts do
      member do
        get :preview
        post :publish, named: :push_publish
      end
      collection do
        get :export
      end
    end
    resources :articles, only: [:index, :show] do
      member do
        get :share
      end
    end
    resources :people do
      resources :addresses
    end
    namespace :admin do
      resources :chapters do
        member do
          get :review
        end
        collection do
          get :digest
        end
        resources :notes, only: [:index, :create]
      end
    end
  end
end

class OnlySymbolApp < Altair::Application
  routes do
    resources :posts do
      resources :comments, only: :create
    end
  end
end

describe "resources block" do
  describe "member routes" do
    it "registers member routes after the standard seven" do
      ResourcesBlockApp.route_set.routes.select(&.pattern.starts_with?("/posts")).map do |route|
        "#{route.method} #{route.pattern} -> #{route.action}"
      end.should eq([
        "GET /posts/export -> posts#export",
        "GET /posts -> posts#index",
        "GET /posts/new -> posts#new",
        "POST /posts -> posts#create",
        "GET /posts/:id -> posts#show",
        "GET /posts/:id/edit -> posts#edit",
        "PUT /posts/:id -> posts#update",
        "PATCH /posts/:id -> posts#update",
        "DELETE /posts/:id -> posts#destroy",
        "GET /posts/:id/preview -> posts#preview",
        "POST /posts/:id/publish -> posts#publish",
      ])
    end

    it "generates member path helpers from the action and the singular name" do
      ResourcesBlockApp.preview_post_path(5).should eq("/posts/5/preview")
    end

    it "honours a manual `named:` override on a member route" do
      ResourcesBlockApp.push_publish_path(5).should eq("/posts/5/publish")
      ResourcesBlockApp.route_set.routes.find!(&.pattern.==("/posts/:id/publish")).name.should eq("push_publish")
    end

    it "keeps member routes when `only:` limits the standard actions" do
      ResourcesBlockApp.share_article_path(7).should eq("/articles/7/share")
      ResourcesBlockApp.route_set.routes.map(&.pattern).should_not contain("/articles/new")
    end
  end

  describe "collection routes" do
    it "registers collection routes with the plural path" do
      ResourcesBlockApp.route_set.routes.select(&.pattern.==("/posts/export")).map do |route|
        "#{route.method} #{route.pattern} -> #{route.action}"
      end.should eq(["GET /posts/export -> posts#export"])
    end

    it "generates collection path helpers from the action and the plural name" do
      ResourcesBlockApp.export_posts_path.should eq("/posts/export")
    end
  end

  describe "nested resources" do
    it "prefixes the seven standard routes with the parent member path" do
      ResourcesBlockApp.route_set.routes.select(&.pattern.starts_with?("/people/:person_id")).map do |route|
        "#{route.method} #{route.pattern} -> #{route.action}"
      end.should eq([
        "GET /people/:person_id/addresses -> addresses#index",
        "GET /people/:person_id/addresses/new -> addresses#new",
        "POST /people/:person_id/addresses -> addresses#create",
        "GET /people/:person_id/addresses/:id -> addresses#show",
        "GET /people/:person_id/addresses/:id/edit -> addresses#edit",
        "PUT /people/:person_id/addresses/:id -> addresses#update",
        "PATCH /people/:person_id/addresses/:id -> addresses#update",
        "DELETE /people/:person_id/addresses/:id -> addresses#destroy",
      ])
    end

    it "generates nested helpers with the parent parameter first" do
      ResourcesBlockApp.person_addresses_path(1).should eq("/people/1/addresses")
      ResourcesBlockApp.new_person_address_path(1).should eq("/people/1/addresses/new")
      ResourcesBlockApp.person_address_path(1, 2).should eq("/people/1/addresses/2")
      ResourcesBlockApp.edit_person_address_path(1, 2).should eq("/people/1/addresses/2/edit")
    end

    it "applies `only:` inside a nested block" do
      ResourcesBlockApp.route_set.routes.map(&.pattern).should_not contain("/admin/chapters/:chapter_id/notes/new")
      ResourcesBlockApp.admin_chapter_notes_path(5).should eq("/admin/chapters/5/notes")
    end

    context "bare `only:` shorthand" do
      it "accepts a bare symbol and generates the nested create helper" do
        OnlySymbolApp.route_set.routes.select(&.pattern.starts_with?("/posts/:post_id")).map do |route|
          "#{route.method} #{route.pattern} -> #{route.action}"
        end.should eq(["POST /posts/:post_id/comments -> comments#create"])
        OnlySymbolApp.post_comments_path(4).should eq("/posts/4/comments")
      end
    end
  end

  describe "namespaced blocks" do
    it "namespaces member and collection routes and their helpers" do
      ResourcesBlockApp.route_set.routes.select(&.pattern.==("/admin/chapters/:id/review")).map do |route|
        "#{route.method} #{route.pattern} -> #{route.action}"
      end.should eq(["GET /admin/chapters/:id/review -> admin/chapters#review"])
      ResourcesBlockApp.admin_review_chapter_path(5).should eq("/admin/chapters/5/review")
      ResourcesBlockApp.admin_digest_chapters_path.should eq("/admin/chapters/digest")
    end

    it "namespaces nested resources under the same prefix" do
      ResourcesBlockApp.route_set.routes.select(&.pattern.starts_with?("/admin/chapters/:chapter_id/notes")).map do |route|
        "#{route.method} #{route.pattern} -> #{route.action}"
      end.should eq([
        "GET /admin/chapters/:chapter_id/notes -> admin/notes#index",
        "POST /admin/chapters/:chapter_id/notes -> admin/notes#create",
      ])
      ResourcesBlockApp.admin_chapter_notes_path(5).should eq("/admin/chapters/5/notes")
    end
  end
end

class BlockPlaylistsApp < Altair::Application
  routes do
    resources :playlists do
      member do
        get :preview
      end
      collection do
        get :digest
      end
      resources :tracks, only: [:index, :create]
    end
  end
end

class PlaylistsController < Altair::Controller
  include BlockPlaylistsApp::RouteHelpers

  def index : Nil
  end

  def new : Nil
  end

  def create : Nil
  end

  def show : Nil
  end

  def edit : Nil
  end

  def update : Nil
  end

  def destroy : Nil
  end

  def preview : Nil
    render text: "preview #{params["id"]}"
  end

  def digest : Nil
    render text: "digest"
  end
end

class TracksController < Altair::Controller
  def index : Nil
    render text: "tracks of #{params["playlist_id"]}"
  end

  def create : Nil
    render text: "created for #{params["playlist_id"]}"
  end
end

private def with_block_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  app = BlockPlaylistsApp.instance
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
      HTTP::Client.get("http://127.0.0.1:#{port}/playlists/digest")
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

describe "resources block integration" do
  it "dispatches member routes with the member param" do
    with_block_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/playlists/7/preview")
      response.status_code.should eq(200)
      response.body.should eq("preview 7")
    end
  end

  it "dispatches collection routes" do
    with_block_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/playlists/digest")
      response.status_code.should eq(200)
      response.body.should eq("digest")
    end
  end

  it "dispatches nested routes with the parent param" do
    with_block_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/playlists/3/tracks")
      response.status_code.should eq(200)
      response.body.should eq("tracks of 3")
    end
  end

  it "dispatches nested create with the parent param" do
    with_block_server do |port|
      response = HTTP::Client.post("http://127.0.0.1:#{port}/playlists/3/tracks")
      response.status_code.should eq(200)
      response.body.should eq("created for 3")
    end
  end

  it "answers 405 for the wrong method on a member route" do
    with_block_server do |port|
      response = HTTP::Client.post("http://127.0.0.1:#{port}/playlists/7/preview")
      response.status_code.should eq(405)
      response.headers["Allow"].should eq("GET")
    end
  end
end
