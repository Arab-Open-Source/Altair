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

    # Records this controller's superclass chain (itself first) as soon as
    # the class is defined, so callback resolution at request time can walk
    # the chain without runtime reflection. Modules picked up by
    # `#ancestors` are filtered out by requiring the candidate's own
    # ancestry to include the base controller.
    macro inherited
      {% names = [] of String %}
      {% for a in @type.ancestors %}
        {% if a.ancestors.map(&.name.stringify).includes?("Altair::Controller") %}
          {% names << a.name.stringify %}
        {% end %}
      {% end %}
      Altair::Controller::Callbacks.record_chain(
        {{ @type.name.stringify }},
        [{{ @type.name.stringify }}, {% for n in names %}{{ n }}, {% end %}]
      )
    end

    # Registers a filter method to run before the action. `only:` and
    # `except:` restrict the actions the filter applies to. A filter that
    # writes a response (render, redirect, head) halts the chain — the
    # action and its after callbacks are skipped:
    #
    # ```
    # class PostsController < Altair::Controller
    #   before_action :require_login, only: [:new, :create]
    # end
    # ```
    macro before_action(method, only = nil, except = nil)
      {% only_list = only ? (only.is_a?(SymbolLiteral) ? [only] : only) : [] of SymbolLiteral %}
      {% except_list = except ? (except.is_a?(SymbolLiteral) ? [except] : except) : [] of SymbolLiteral %}
      {% only_codes = only_list.map(&.id.stringify) %}
      {% except_codes = except_list.map(&.id.stringify) %}
      altair_callback = ->(controller : Altair::Controller) { controller.as({{ @type }}).{{ method.id }}
      }
      Altair::Controller::Callbacks.add_before(
        {{ @type }},
        Altair::Controller::Callbacks::Callback.new(
          {{ method.id.stringify }},
          {{ only_codes.empty? ? "[] of String".id : only_codes }},
          {{ except_codes.empty? ? "[] of String".id : except_codes }},
          altair_callback
        )
      )
    end

    # Registers a filter method to run after the action. Skipped when a
    # before callback halted the chain.
    macro after_action(method, only = nil, except = nil)
      {% only_list = only ? (only.is_a?(SymbolLiteral) ? [only] : only) : [] of SymbolLiteral %}
      {% except_list = except ? (except.is_a?(SymbolLiteral) ? [except] : except) : [] of SymbolLiteral %}
      {% only_codes = only_list.map(&.id.stringify) %}
      {% except_codes = except_list.map(&.id.stringify) %}
      altair_callback = ->(controller : Altair::Controller) { controller.as({{ @type }}).{{ method.id }}
      }
      Altair::Controller::Callbacks.add_after(
        {{ @type }},
        Altair::Controller::Callbacks::Callback.new(
          {{ method.id.stringify }},
          {{ only_codes.empty? ? "[] of String".id : only_codes }},
          {{ except_codes.empty? ? "[] of String".id : except_codes }},
          altair_callback
        )
      )
    end

    # Removes a `before_action` (typically inherited from a base
    # controller) for the selected actions:
    #
    # ```
    # class Admin::PostsController < PostsController
    #   skip_before_action :require_login
    # end
    # ```
    macro skip_before_action(method, only = nil, except = nil)
      {% only_list = only ? (only.is_a?(SymbolLiteral) ? [only] : only) : [] of SymbolLiteral %}
      {% except_list = except ? (except.is_a?(SymbolLiteral) ? [except] : except) : [] of SymbolLiteral %}
      {% only_codes = only_list.map(&.id.stringify) %}
      {% except_codes = except_list.map(&.id.stringify) %}
      altair_callback = ->(controller : Altair::Controller) { controller.as({{ @type }}).{{ method.id }}
      }
      Altair::Controller::Callbacks.add_skip_before(
        {{ @type }},
        Altair::Controller::Callbacks::Callback.new(
          {{ method.id.stringify }},
          {{ only_codes.empty? ? "[] of String".id : only_codes }},
          {{ except_codes.empty? ? "[] of String".id : except_codes }},
          altair_callback
        )
      )
    end

    # Removes an `after_action` for the selected actions.
    macro skip_after_action(method, only = nil, except = nil)
      {% only_list = only ? (only.is_a?(SymbolLiteral) ? [only] : only) : [] of SymbolLiteral %}
      {% except_list = except ? (except.is_a?(SymbolLiteral) ? [except] : except) : [] of SymbolLiteral %}
      {% only_codes = only_list.map(&.id.stringify) %}
      {% except_codes = except_list.map(&.id.stringify) %}
      altair_callback = ->(controller : Altair::Controller) { controller.as({{ @type }}).{{ method.id }}
      }
      Altair::Controller::Callbacks.add_skip_after(
        {{ @type }},
        Altair::Controller::Callbacks::Callback.new(
          {{ method.id.stringify }},
          {{ only_codes.empty? ? "[] of String".id : only_codes }},
          {{ except_codes.empty? ? "[] of String".id : except_codes }},
          altair_callback
        )
      )
    end

    # Registers a handler for exceptions raised by the action or any of its
    # callbacks. The handler must accept the exception and return nothing:
    #
    # ```
    # rescue_from InvalidParams, handle_with: :render_bad_request
    #
    # def render_bad_request(e : InvalidParams) : Nil
    #   render json: {error: e.message}, status: :bad_request
    # end
    # ```
    #
    # `only:` and `except:` restrict the actions the handler answers for,
    # subclass exceptions match the registered type, and a subclass's
    # `rescue_from` shadows a base controller's for the same exception.
    macro rescue_from(exception, handle_with = nil, only = nil, except = nil)
      {% if handle_with == nil %}
        {% raise "rescue_from requires `handle_with:` naming the handler method" %}
      {% end %}
      {% only_list = only ? (only.is_a?(SymbolLiteral) ? [only] : only) : [] of SymbolLiteral %}
      {% except_list = except ? (except.is_a?(SymbolLiteral) ? [except] : except) : [] of SymbolLiteral %}
      {% only_codes = only_list.map(&.id.stringify) %}
      {% except_codes = except_list.map(&.id.stringify) %}
      altair_rescue_match = ->(e : Exception) { e.is_a?({{ exception }}) }
      altair_rescue_run = ->(controller : Altair::Controller, e : Exception) {
        controller.as({{ @type }}).{{ handle_with.id }}(e.as({{ exception }}))
      }
      Altair::Controller::RescueFrom.add_handler(
        {{ @type.name.stringify }},
        Altair::Controller::RescueFrom::RescueHandler.new(
          {{ exception.stringify }},
          {{ handle_with.id.stringify }},
          {{ only_codes.empty? ? "[] of String".id : only_codes }},
          {{ except_codes.empty? ? "[] of String".id : except_codes }},
          altair_rescue_match,
          altair_rescue_run
        )
      )
    end

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
    # `200 OK` and can be overridden. The `json:` value may be a
    # pre-serialized JSON string or any JSON-able object:
    #
    # ```
    # render html: "<h1>Hello</h1>"
    # render json: %({"ok": true}), status: ::HTTP::Status::CREATED
    # render json: {ok: true}
    # render text: "plain"
    # ```
    def render(html : String? = nil, text : String? = nil, json : String? = nil, status : ::HTTP::Status = ::HTTP::Status::OK) : Nil
      write_render(html, text, json, status)
    end

    # Serializes any JSON-able object (`Hash`, `NamedTuple`, `Array`,
    # `JSON::Serializable`, ...) with `to_json` before rendering.
    def render(html : String? = nil, text : String? = nil, json : T = nil, status : ::HTTP::Status = ::HTTP::Status::OK) : Nil forall T
      payload = json.try { |obj| obj.is_a?(String) ? obj : obj.to_json }
      write_render(html, text, payload, status)
    end

    private def write_render(html : String?, text : String?, json : String?, status : ::HTTP::Status) : Nil
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
      io << "<form action=\"" << Altair::View.escape(action) << "\" method=\"post\""
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

    # Redirects back to the page the request came from — the `Referer`
    # header — falling back to `fallback` when there is no referer or it
    # points at another host (open-redirect protection):
    #
    # ```
    # redirect_back(fallback: posts_path)
    # ```
    def redirect_back(fallback : String, status : ::HTTP::Status = ::HTTP::Status::FOUND) : Nil
      if referer = @request.headers["Referer"]?
        uri = URI.parse(referer)
        host = @request.headers["Host"]?.try(&.split(':')[0])
        if uri.host.nil? || host.nil? || uri.host == host
          target = uri.query ? "#{uri.path}?#{uri.query}" : uri.path
          return redirect_to(target, status)
        end
      end
      redirect_to(fallback, status)
    end

    # Answers the request in the format it asked for. The block declares one
    # handler per format; the one matching `request.format` (path suffix,
    # then `Accept`, then `:html`) runs, and a request for an undeclared
    # format answers 406 Not Acceptable:
    #
    # ```
    # def show : Nil
    #   @post = Post.find(params["id"])
    #   respond_to do |format|
    #     format.html { render "posts.show" }
    #     format.json { render json: @post }
    #   end
    # end
    # ```
    def respond_to(& : Altair::Controller::FormatResponder ->) : Nil
      responder = Altair::Controller::FormatResponder.new(@request, @response)
      yield responder
      responder.answer
    end

    # Sends an empty response with only the given status, e.g.
    # `head ::HTTP::Status::NO_CONTENT`. Any body written afterwards is
    # ignored.
    def head(status : ::HTTP::Status) : Nil
      @response.head(status)
    end

    # Sends an empty `204 No Content` response — the conventional answer
    # for successful submissions that should not navigate anywhere.
    def no_content : Nil
      head ::HTTP::Status::NO_CONTENT
    end

    # Runs the action's before callbacks, in declaration order. Called by
    # the router's dispatch wrapper before the action; a callback that
    # writes a response halts the chain, so the dispatcher skips the
    # action when `responded?` turns true.
    def run_before_actions(action : String) : Nil
      self.class.callbacks_for(:before, action).each do |callback|
        callback.run.call(self)
      end
    end

    # Runs the action's after callbacks, in declaration order. Called by
    # the router's dispatch wrapper after the action, unless a before
    # callback halted the chain.
    def run_after_actions(action : String) : Nil
      self.class.callbacks_for(:after, action).each do |callback|
        callback.run.call(self)
      end
    end

    # True when the response has been written — by a callback (render,
    # redirect, head) or by the action itself. The router's dispatch
    # wrapper uses it to halt the chain once the response is started.
    def responded? : Bool
      @response.written?
    end

    # Answers `e` with the first matching `rescue_from` handler for the
    # current action, or re-raises when none applies.
    def handle_rescue(e : Exception, action : String) : Nil
      handler = self.class.rescue_handlers_for(e, action).first?
      if handler
        handler.run.call(self, e)
      else
        raise e
      end
    end

    # The `rescue_from` handlers in effect for `e` and `action`: declared
    # anywhere in the superclass chain (the subclass's own first), whose
    # registered exception matches `e` and whose filters include the action.
    def self.rescue_handlers_for(e : Exception, action : String) : Array(Altair::Controller::RescueFrom::RescueHandler)
      Altair::Controller::Callbacks.chain_of(name)
        .flat_map { |class_name| Altair::Controller::RescueFrom.handlers_of(class_name) }
        .select { |handler| handler.match.call(e) && handler.applies_to?(action) }
    end

    # The callbacks in effect for `action`: declarations from the whole
    # superclass chain (base first), minus anything a `skip_*` marker
    # removed for this action, minus callbacks whose `only:`/`except:`
    # filters exclude it.
    def self.callbacks_for(kind : Symbol, action : String) : Array(Altair::Controller::Callbacks::Callback)
      names = Altair::Controller::Callbacks.chain_of(name).reverse
      callbacks = names.flat_map { |class_name| Altair::Controller::Callbacks.list(kind, class_name) }
      skips = names.flat_map { |class_name| Altair::Controller::Callbacks.skips(kind, class_name) }
      callbacks.select do |callback|
        next false if skips.any? { |skip| skip.method_name == callback.method_name && skip.applies_to?(action) }
        callback.applies_to?(action)
      end
    end
  end
end
