# Altair — the batteries-included web framework for Crystal.
#
# Unit specs for the `Altair::Controller` base class: the render API with
# its content types and status handling, `redirect_to`, `head`, and the
# request/response/params accessors. Controllers are exercised directly
# against the framework's wrappers, without a running server.
require "../spec_helper"

private def build_controller(method : String = "GET", resource : String = "/posts/5?page=2", headers : HTTP::Headers? = nil, body : String? = nil) : TestController
  raw_request = HTTP::Request.new(method, resource, headers, body)
  request = Altair::HTTP::Request.new(raw_request)
  response = Altair::HTTP::Response.new(HTTP::Server::Response.new(IO::Memory.new))
  TestController.new(request, response)
end

private class TestController < Altair::Controller
  def html_action : Nil
    render html: "<h1>Hi</h1>"
  end

  def text_action : Nil
    render text: "plain body"
  end

  def json_action : Nil
    render json: %({"ok": true})
  end

  def status_action : Nil
    render html: "created", status: ::HTTP::Status::CREATED
  end

  def missing_action : Nil
    render
  end

  def double_action : Nil
    render html: "a", text: "b"
  end

  def redirect_action : Nil
    redirect_to "/posts"
  end

  def redirect_status_action : Nil
    redirect_to "/posts", status: ::HTTP::Status::SEE_OTHER
  end

  def head_action : Nil
    head ::HTTP::Status::NO_CONTENT
  end

  def merged_params_action : Nil
    render text: params["id"]
  end
end

describe Altair::Controller do
  describe "render" do
    it "renders an html body with the html content type" do
      controller = build_controller
      controller.html_action
      controller.response.headers["Content-Type"].should start_with("text/html")
    end

    it "renders a text body with the text content type" do
      controller = build_controller
      controller.text_action
      controller.response.headers["Content-Type"].should start_with("text/plain")
    end

    it "renders a json body with the json content type" do
      controller = build_controller
      controller.json_action
      controller.response.headers["Content-Type"].should start_with("application/json")
    end

    it "honours an explicit status" do
      controller = build_controller
      controller.status_action
      controller.response.status.should eq(::HTTP::Status::CREATED)
    end

    it "keeps 200 OK as the default status" do
      controller = build_controller
      controller.html_action
      controller.response.status.should eq(::HTTP::Status::OK)
    end

    it "raises when no content argument is given" do
      controller = build_controller
      expect_raises(ArgumentError, /exactly one/) do
        controller.missing_action
      end
    end

    it "raises when more than one content argument is given" do
      controller = build_controller
      expect_raises(ArgumentError, /exactly one/) do
        controller.double_action
      end
    end
  end

  describe "redirect_to" do
    it "redirects with the Location header and 302 by default" do
      controller = build_controller
      controller.redirect_action
      controller.response.status.should eq(::HTTP::Status::FOUND)
      controller.response.headers["Location"].should eq("/posts")
    end

    it "honours an explicit status" do
      controller = build_controller
      controller.redirect_status_action
      controller.response.status.should eq(::HTTP::Status::SEE_OTHER)
    end
  end

  describe "head" do
    it "sets the status without a body" do
      controller = build_controller
      controller.head_action
      controller.response.status.should eq(::HTTP::Status::NO_CONTENT)
    end
  end

  describe "accessors" do
    it "exposes the framework request and response wrappers" do
      controller = build_controller(resource: "/posts/5?page=2")
      controller.request.path.should eq("/posts/5")
      controller.params["page"].should eq("2")
    end

    it "exposes the merged params including route params" do
      controller = build_controller
      controller.params.merge_route({"id" => "5"})
      controller.merged_params_action
      controller.params["id"].should eq("5")
    end
  end
end
