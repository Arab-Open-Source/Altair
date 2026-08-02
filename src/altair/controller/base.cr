# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Controller`, the base class every controller
# inherits from. Controllers are instantiated per request by the router:
# a route like `resources :posts` dispatches `posts#show` by building
# `PostsController.new(request, response).show`, so each request gets a
# fresh controller with the request, response and merged parameters at
# hand.
#
# The base class provides the three things an action needs to answer a
# request: `render` for bodies with an explicit content type, `redirect_to`
# for redirects and `head` for empty responses. Actions are plain instance
# methods, so controllers stay ordinary classes — no magic, no reflection.
#
# ```
# class PagesController < Altair::Controller
#   def index : Nil
#     render html: "<h1>Welcome</h1>"
#   end
#
#   def show : Nil
#     render json: %({"id": #{params["id"]}})
#   end
# end
# ```
module Altair
  abstract class Controller
    include Altair::View::Helpers
    include Altair::Htmx::Headers

    # The framework's request wrapper for this request.
    getter request : Altair::HTTP::Request

    # The framework's response wrapper for this request.
    getter response : Altair::HTTP::Response

    # The merged parameter bag: route params first, then the query string,
    # then the form body.
    getter params : Altair::HTTP::Params

    def initialize(@request : Altair::HTTP::Request, @response : Altair::HTTP::Response)
      @params = @request.params
    end

    # Renders a response body with an explicit content type. Exactly one of
    # `html:`, `text:` or `json:` must be given; the status defaults to
    # `200 OK` and can be overridden:
    #
    # ```
    # render html: "<h1>Hello</h1>"
    # render json: %({"ok": true}), status: ::HTTP::Status::CREATED
    # render text: "plain"
    # ```
    def render(html : String? = nil, text : String? = nil, json : String? = nil, status : ::HTTP::Status = ::HTTP::Status::OK) : Nil
      kinds = [] of Symbol
      kinds << :html unless html.nil?
      kinds << :text unless text.nil?
      kinds << :json unless json.nil?
      unless kinds.size == 1
        raise ArgumentError.new("render expects exactly one of `html:`, `text:` or `json:`")
      end
      @response.status = status
      case kinds.first
      when :html
        @response.html(html.not_nil!)
      when :text
        @response.text(text.not_nil!)
      when :json
        @response.json(json.not_nil!)
      end
    end

    # Renders a view by action name, wrapped in the controller's layout by
    # default. `layout: false` renders a bare fragment — the building block
    # of htmx flows. Locals must match the template's declared locals:
    #
    # ```
    # render :index
    # render :index, locals: {posts: posts}
    # render :index, layout: false
    # ```
    def render(action : Symbol, *, layout : Bool = true, locals : NamedTuple = NamedTuple.new) : Nil
      body = render_template(action, locals)
      body = render_layout(body) if layout
      @response.html(body)
    end

    # Renders a partial and returns its markup as a String, for composition
    # inside templates:
    #
    # ```
    # <%= render "form", locals: {post: post} %>
    # ```
    def render(partial : String, *, locals : NamedTuple = NamedTuple.new) : String
      render_template(partial, locals)
    end

    # The default template dispatcher; the `templates` macro overrides it
    # in the controller.
    private def render_template(action : Symbol | String, locals : NamedTuple) : String
      raise Altair::Error.new("No templates declared on #{self.class}")
    end

    # The default layout renderer; the `templates` macro overrides it when
    # a layout is declared. Passes the body through unchanged.
    private def render_layout(content : String) : String
      content
    end

    # Opens a `<form>` and appends its closing tag around the block. The
    # template transpiler passes the current output buffer automatically,
    # so it is used directly inside templates:
    #
    # ```
    # <% form_for("/posts", hx_post: "/posts") do |f| %>
    #   <%= f.text_field("title") %>
    #   <%= f.submit("Save") %>
    # <% end %>
    # ```
    def form_for(io : IO, action : String, method : Symbol = :post, **attrs, & : Altair::View::FormBuilder -> Nil) : Nil
      io << "<form action=\"" << action << "\" method=\"post\""
      attrs.each do |key, value|
        io << ' ' << attribute_name(key) << "=\"" << Altair::View.escape(value.to_s) << '"'
      end
      io << '>'
      unless method.in?(:get, :post)
        io << "<input type=\"hidden\" name=\"_method\" value=\"" << method.to_s.upcase << "\">"
      end
      yield Altair::View::FormBuilder.new(method)
      io << "</form>"
    end

    # Redirects to `path`, defaulting to status 302 (Found). The `Location`
    # header is set to `path`, which may be a generated path helper or a
    # literal path:
    #
    # ```
    # redirect_to posts_path
    # redirect_to "/posts", status: ::HTTP::Status::SEE_OTHER
    # ```
    def redirect_to(path : String, status : ::HTTP::Status = ::HTTP::Status::FOUND) : Nil
      @response.redirect(path, status)
    end

    # Sends an empty response with only the given status, e.g.
    # `head ::HTTP::Status::NO_CONTENT`.
    def head(status : ::HTTP::Status) : Nil
      @response.status = status
    end
  end
end
