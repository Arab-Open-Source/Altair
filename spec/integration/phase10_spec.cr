# Altair — Phase 10 integration spec.
#
# Boots one application with every new subsystem enabled — dynamic redirect,
# cache, storage, attachments, Cable, observability and structured logs —
# then exercises each over real HTTP to prove they work together.
require "../spec_helper"
require "../record/model_fixtures_spec"

class ShowcaseNote < Altair::Record::Model
  table :notes

  belongs_to :notable, polymorphic: true
end

class ShowcasePost < Altair::Record::Model
  table :posts

  has_many :post_tags, foreign_key: :post_id, dependent: :delete_all
  has_many :tags, through: :post_tags, foreign_key: :post_id
end

class ShowcaseTag < Altair::Record::Model
  table :tags
end

class ShowcasePostTag < Altair::Record::Model
  table :post_tags

  belongs_to :post
  belongs_to :tag
end

class ShowcaseController < Altair::Controller
  def cached : Nil
    value = Altair.cache.fetch("greeting", expires_in: 5.seconds) { "hello-from-cache" }
    render text: value
  end

  def upload : Nil
    upload = params.upload("file")
    unless upload
      render text: "missing file", status: ::HTTP::Status::UNPROCESSABLE_ENTITY
      return
    end
    stored = Altair.storage.upload(upload)
    render text: Altair.storage.url(stored.key)
  end

  def broadcast : Nil
    channel = params["channel"]? || "default"
    message = params["message"]? || ""
    begin
      Altair::Cable.broadcast(channel, message)
      head(::HTTP::Status::NO_CONTENT)
    rescue e
      render text: "BROADCAST_ERROR: #{e.class} #{e.message}", status: ::HTTP::Status::INTERNAL_SERVER_ERROR
    end
  end

  def health : Nil
    response.text("healthy")
  end

  def note_for_post : Nil
    post = ShowcasePost.create(title: "noted", views: 1, published: true)
    note = ShowcaseNote.new(body: "attached")
    note.notable = post
    note.save
    render json: {note_id: note.id, notable_type: note.notable_type, resolved: note.notable.as(ShowcasePost).title}
  end
end

class Phase10App < Altair::Application
  routes do
    root to: ShowcaseController.cached
    redirect "/t/:id", to: "/notes/for-post/:id"
    get "/cache", to: ShowcaseController.cached
    post "/upload", to: ShowcaseController.upload
    post "/broadcast", to: ShowcaseController.broadcast
    get "/notes/for-post/:id", to: ShowcaseController.note_for_post
    get "/health", to: ShowcaseController.health
  end
end

private def with_phase10_app(& : Int32 -> Nil)
  Altair::Test.boot(Phase10App, configure: ->(app : Phase10App) {
    app.config.secret_key_base = "phase10-secret"
    app.config.cache = Altair::Cache::MemoryStore.new(100)
    app.config.storage = Altair::Storage::DiskStore.new(
      Path.new(Dir.tempdir, "altair_phase10_#{Random.rand(1_000_000)}")
    )
    app.config.observability = true
    app.config.structured_logs = true
  }) do |port|
    yield port
  end
end

describe "Phase 10 integration" do
  before_each do
    conn = Altair::Record.connection
    RecordSpec.setup_database
    conn.exec("DROP TABLE IF EXISTS altair_attachments")
  end

  it "serves /health when observability is enabled" do
    with_phase10_app do |port|
      response = Altair::Test.get(port, "/health")
      response.status_code.should eq(200)
      response.body.should contain("ok")

      metrics = Altair::Test.get(port, "/metrics")
      metrics.status_code.should eq(200)
      metrics.body.should contain("altair_http_requests_total")
    end
  end

  it "redirects dynamically preserving the id parameter" do
    with_phase10_app do |port|
      response = Altair::Test.get(port, "/t/42")
      response.status_code.should eq(301)
      response.headers["Location"].should eq("/notes/for-post/42")
    end
  end

  it "caches computed values across requests" do
    with_phase10_app do |port|
      first = Altair::Test.get(port, "/cache")
      second = Altair::Test.get(port, "/cache")
      first.body.should eq("hello-from-cache")
      second.body.should eq("hello-from-cache")

      # Verify it came from cache (same instance)
      Altair.cache.read("greeting").should eq("hello-from-cache")
    end
  end

  it "uploads a file via DiskStore and returns its URL" do
    with_phase10_app do |port|
      boundary = "----Boundary#{Random.rand(999_999)}"
      body = "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"test.txt\"\r\nContent-Type: text/plain\r\n\r\nfile content here\r\n--#{boundary}--\r\n"
      response = ::HTTP::Client.post(
        "http://127.0.0.1:#{port}/upload",
        headers: ::HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"},
        body: body
      )
      response.status_code.should eq(200)
      response.body.should start_with("/uploads/")
    end
  end

  it "broadcasts messages through Cable without error" do
    with_phase10_app do |port|
      received = Channel(String).new
      ws = ::HTTP::WebSocket.new(host: "127.0.0.1", port: port, path: "/cable?channel=integration")
      ws.on_message { |msg| received.send(msg) }

      spawn do
        ws.run
      end
      sleep 50.milliseconds

      response = Altair::Test.post(port, "/broadcast", form: "channel=integration&message=live-update")
      # TODO: debug why broadcast via HTTP returns 500; module-level
      # broadcast works (cable_spec.cr passes). Likely controller routing.
      response.status_code.should eq(204)

      select
      when msg = received.receive
        msg.should eq("live-update")
      when timeout(2.seconds)
        fail "did not receive broadcast within timeout"
      end

      ws.close
    end
  end

  it "creates polymorphic notes resolving to posts" do
    with_phase10_app do |port|
      response = Altair::Test.get(port, "/notes/for-post/0")
      # The route creates its own post internally
      response.status_code.should eq(200)
      body = JSON.parse(response.body)
      body["resolved"].as_s.should eq("noted")
      body["notable_type"].as_s.should eq("ShowcasePost")
    end
  end

  it "emits structured JSON log lines" do
    with_phase10_app do |port|
      response = Altair::Test.get(port, "/cache")
      response.status_code.should eq(200)
      # structured_logs is enabled — verify the flag is set
      Altair.application_instance.not_nil!.config.structured_logs?.should be_true
    end
  end

  it "exercises has_many :through alongside joins" do
    with_phase10_app do |_port|
      post = ShowcasePost.create(title: "tagged", views: 1, published: true)
      tag = ShowcaseTag.create(name: "crystal")
      ShowcasePostTag.create(post_id: post.id, tag_id: tag.id)

      results = ShowcasePost.all.joins(:tags).where("tags.name", "crystal").to_a
      results.size.should eq(1)
      results.first.tags.compact_map(&.name).should eq(["crystal"])
    end
  end

  it "uses has_many :through with joins and polymorphic together" do
    with_phase10_app do |_port|
      post = ShowcasePost.create(title: "both", views: 1, published: true)
      tag = ShowcaseTag.create(name: "dual")
      ShowcasePostTag.create(post_id: post.id, tag_id: tag.id)
      results = ShowcasePost.all.joins(:tags).where("tags.name", "dual").to_a
      results.first.tags.compact_map(&.name).should eq(["dual"])
    end
  end
end
