# Altair — the batteries-included web framework for Crystal.
#
# This file defines the routing DSL: the `routes` block available on every
# `Altair::Application` subclass. The DSL is entirely compile-time — every
# call is a macro — which gives Altair three properties at once:
#
# * named path helpers are real methods, callable as `Blog.post_path(5)`
#   and type-checked by the compiler;
# * controller references are resolved by the compiler, so a typo in
#   `to: "posts#shw"` is a compile error, not a runtime surprise;
# * the route table is fully built while the application class is loaded,
#   before the first request ever arrives.
#
# `to:` routes dispatch to instance controllers: `"posts#show"` expands to
# `PostsController.new(request, response).show`, so actions are plain
# instance methods on a controller that subclasses `Altair::Controller`.
# Generated path helpers are gathered in the application's `RouteHelpers`
# module, which controllers include to call them bare:
#
# ```
# class PostsController < Altair::Controller
#   include Blog::RouteHelpers
#
#   def index : Nil
#     redirect_to new_post_path
#   end
# end
# ```
#
# ```
# class Blog < Altair::Application
#   routes do
#     root to: "pages#index"
#     get "/hello/:name", to: "pages#hello"
#     get "/version" do |request, response|
#       response.json(%({"version": "#{Altair::VERSION}"}))
#     end
#     resources :posts
#     namespace :admin do
#       resources :posts
#     end
#   end
# end
# ```
abstract class Altair::Application
  # Opens the routing section of the application. Every route declared
  # inside the block is expanded at compile time.
  macro routes(&block)
    {{ block.body }}
  end

  # Registers a `GET` route. `to:` names the controller action
  # (`"pages#index"`), `named:` gives the route a path helper, or a handler
  # block replaces both. `constraints:` restricts a parameter's values to a
  # regular expression (`get "/posts/:id", constraints: {id: /\d+/}`).
  macro get(path, to = nil, named = nil, namespace = nil, constraints = nil, &block)
    {% if to %}
      {% if block %}
        {% raise "a route cannot combine `to:` with a handler block: #{path}" %}
      {% end %}
    {% end %}
    {% if block %}
      {% if block.args.size != 2 %}
        {% raise "route handler blocks must declare exactly two parameters — |request, response|: #{path}" %}
      {% end %}
    {% end %}
    {% ns = namespace ? namespace + "/" : "" %}
    {% nsf = namespace ? namespace.split("/").join("_") + "_" : "" %}
    {% full_path = namespace ? "/" + namespace + path : path %}
    {% route_name = named ? named.id.stringify : nil %}
    {% if block %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "GET",
        pattern: {{full_path}},
        action: nil,
        name: {{ route_name }},
        {% if constraints %}
          constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
        {% end %}
        handler: ->({{block.args[0].id}} : Altair::HTTP::Request, {{block.args[1].id}} : Altair::HTTP::Response) {
          {{ block.body }}
        }
      )
    {% else %}
      {% if to == nil %}
        {% raise "a route must declare an action with `to:` or a handler block: #{path}" %}
      {% end %}
      {% if to.is_a?(Call) %}
        {% cconst = to.receiver %}
        {% action_ref = to.name %}
        {% action_label = cconst.id.stringify + "#" + action_ref.id.stringify %}
      {% else %}
        {% cparts = (ns + to.split("#")[0]).split("/") %}
        {% cconst = cparts.map(&.camelcase).join("::") + "Controller" %}
        {% action_ref = to.split("#")[1] %}
        {% action_label = ns + to %}
      {% end %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "GET",
        pattern: {{full_path}},
        action: {{ action_label }},
        name: {{ route_name }},
        {% if constraints %}
          constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
        {% end %}
        handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
          {{ cconst.id }}.new(request, response).{{ action_ref.id }}
        }
      )
    {% end %}
    {% if named %}
      {% helper_parts = full_path.split("/").reject(&.empty?) %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") || part.starts_with?("*") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = "#{nsf.id}#{named.id}_path" %}
      {% if helper_params.size > 0 %}
        module RouteHelpers
          def {{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String) : String
            {{helper_expr.join(" + ").id}}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% else %}
        module RouteHelpers
          def {{helper_name.id}} : String
            {{ full_path }}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% end %}
    {% end %}
  end

  # Registers a `POST` route.
  macro post(path, to = nil, named = nil, namespace = nil, constraints = nil, &block)
    {% if to %}
      {% if block %}
        {% raise "a route cannot combine `to:` with a handler block: #{path}" %}
      {% end %}
    {% end %}
    {% if block %}
      {% if block.args.size != 2 %}
        {% raise "route handler blocks must declare exactly two parameters — |request, response|: #{path}" %}
      {% end %}
    {% end %}
    {% ns = namespace ? namespace + "/" : "" %}
    {% nsf = namespace ? namespace.split("/").join("_") + "_" : "" %}
    {% full_path = namespace ? "/" + namespace + path : path %}
    {% route_name = named ? named.id.stringify : nil %}
    {% if block %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "POST",
        pattern: {{full_path}},
        action: nil,
        name: {{ route_name }},
        {% if constraints %}
          constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
        {% end %}
        handler: ->({{block.args[0].id}} : Altair::HTTP::Request, {{block.args[1].id}} : Altair::HTTP::Response) {
          {{ block.body }}
        }
      )
    {% else %}
      {% if to == nil %}
        {% raise "a route must declare an action with `to:` or a handler block: #{path}" %}
      {% end %}
      {% if to.is_a?(Call) %}
        {% cconst = to.receiver %}
        {% action_ref = to.name %}
        {% action_label = cconst.id.stringify + "#" + action_ref.id.stringify %}
      {% else %}
        {% cparts = (ns + to.split("#")[0]).split("/") %}
        {% cconst = cparts.map(&.camelcase).join("::") + "Controller" %}
        {% action_ref = to.split("#")[1] %}
        {% action_label = ns + to %}
      {% end %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "POST",
        pattern: {{full_path}},
        action: {{ action_label }},
        name: {{ route_name }},
        {% if constraints %}
          constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
        {% end %}
        handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
          {{ cconst.id }}.new(request, response).{{ action_ref.id }}
        }
      )
    {% end %}
    {% if named %}
      {% helper_parts = full_path.split("/").reject(&.empty?) %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") || part.starts_with?("*") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = "#{nsf.id}#{named.id}_path" %}
      {% if helper_params.size > 0 %}
        module RouteHelpers
          def {{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String) : String
            {{helper_expr.join(" + ").id}}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% else %}
        module RouteHelpers
          def {{helper_name.id}} : String
            {{ full_path }}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% end %}
    {% end %}
  end

  # Registers a `PUT` route.
  macro put(path, to = nil, named = nil, namespace = nil, constraints = nil, &block)
    {% if to %}
      {% if block %}
        {% raise "a route cannot combine `to:` with a handler block: #{path}" %}
      {% end %}
    {% end %}
    {% if block %}
      {% if block.args.size != 2 %}
        {% raise "route handler blocks must declare exactly two parameters — |request, response|: #{path}" %}
      {% end %}
    {% end %}
    {% ns = namespace ? namespace + "/" : "" %}
    {% nsf = namespace ? namespace.split("/").join("_") + "_" : "" %}
    {% full_path = namespace ? "/" + namespace + path : path %}
    {% route_name = named ? named.id.stringify : nil %}
    {% if block %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "PUT",
        pattern: {{full_path}},
        action: nil,
        name: {{ route_name }},
        {% if constraints %}
          constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
        {% end %}
        handler: ->({{block.args[0].id}} : Altair::HTTP::Request, {{block.args[1].id}} : Altair::HTTP::Response) {
          {{ block.body }}
        }
      )
    {% else %}
      {% if to == nil %}
        {% raise "a route must declare an action with `to:` or a handler block: #{path}" %}
      {% end %}
      {% if to.is_a?(Call) %}
        {% cconst = to.receiver %}
        {% action_ref = to.name %}
        {% action_label = cconst.id.stringify + "#" + action_ref.id.stringify %}
      {% else %}
        {% cparts = (ns + to.split("#")[0]).split("/") %}
        {% cconst = cparts.map(&.camelcase).join("::") + "Controller" %}
        {% action_ref = to.split("#")[1] %}
        {% action_label = ns + to %}
      {% end %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "PUT",
        pattern: {{full_path}},
        action: {{ action_label }},
        name: {{ route_name }},
        {% if constraints %}
          constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
        {% end %}
        handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
          {{ cconst.id }}.new(request, response).{{ action_ref.id }}
        }
      )
    {% end %}
    {% if named %}
      {% helper_parts = full_path.split("/").reject(&.empty?) %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") || part.starts_with?("*") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = "#{nsf.id}#{named.id}_path" %}
      {% if helper_params.size > 0 %}
        module RouteHelpers
          def {{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String) : String
            {{helper_expr.join(" + ").id}}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% else %}
        module RouteHelpers
          def {{helper_name.id}} : String
            {{ full_path }}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% end %}
    {% end %}
  end

  # Registers a `PATCH` route.
  macro patch(path, to = nil, named = nil, namespace = nil, constraints = nil, &block)
    {% if to %}
      {% if block %}
        {% raise "a route cannot combine `to:` with a handler block: #{path}" %}
      {% end %}
    {% end %}
    {% if block %}
      {% if block.args.size != 2 %}
        {% raise "route handler blocks must declare exactly two parameters — |request, response|: #{path}" %}
      {% end %}
    {% end %}
    {% ns = namespace ? namespace + "/" : "" %}
    {% nsf = namespace ? namespace.split("/").join("_") + "_" : "" %}
    {% full_path = namespace ? "/" + namespace + path : path %}
    {% route_name = named ? named.id.stringify : nil %}
    {% if block %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "PATCH",
        pattern: {{full_path}},
        action: nil,
        name: {{ route_name }},
        {% if constraints %}
          constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
        {% end %}
        handler: ->({{block.args[0].id}} : Altair::HTTP::Request, {{block.args[1].id}} : Altair::HTTP::Response) {
          {{ block.body }}
        }
      )
    {% else %}
      {% if to == nil %}
        {% raise "a route must declare an action with `to:` or a handler block: #{path}" %}
      {% end %}
      {% if to.is_a?(Call) %}
        {% cconst = to.receiver %}
        {% action_ref = to.name %}
        {% action_label = cconst.id.stringify + "#" + action_ref.id.stringify %}
      {% else %}
        {% cparts = (ns + to.split("#")[0]).split("/") %}
        {% cconst = cparts.map(&.camelcase).join("::") + "Controller" %}
        {% action_ref = to.split("#")[1] %}
        {% action_label = ns + to %}
      {% end %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "PATCH",
        pattern: {{full_path}},
        action: {{ action_label }},
        name: {{ route_name }},
        {% if constraints %}
          constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
        {% end %}
        handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
          {{ cconst.id }}.new(request, response).{{ action_ref.id }}
        }
      )
    {% end %}
    {% if named %}
      {% helper_parts = full_path.split("/").reject(&.empty?) %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") || part.starts_with?("*") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = "#{nsf.id}#{named.id}_path" %}
      {% if helper_params.size > 0 %}
        module RouteHelpers
          def {{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String) : String
            {{helper_expr.join(" + ").id}}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% else %}
        module RouteHelpers
          def {{helper_name.id}} : String
            {{ full_path }}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% end %}
    {% end %}
  end

  # Registers a `DELETE` route.
  macro delete(path, to = nil, named = nil, namespace = nil, constraints = nil, &block)
    {% if to %}
      {% if block %}
        {% raise "a route cannot combine `to:` with a handler block: #{path}" %}
      {% end %}
    {% end %}
    {% if block %}
      {% if block.args.size != 2 %}
        {% raise "route handler blocks must declare exactly two parameters — |request, response|: #{path}" %}
      {% end %}
    {% end %}
    {% ns = namespace ? namespace + "/" : "" %}
    {% nsf = namespace ? namespace.split("/").join("_") + "_" : "" %}
    {% full_path = namespace ? "/" + namespace + path : path %}
    {% route_name = named ? named.id.stringify : nil %}
    {% if block %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "DELETE",
        pattern: {{full_path}},
        action: nil,
        name: {{ route_name }},
        {% if constraints %}
          constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
        {% end %}
        handler: ->({{block.args[0].id}} : Altair::HTTP::Request, {{block.args[1].id}} : Altair::HTTP::Response) {
          {{ block.body }}
        }
      )
    {% else %}
      {% if to == nil %}
        {% raise "a route must declare an action with `to:` or a handler block: #{path}" %}
      {% end %}
      {% if to.is_a?(Call) %}
        {% cconst = to.receiver %}
        {% action_ref = to.name %}
        {% action_label = cconst.id.stringify + "#" + action_ref.id.stringify %}
      {% else %}
        {% cparts = (ns + to.split("#")[0]).split("/") %}
        {% cconst = cparts.map(&.camelcase).join("::") + "Controller" %}
        {% action_ref = to.split("#")[1] %}
        {% action_label = ns + to %}
      {% end %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "DELETE",
        pattern: {{full_path}},
        action: {{ action_label }},
        name: {{ route_name }},
        {% if constraints %}
          constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
        {% end %}
        handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
          {{ cconst.id }}.new(request, response).{{ action_ref.id }}
        }
      )
    {% end %}
    {% if named %}
      {% helper_parts = full_path.split("/").reject(&.empty?) %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") || part.starts_with?("*") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = "#{nsf.id}#{named.id}_path" %}
      {% if helper_params.size > 0 %}
        module RouteHelpers
          def {{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String) : String
            {{helper_expr.join(" + ").id}}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% else %}
        module RouteHelpers
          def {{helper_name.id}} : String
            {{ full_path }}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% end %}
    {% end %}
  end

  # Registers the application root route (`/`), named `root_path`.
  macro root(to = nil, named = nil, namespace = nil, &block)
    {% route_name = named ? named.id.stringify : "root" %}
    {% if to %}
      {% if block %}
        {% raise "a route cannot combine `to:` with a handler block: #{to}" %}
      {% end %}
    {% end %}
    {% if block %}
      {% if block.args.size != 2 %}
        {% raise "route handler blocks must declare exactly two parameters — |request, response|" %}
      {% end %}
    {% end %}
    {% ns = namespace ? namespace + "/" : "" %}
    {% nsf = namespace ? namespace.split("/").join("_") + "_" : "" %}
  {% if block %}
    Altair::Routing.route_set_for({{@type}}).register(
      method: "GET",
      pattern: {{ ns == "" ? "/" : "/" + ns[0..-2] }},
      action: nil,
        name: {{ route_name }},
        handler: ->({{block.args[0].id}} : Altair::HTTP::Request, {{block.args[1].id}} : Altair::HTTP::Response) {
          {{ block.body }}
        }
      )
    {% else %}
      {% if to == nil %}
        {% raise "a route must declare an action with `to:` or a handler block" %}
      {% end %}
      {% if to.is_a?(Call) %}
        {% cconst = to.receiver %}
        {% action_ref = to.name %}
        {% action_label = cconst.id.stringify + "#" + action_ref.id.stringify %}
      {% else %}
        {% cparts = (ns + to.split("#")[0]).split("/") %}
        {% cconst = cparts.map(&.camelcase).join("::") + "Controller" %}
        {% action_ref = to.split("#")[1] %}
        {% action_label = ns + to %}
      {% end %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "GET",
        pattern: {{ ns == "" ? "/" : "/" + ns[0..-2] }},
        action: {{ action_label }},
        name: {{ route_name }},
        handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
          {{ cconst.id }}.new(request, response).{{ action_ref.id }}
        }
      )
    {% end %}
    {% helper_name = "#{nsf.id}#{route_name.id}_path" %}
    module RouteHelpers
      def {{helper_name.id}} : String
        {{ ns == "" ? "/" : "/" + ns[0..-2] }}
      end
    end
    include RouteHelpers
    extend RouteHelpers
  end

  # Custom member routes inside a `resources` block. Each verb call names an
  # action as a symbol; it expands to `<resource>/:id/<action>` with a path
  # helper named `<action>_<singular>_path` (`get :preview` on
  # `resources :posts` gives `GET /posts/:id/preview` and
  # `preview_post_path(id)`). A `named:` argument overrides the helper name.
  macro member(base_path = nil, controller = nil, helper = nil, nsf = nil, constraints = nil, &block)
    {% raise "member can only be used inside a resources block" unless base_path %}
    {% if block %}
      {% if block.body.is_a?(NestedExpression) || block.body.is_a?(Expressions) %}
        {% body_exprs = block.body.expressions %}
      {% else %}
        {% body_exprs = [block.body] %}
      {% end %}
      {% for expr in body_exprs %}
        {% if expr.is_a?(Call) && (expr.name == :get || expr.name == :post || expr.name == :put || expr.name == :patch || expr.name == :delete) && expr.args.size > 0 && expr.args[0].is_a?(SymbolLiteral) %}
          {% if expr.block %}
            {{ expr.name.id }}({{ base_path + "/" + expr.args[0].id.stringify }}{% if constraints %}, constraints: {{ constraints }}{% end %}){{ expr.block }}
          {% else %}
            {% named_value = nil %}
            {% if expr.named_args %}
              {% for na in expr.named_args %}
                {% if na.name.id.stringify == "named" %}
                  {% named_value = na.value %}
                {% end %}
              {% end %}
            {% end %}
            {% auto_named = (nsf.id.stringify + expr.args[0].id.stringify + "_" + helper.id.stringify) %}
            {% route_name = named_value ? named_value : auto_named %}
            {{ expr.name.id }}({{ base_path + "/" + expr.args[0].id.stringify }}, to: {{ controller + "#" + expr.args[0].id.stringify }}, named: {{ route_name.id }}{% if constraints %}, constraints: {{ constraints }}{% end %})
          {% end %}
        {% else %}
          {{ expr }}
        {% end %}
      {% end %}
    {% end %}
  end

  # Custom collection routes inside a `resources` block. Each verb call names
  # an action as a symbol; it expands to `<resource>/<action>` with a path
  # helper named `<action>_<plural>_path` (`get :export` on
  # `resources :posts` gives `GET /posts/export` and `export_posts_path`).
  # A `named:` argument overrides the helper name.
  macro collection(base_path = nil, controller = nil, helper = nil, nsf = nil, constraints = nil, &block)
    {% raise "collection can only be used inside a resources block" unless base_path %}
    {% if block %}
      {% if block.body.is_a?(NestedExpression) || block.body.is_a?(Expressions) %}
        {% body_exprs = block.body.expressions %}
      {% else %}
        {% body_exprs = [block.body] %}
      {% end %}
      {% for expr in body_exprs %}
        {% if expr.is_a?(Call) && (expr.name == :get || expr.name == :post || expr.name == :put || expr.name == :patch || expr.name == :delete) && expr.args.size > 0 && expr.args[0].is_a?(SymbolLiteral) %}
          {% if expr.block %}
            {{ expr.name.id }}({{ base_path + "/" + expr.args[0].id.stringify }}{% if constraints %}, constraints: {{ constraints }}{% end %}){{ expr.block }}
          {% else %}
            {% named_value = nil %}
            {% if expr.named_args %}
              {% for na in expr.named_args %}
                {% if na.name.id.stringify == "named" %}
                  {% named_value = na.value %}
                {% end %}
              {% end %}
            {% end %}
            {% auto_named = (nsf.id.stringify + expr.args[0].id.stringify + "_" + helper.id.stringify) %}
            {% route_name = named_value ? named_value : auto_named %}
            {{ expr.name.id }}({{ base_path + "/" + expr.args[0].id.stringify }}, to: {{ controller + "#" + expr.args[0].id.stringify }}, named: {{ route_name.id }}{% if constraints %}, constraints: {{ constraints }}{% end %})
          {% end %}
        {% else %}
          {{ expr }}
        {% end %}
      {% end %}
    {% end %}
  end

  # Generates the seven RESTful routes for a resource. Supports the
  # conventional options: `only:` and `except:`. The block adds custom
  # `member`/`collection` routes and nested `resources`:
  #
  # ```
  # resources :posts do
  #   member { get :preview }            # GET /posts/:id/preview
  #   collection { get :export }         # GET /posts/export
  #   resources :comments, only: :create # POST /posts/:post_id/comments
  # end
  # ```
  # `constraints:` limits every generated route's matching to the given
  # parameter regexes (`resources :posts, constraints: { id: /\d+/ }`) and
  # applies (by name) to `member`/`collection` routes and nested resources.
  macro resources(name, only = nil, except = nil, namespace = nil, parent_path = nil, parent_helper = nil, constraints = nil, &block)
    {% singular = name.id.stringify %}
    {% if singular == "person" %}
      {% base = "person" %}
    {% elsif singular == "children" %}
      {% base = "child" %}
    {% elsif singular == "men" %}
      {% base = "man" %}
    {% elsif singular == "women" %}
      {% base = "woman" %}
    {% elsif singular == "feet" %}
      {% base = "foot" %}
    {% elsif singular == "teeth" %}
      {% base = "tooth" %}
    {% elsif singular == "geese" %}
      {% base = "goose" %}
    {% elsif singular == "mice" %}
      {% base = "mouse" %}
    {% elsif singular == "people" %}
      {% base = "person" %}
    {% elsif singular == "sheep" || singular == "fish" || singular == "deer" || singular == "series" || singular == "species" || singular == "news" %}
      {% base = singular %}
    {% elsif singular.ends_with?("ies") && singular.size > 3 %}
      {% base = singular[0..-4] + "y" %}
    {% elsif singular.ends_with?("ves") %}
      {% base = singular[0..-4] + "f" %}
    {% elsif singular.ends_with?("les") %}
      {% base = singular[0..-2] %}
    {% elsif singular.ends_with?("es") %}
      {% base = singular[0..-3] %}
      {% if !(base.ends_with?("s") || base.ends_with?("x") || base.ends_with?("z") || base.ends_with?("ch") || base.ends_with?("sh") || base.ends_with?("o")) %}
        {% base = singular[0..-2] %}
      {% end %}
    {% elsif singular.ends_with?("s") %}
      {% base = singular[0..-2] %}
    {% else %}
      {% base = singular %}
    {% end %}
    {% if base == "person" %}
      {% plural = "people" %}
    {% elsif base == "child" %}
      {% plural = "children" %}
    {% elsif base == "man" %}
      {% plural = "men" %}
    {% elsif base == "woman" %}
      {% plural = "women" %}
    {% elsif base == "foot" %}
      {% plural = "feet" %}
    {% elsif base == "tooth" %}
      {% plural = "teeth" %}
    {% elsif base == "goose" %}
      {% plural = "geese" %}
    {% elsif base == "mouse" %}
      {% plural = "mice" %}
    {% elsif base == "sheep" || base == "fish" || base == "deer" || base == "series" || base == "species" || base == "news" %}
      {% plural = base %}
    {% elsif base.ends_with?("fe") %}
      {% plural = base[0..-3] + "ves" %}
    {% elsif base.ends_with?("f") %}
      {% plural = base[0..-2] + "ves" %}
    {% elsif base.ends_with?("s") || base.ends_with?("x") || base.ends_with?("z") || base.ends_with?("ch") || base.ends_with?("sh") %}
      {% plural = base + "es" %}
    {% elsif base.ends_with?("y") && !"aeiou".includes?(base[-2]) %}
      {% plural = base[0..-2] + "ies" %}
    {% else %}
      {% plural = base + "s" %}
    {% end %}
    {% ns = namespace ? namespace + "/" : "" %}
    {% nsf = namespace ? namespace.split("/").join("_") + "_" : "" %}
    {% cpath = ns + plural %}
    {% parent_prefix = parent_helper ? parent_helper + "/" : "" %}
    {% plural_path = parent_path ? parent_path + "/" + plural : "/" + ns + plural %}
    {% new_path = plural_path + "/new" %}
    {% member_path = plural_path + "/:id" %}
    {% edit_path = member_path + "/edit" %}
    {% cparts = cpath.split("/") %}
    {% cconst = cparts.map(&.camelcase).join("::") + "Controller" %}
    {% ph = parent_helper ? parent_helper.id.stringify : "" %}
    {% name_plural = nsf + ph + plural + "_path" %}
    {% name_new = "new_" + nsf + ph + base + "_path" %}
    {% name_member = nsf + ph + base + "_path" %}
    {% name_edit = "edit_" + nsf + ph + base + "_path" %}
    {% actions = [:index, :new, :create, :show, :edit, :update, :destroy] %}
    {% only_list = only.is_a?(SymbolLiteral) ? [only] : only %}
    {% except_list = except.is_a?(SymbolLiteral) ? [except] : except %}
    {% if block %}
      {% if block.body.is_a?(NestedExpression) || block.body.is_a?(Expressions) %}
        {% body_exprs = block.body.expressions %}
      {% else %}
        {% body_exprs = [block.body] %}
      {% end %}
      {% child_helper = parent_helper ? parent_helper.id.stringify + base + "_" : base + "_" %}
      {% child_parent_path = plural_path + "/:" + base + "_id" %}
      {% member_helper = parent_helper ? parent_helper.id.stringify + base : base %}
      {% collection_helper = parent_helper ? parent_helper.id.stringify + plural : plural %}
    {% end %}
    {% if only_list %}
      {% actions = actions.select { |action| only_list.map(&.id.stringify).includes?(action.id.stringify) } %}
    {% end %}
    {% if except_list %}
      {% actions = actions.reject { |action| except_list.map(&.id.stringify).includes?(action.id.stringify) } %}
    {% end %}
    {% if block %}
      {% for expr in body_exprs %}
        {% if expr.is_a?(Call) && expr.name == :collection %}
          {{ expr.name.id }}(base_path: {{ plural_path }}, controller: {{ cpath }}, helper: {{ collection_helper }}, nsf: {{ nsf }}{% if constraints %}, constraints: {{ constraints }}{% end %}){% if expr.block %} {{ expr.block }}{% end %}
        {% end %}
      {% end %}
    {% end %}
    {% for action in actions %}
      {% if action.id.stringify == "index" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "GET",
          pattern: {{ plural_path }},
          action: {{ cpath + "#index" }},
          name: {{ name_plural }},
          {% if constraints %}
            constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
          {% end %}
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.new(request, response).index
          }
        )
      {% elsif action.id.stringify == "new" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "GET",
          pattern: {{ new_path }},
          action: {{ cpath + "#new" }},
          name: {{ name_new }},
          {% if constraints %}
            constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
          {% end %}
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.new(request, response).new
          }
        )
      {% elsif action.id.stringify == "create" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "POST",
          pattern: {{ plural_path }},
          action: {{ cpath + "#create" }},
          name: {{ name_plural }},
          {% if constraints %}
            constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
          {% end %}
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.new(request, response).create
          }
        )
      {% elsif action.id.stringify == "show" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "GET",
          pattern: {{ member_path }},
          action: {{ cpath + "#show" }},
          name: {{ name_member }},
          {% if constraints %}
            constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
          {% end %}
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.new(request, response).show
          }
        )
      {% elsif action.id.stringify == "edit" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "GET",
          pattern: {{ edit_path }},
          action: {{ cpath + "#edit" }},
          name: {{ name_edit }},
          {% if constraints %}
            constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
          {% end %}
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.new(request, response).edit
          }
        )
      {% elsif action.id.stringify == "update" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "PUT",
          pattern: {{ member_path }},
          action: {{ cpath + "#update" }},
          name: {{ name_member }},
          {% if constraints %}
            constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
          {% end %}
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.new(request, response).update
          }
        )
        Altair::Routing.route_set_for({{@type}}).register(
          method: "PATCH",
          pattern: {{ member_path }},
          action: {{ cpath + "#update" }},
          name: {{ name_member }},
          {% if constraints %}
            constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
          {% end %}
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.new(request, response).update
          }
        )
      {% elsif action.id.stringify == "destroy" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "DELETE",
          pattern: {{ member_path }},
          action: {{ cpath + "#destroy" }},
          name: {{ name_member }},
          {% if constraints %}
            constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
          {% end %}
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.new(request, response).destroy
          }
        )
      {% end %}
    {% end %}
    {% if actions.map(&.id.stringify).includes?("index") || actions.map(&.id.stringify).includes?("create") %}
      {% helper_parts = plural_path.split("/").reject(&.empty?) %}
      {% full_path = "/" + helper_parts.join("/") %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") || part.starts_with?("*") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = name_plural %}
      {% if helper_params.size > 0 %}
        module RouteHelpers
          def {{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String) : String
            {{helper_expr.join(" + ").id}}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% else %}
        module RouteHelpers
          def {{helper_name.id}} : String
            {{ full_path }}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% end %}
    {% end %}
    {% if actions.map(&.id.stringify).includes?("new") %}
      {% helper_parts = new_path.split("/").reject(&.empty?) %}
      {% full_path = "/" + helper_parts.join("/") %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") || part.starts_with?("*") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = name_new %}
      {% if helper_params.size > 0 %}
        module RouteHelpers
          def {{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String) : String
            {{helper_expr.join(" + ").id}}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% else %}
        module RouteHelpers
          def {{helper_name.id}} : String
            {{ full_path }}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% end %}
    {% end %}
    {% if actions.map(&.id.stringify).includes?("show") || actions.map(&.id.stringify).includes?("update") || actions.map(&.id.stringify).includes?("destroy") %}
      {% helper_parts = member_path.split("/").reject(&.empty?) %}
      {% full_path = "/" + helper_parts.join("/") %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") || part.starts_with?("*") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = name_member %}
      {% if helper_params.size > 0 %}
        module RouteHelpers
          def {{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String) : String
            {{helper_expr.join(" + ").id}}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% else %}
        module RouteHelpers
          def {{helper_name.id}} : String
            {{ full_path }}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% end %}
    {% end %}
    {% if actions.map(&.id.stringify).includes?("edit") %}
      {% helper_parts = edit_path.split("/").reject(&.empty?) %}
      {% full_path = "/" + helper_parts.join("/") %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") || part.starts_with?("*") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = name_edit %}
      {% if helper_params.size > 0 %}
        module RouteHelpers
          def {{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String) : String
            {{helper_expr.join(" + ").id}}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% else %}
        module RouteHelpers
          def {{helper_name.id}} : String
            {{ full_path }}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% end %}
    {% end %}
    {% if block %}
      {% for expr in body_exprs %}
        {% if expr.is_a?(Call) && expr.name == :member %}
          {{ expr.name.id }}(base_path: {{ member_path }}, controller: {{ cpath }}, helper: {{ member_helper }}, nsf: {{ nsf }}{% if constraints %}, constraints: {{ constraints }}{% end %}){% if expr.block %} {{ expr.block }}{% end %}
        {% elsif expr.is_a?(Call) && (expr.name == :collection || (expr.name == :resources && !expr.args) || (expr.name == :resource && !expr.args)) %}
        {% elsif expr.is_a?(Call) && (expr.name == :resources || expr.name == :resource) && expr.args %}
          {% if expr.named_args %}
            {{ expr.name.id }}({{ expr.args.splat }}, {{ expr.named_args.splat }}, namespace: {{ namespace }}, parent_path: {{ child_parent_path }}, parent_helper: {{ child_helper }}{% if constraints %}, constraints: {{ constraints }}{% end %}){% if expr.block %} {{ expr.block }}{% end %}
          {% else %}
            {{ expr.name.id }}({{ expr.args.splat }}, namespace: {{ namespace }}, parent_path: {{ child_parent_path }}, parent_helper: {{ child_helper }}{% if constraints %}, constraints: {{ constraints }}{% end %}){% if expr.block %} {{ expr.block }}{% end %}
          {% end %}
        {% else %}
          {{ expr }}
        {% end %}
      {% end %}
    {% end %}
  end

  # Generates the six RESTful routes for a singular resource — the same
  # actions as `resources` without `index` and without an `:id` parameter:
  #
  # ```
  # resource :profile
  # ```
  #
  # expands to `new`/`create`/`show`/`edit`/`update`/`destroy` on
  # `/profile`, dispatching to the plural `ProfilesController`, and
  # generates the no-argument helpers `profile_path`, `new_profile_path`
  # and `edit_profile_path`. `only:` and `except:` filter the actions, and
  # `constraints:` applies to the (id-less) routes and nested children. The
  # block mirrors `resources`: custom `member`/`collection` routes carry no
  # id, and nested `resources` or another singular `resource` hang off the
  # singular path without a parent parameter:
  #
  # ```
  # resource :profile do
  #   member { get :preview }    # GET /profile/preview
  #   collection { get :export } # GET /profile/export
  #   resources :comments        # GET /profile/comments, ...
  # end
  # ```
  macro resource(name, only = nil, except = nil, namespace = nil, parent_path = nil, parent_helper = nil, constraints = nil, &block)
    {% singular = name.id.stringify %}
    {% if singular == "person" %}
      {% plural = "people" %}
    {% elsif singular == "child" %}
      {% plural = "children" %}
    {% elsif singular == "man" %}
      {% plural = "men" %}
    {% elsif singular == "woman" %}
      {% plural = "women" %}
    {% elsif singular == "foot" %}
      {% plural = "feet" %}
    {% elsif singular == "tooth" %}
      {% plural = "teeth" %}
    {% elsif singular == "goose" %}
      {% plural = "geese" %}
    {% elsif singular == "mouse" %}
      {% plural = "mice" %}
    {% elsif singular == "sheep" || singular == "fish" || singular == "deer" || singular == "series" || singular == "species" || singular == "news" || singular == "settings" %}
      {% plural = singular %}
    {% elsif singular.ends_with?("fe") %}
      {% plural = singular[0..-3] + "ves" %}
    {% elsif singular.ends_with?("f") %}
      {% plural = singular[0..-2] + "ves" %}
    {% elsif singular.ends_with?("s") || singular.ends_with?("x") || singular.ends_with?("z") || singular.ends_with?("ch") || singular.ends_with?("sh") %}
      {% plural = singular + "es" %}
    {% elsif singular.ends_with?("y") && !"aeiou".includes?(singular[-2]) %}
      {% plural = singular[0..-2] + "ies" %}
    {% else %}
      {% plural = singular + "s" %}
    {% end %}
    {% ns = namespace ? namespace + "/" : "" %}
    {% nsf = namespace ? namespace.split("/").join("_") + "_" : "" %}
    {% cpath = ns + plural %}
    {% base_path = parent_path ? parent_path + "/" + singular : "/" + ns + singular %}
    {% new_path = base_path + "/new" %}
    {% edit_path = base_path + "/edit" %}
    {% cparts = cpath.split("/") %}
    {% cconst = cparts.map(&.camelcase).join("::") + "Controller" %}
    {% ph = parent_helper ? parent_helper.id.stringify : "" %}
    {% name_plural = nsf + ph + singular + "_path" %}
    {% name_new = "new_" + nsf + ph + singular + "_path" %}
    {% name_edit = "edit_" + nsf + ph + singular + "_path" %}
    {% actions = [:new, :create, :show, :edit, :update, :destroy] %}
    {% only_list = only.is_a?(SymbolLiteral) ? [only] : only %}
    {% except_list = except.is_a?(SymbolLiteral) ? [except] : except %}
    {% if block %}
      {% if block.body.is_a?(NestedExpression) || block.body.is_a?(Expressions) %}
        {% body_exprs = block.body.expressions %}
      {% else %}
        {% body_exprs = [block.body] %}
      {% end %}
      {% child_helper = parent_helper ? parent_helper.id.stringify + singular + "_" : singular + "_" %}
      {% member_helper = parent_helper ? parent_helper.id.stringify + singular : singular %}
    {% end %}
    {% if only_list %}
      {% actions = actions.select { |action| only_list.map(&.id.stringify).includes?(action.id.stringify) } %}
    {% end %}
    {% if except_list %}
      {% actions = actions.reject { |action| except_list.map(&.id.stringify).includes?(action.id.stringify) } %}
    {% end %}
    {% if block %}
      {% for expr in body_exprs %}
        {% if expr.is_a?(Call) && expr.name == :collection %}
          {{ expr.name.id }}(base_path: {{ base_path }}, controller: {{ cpath }}, helper: {{ member_helper }}, nsf: {{ nsf }}{% if constraints %}, constraints: {{ constraints }}{% end %}){% if expr.block %} {{ expr.block }}{% end %}
        {% end %}
      {% end %}
    {% end %}
    {% for action in actions %}
      {% if action.id.stringify == "new" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "GET",
          pattern: {{ new_path }},
          action: {{ cpath + "#new" }},
          name: {{ name_new }},
          {% if constraints %}
            constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
          {% end %}
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.new(request, response).new
          }
        )
      {% elsif action.id.stringify == "create" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "POST",
          pattern: {{ base_path }},
          action: {{ cpath + "#create" }},
          name: {{ name_plural }},
          {% if constraints %}
            constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
          {% end %}
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.new(request, response).create
          }
        )
      {% elsif action.id.stringify == "show" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "GET",
          pattern: {{ base_path }},
          action: {{ cpath + "#show" }},
          name: {{ name_plural }},
          {% if constraints %}
            constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
          {% end %}
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.new(request, response).show
          }
        )
      {% elsif action.id.stringify == "edit" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "GET",
          pattern: {{ edit_path }},
          action: {{ cpath + "#edit" }},
          name: {{ name_edit }},
          {% if constraints %}
            constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
          {% end %}
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.new(request, response).edit
          }
        )
      {% elsif action.id.stringify == "update" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "PUT",
          pattern: {{ base_path }},
          action: {{ cpath + "#update" }},
          name: {{ name_plural }},
          {% if constraints %}
            constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
          {% end %}
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.new(request, response).update
          }
        )
        Altair::Routing.route_set_for({{@type}}).register(
          method: "PATCH",
          pattern: {{ base_path }},
          action: {{ cpath + "#update" }},
          name: {{ name_plural }},
          {% if constraints %}
            constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
          {% end %}
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.new(request, response).update
          }
        )
      {% elsif action.id.stringify == "destroy" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "DELETE",
          pattern: {{ base_path }},
          action: {{ cpath + "#destroy" }},
          name: {{ name_plural }},
          {% if constraints %}
            constraints: { {% for ck, cv in constraints %}"{{ ck.id }}" => {{ cv }}, {% end %} },
          {% end %}
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.new(request, response).destroy
          }
        )
      {% end %}
    {% end %}
    {% if actions.map(&.id.stringify).includes?("new") || actions.map(&.id.stringify).includes?("create") || actions.map(&.id.stringify).includes?("show") || actions.map(&.id.stringify).includes?("update") || actions.map(&.id.stringify).includes?("destroy") %}
      {% helper_parts = base_path.split("/").reject(&.empty?) %}
      {% full_path = "/" + helper_parts.join("/") %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") || part.starts_with?("*") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = name_plural %}
      {% if helper_params.size > 0 %}
        module RouteHelpers
          def {{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String) : String
            {{helper_expr.join(" + ").id}}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% else %}
        module RouteHelpers
          def {{helper_name.id}} : String
            {{ full_path }}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% end %}
    {% end %}
    {% if actions.map(&.id.stringify).includes?("new") %}
      {% helper_parts = new_path.split("/").reject(&.empty?) %}
      {% full_path = "/" + helper_parts.join("/") %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") || part.starts_with?("*") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = name_new %}
      {% if helper_params.size > 0 %}
        module RouteHelpers
          def {{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String) : String
            {{helper_expr.join(" + ").id}}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% else %}
        module RouteHelpers
          def {{helper_name.id}} : String
            {{ full_path }}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% end %}
    {% end %}
    {% if actions.map(&.id.stringify).includes?("edit") %}
      {% helper_parts = edit_path.split("/").reject(&.empty?) %}
      {% full_path = "/" + helper_parts.join("/") %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") || part.starts_with?("*") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = name_edit %}
      {% if helper_params.size > 0 %}
        module RouteHelpers
          def {{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String) : String
            {{helper_expr.join(" + ").id}}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% else %}
        module RouteHelpers
          def {{helper_name.id}} : String
            {{ full_path }}
          end
        end
        include RouteHelpers
        extend RouteHelpers
      {% end %}
    {% end %}
    {% if block %}
      {% for expr in body_exprs %}
        {% if expr.is_a?(Call) && expr.name == :member %}
          {{ expr.name.id }}(base_path: {{ base_path }}, controller: {{ cpath }}, helper: {{ member_helper }}, nsf: {{ nsf }}{% if constraints %}, constraints: {{ constraints }}{% end %}){% if expr.block %} {{ expr.block }}{% end %}
        {% elsif expr.is_a?(Call) && expr.name == :collection %}
        {% elsif expr.is_a?(Call) && (expr.name == :resources || expr.name == :resource) && expr.args %}
          {% if expr.named_args %}
            {{ expr.name.id }}({{ expr.args.splat }}, {{ expr.named_args.splat }}, namespace: {{ namespace }}, parent_path: {{ base_path }}, parent_helper: {{ child_helper }}{% if constraints %}, constraints: {{ constraints }}{% end %}){% if expr.block %} {{ expr.block }}{% end %}
          {% else %}
            {{ expr.name.id }}({{ expr.args.splat }}, namespace: {{ namespace }}, parent_path: {{ base_path }}, parent_helper: {{ child_helper }}{% if constraints %}, constraints: {{ constraints }}{% end %}){% if expr.block %} {{ expr.block }}{% end %}
          {% end %}
        {% else %}
          {{ expr }}
        {% end %}
      {% end %}
    {% end %}
  end

  # Registers a permanent redirect: `redirect "/old/draft", to: "/posts"`
  # answers every method on `/old/draft` with 301 (Moved Permanently) and
  # a `Location` header pointing at the destination. Redirects match any
  # method but never appear in a 405 `Allow` header.
  macro redirect(path, to, namespace = nil)
    {% full_path = namespace ? "/" + namespace + path : path %}
    Altair::Routing.route_set_for({{@type}}).register(
      method: "ANY",
      pattern: {{ full_path }},
      action: nil,
      name: nil,
      handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
        response.status = ::HTTP::Status::MOVED_PERMANENTLY
        response.headers["Location"] = {{ to }}
      }
    )
  end

  # `admin_posts_path`. Namespaces nest.
  macro namespace(scope, namespace = nil, &block)
    {% ns = namespace ? namespace.id.stringify + "/" + scope.id.stringify : scope.id.stringify %}
    {% if block.body.is_a?(NestedExpression) || block.body.is_a?(Expressions) %}
      {% body_exprs = block.body.expressions %}
    {% else %}
      {% body_exprs = [block.body] %}
    {% end %}
    {% for expr in body_exprs %}
      {% if expr.is_a?(Call) && (expr.name == :get || expr.name == :post || expr.name == :put || expr.name == :patch || expr.name == :delete || expr.name == :root || expr.name == :resources || expr.name == :resource || expr.name == :redirect || expr.name == :namespace) %}
        {% if expr.args %}
          {% if expr.named_args %}
            {{ expr.name.id }}({{ expr.args.splat }}, {{ expr.named_args.splat }}, namespace: {{ ns }}){% if expr.block %} {{ expr.block }}{% end %}
          {% else %}
            {{ expr.name.id }}({{ expr.args.splat }}, namespace: {{ ns }}){% if expr.block %} {{ expr.block }}{% end %}
          {% end %}
        {% else %}
          {% if expr.named_args %}
            {{ expr.name.id }}({{ expr.named_args.splat }}, namespace: {{ ns }}){% if expr.block %} {{ expr.block }}{% end %}
          {% else %}
            {{ expr.name.id }}(namespace: {{ ns }})
          {% end %}
        {% end %}
      {% else %}
        {{ expr }}
      {% end %}
    {% end %}
  end
end
