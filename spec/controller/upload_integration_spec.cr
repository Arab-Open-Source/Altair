# Altair — multipart upload integration.
#
# End-to-end spec for Phase 6 "Multipart form parsing": a real application
# boots over HTTP, receives a `multipart/form-data` POST from an
# `HTTP::Client`, and the controller reads both the scalar field and the
# uploaded file from the parameter bag.
require "../spec_helper"

class UploadsApp < Altair::Application
  routes do
    post "/upload", to: "uploads#create"
    get "/uploads/:id", to: "uploads#show"
  end
end

class UploadsController < Altair::Controller
  @@received = [] of String

  def self.received : Array(String)
    @@received
  end

  def self.reset
    @@received.clear
  end

  def create : Nil
    upload = params.upload("file")
    if upload.nil?
      render json: %({"error": "no file"})
    else
      @@received << upload.original_filename.not_nil!
      render json: %({"path": "#{upload.original_filename}", "type": "#{upload.content_type}", "size": #{upload.size}})
    end
  end

  def show : Nil
    render text: "stored: #{@@received.join(", ")}"
  end
end

private def with_upload_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  UploadsController.reset
  app = UploadsApp.instance
  server = Altair::Server.new(app, Altair::Core::RequestHandler.new(app))
  server.bind("127.0.0.1", 0)
  port = server.port

  done = Channel(Nil).new
  spawn do
    server.start
    done.send(nil)
  end

  wait_until_ready(port)

  yield port
ensure
  server.try(&.http_server.close)
  Altair.application_instance = original
end

private def wait_until_ready(port : Int32) : Nil
  100.times do
    HTTP::Client.get("http://127.0.0.1:#{port}/uploads?title=x")
    return
  rescue IO::Error
    sleep 10.milliseconds
  end
  raise "server did not become ready"
end

describe "multipart upload" do
  it "delivers a file and a scalar field through params" do
    with_upload_server do |port|
      boundary = "#{Random.rand(1_000_000)}altair#{Time.utc.to_unix_ms}"
      io = IO::Memory.new
      io << "--#{boundary}\r\n"
      io << "Content-Disposition: form-data; name=\"title\"\r\n\r\n"
      io << "My Photo\r\n"
      io << "--#{boundary}\r\n"
      io << "Content-Disposition: form-data; name=\"file\"; filename=\"vacation.png\"\r\n"
      io << "Content-Type: image/png\r\n\r\n"
      io << "fake-png-bytes"
      io << "\r\n--#{boundary}--\r\n"

      response = HTTP::Client.post(
        "http://127.0.0.1:#{port}/upload",
        body: io.to_s,
        headers: HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"}
      )
      response.status_code.should eq(200)
      response.headers["Content-Type"].should contain("application/json")
      response.body.should eq(%({"path": "vacation.png", "type": "image/png", "size": 14}))
      UploadsController.received.should eq(["vacation.png"])
    end
  end

  it "answers with a JSON error when no file part was sent" do
    with_upload_server do |port|
      boundary = "missing"
      body = "--#{boundary}\r\n" \
             "Content-Disposition: form-data; name=\"title\"\r\n\r\n" \
             "Plain Field\r\n" \
             "--#{boundary}--\r\n"
      response = HTTP::Client.post(
        "http://127.0.0.1:#{port}/upload",
        body: body,
        headers: HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"}
      )
      response.status_code.should eq(200)
      response.body.should eq(%({"error": "no file"}))
    end
  end

  it "sends an application/x-www-form-urlencoded body without uploads" do
    with_upload_server do |port|
      response = HTTP::Client.post(
        "http://127.0.0.1:#{port}/upload",
        form: "title=t",
        headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
      )
      response.body.should eq(%({"error": "no file"}))
    end
  end
end
