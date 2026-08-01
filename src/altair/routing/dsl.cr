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
  # block replaces both.
  macro get(path, to = nil, named = nil, namespace = nil, &block)
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
        handler: ->({{block.args[0].id}} : Altair::HTTP::Request, {{block.args[1].id}} : Altair::HTTP::Response) {
          {{ block.body }}
        }
      )
    {% else %}
      {% if to == nil %}
        {% raise "a route must declare an action with `to:` or a handler block: #{path}" %}
      {% end %}
      {% cparts = (ns + to.split("#")[0]).split("/") %}
      {% cconst = cparts.map(&.camelcase).join("::") + "Controller" %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "GET",
        pattern: {{full_path}},
        action: {{ns + to}},
        name: {{ route_name }},
        handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
          {{ cconst.id }}.{{ to.split("#")[1].id }}(request, response)
        }
      )
    {% end %}
    {% if named %}
      {% helper_parts = full_path.split("/").reject(&.empty?) %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = "#{nsf.id}#{named.id}_path" %}
      {% if helper_params.size > 0 %}
        def self.{{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String)
          {{helper_expr.join(" + ").id}}
        end
      {% else %}
        def self.{{helper_name.id}}
          {{ full_path }}
        end
      {% end %}
    {% end %}
  end

  # Registers a `POST` route.
  macro post(path, to = nil, named = nil, namespace = nil, &block)
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
        handler: ->({{block.args[0].id}} : Altair::HTTP::Request, {{block.args[1].id}} : Altair::HTTP::Response) {
          {{ block.body }}
        }
      )
    {% else %}
      {% if to == nil %}
        {% raise "a route must declare an action with `to:` or a handler block: #{path}" %}
      {% end %}
      {% cparts = (ns + to.split("#")[0]).split("/") %}
      {% cconst = cparts.map(&.camelcase).join("::") + "Controller" %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "POST",
        pattern: {{full_path}},
        action: {{ns + to}},
        name: {{ route_name }},
        handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
          {{ cconst.id }}.{{ to.split("#")[1].id }}(request, response)
        }
      )
    {% end %}
    {% if named %}
      {% helper_parts = full_path.split("/").reject(&.empty?) %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = "#{nsf.id}#{named.id}_path" %}
      {% if helper_params.size > 0 %}
        def self.{{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String)
          {{helper_expr.join(" + ").id}}
        end
      {% else %}
        def self.{{helper_name.id}}
          {{ full_path }}
        end
      {% end %}
    {% end %}
  end

  # Registers a `PUT` route.
  macro put(path, to = nil, named = nil, namespace = nil, &block)
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
        handler: ->({{block.args[0].id}} : Altair::HTTP::Request, {{block.args[1].id}} : Altair::HTTP::Response) {
          {{ block.body }}
        }
      )
    {% else %}
      {% if to == nil %}
        {% raise "a route must declare an action with `to:` or a handler block: #{path}" %}
      {% end %}
      {% cparts = (ns + to.split("#")[0]).split("/") %}
      {% cconst = cparts.map(&.camelcase).join("::") + "Controller" %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "PUT",
        pattern: {{full_path}},
        action: {{ns + to}},
        name: {{ route_name }},
        handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
          {{ cconst.id }}.{{ to.split("#")[1].id }}(request, response)
        }
      )
    {% end %}
    {% if named %}
      {% helper_parts = full_path.split("/").reject(&.empty?) %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = "#{nsf.id}#{named.id}_path" %}
      {% if helper_params.size > 0 %}
        def self.{{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String)
          {{helper_expr.join(" + ").id}}
        end
      {% else %}
        def self.{{helper_name.id}}
          {{ full_path }}
        end
      {% end %}
    {% end %}
  end

  # Registers a `PATCH` route.
  macro patch(path, to = nil, named = nil, namespace = nil, &block)
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
        handler: ->({{block.args[0].id}} : Altair::HTTP::Request, {{block.args[1].id}} : Altair::HTTP::Response) {
          {{ block.body }}
        }
      )
    {% else %}
      {% if to == nil %}
        {% raise "a route must declare an action with `to:` or a handler block: #{path}" %}
      {% end %}
      {% cparts = (ns + to.split("#")[0]).split("/") %}
      {% cconst = cparts.map(&.camelcase).join("::") + "Controller" %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "PATCH",
        pattern: {{full_path}},
        action: {{ns + to}},
        name: {{ route_name }},
        handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
          {{ cconst.id }}.{{ to.split("#")[1].id }}(request, response)
        }
      )
    {% end %}
    {% if named %}
      {% helper_parts = full_path.split("/").reject(&.empty?) %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = "#{nsf.id}#{named.id}_path" %}
      {% if helper_params.size > 0 %}
        def self.{{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String)
          {{helper_expr.join(" + ").id}}
        end
      {% else %}
        def self.{{helper_name.id}}
          {{ full_path }}
        end
      {% end %}
    {% end %}
  end

  # Registers a `DELETE` route.
  macro delete(path, to = nil, named = nil, namespace = nil, &block)
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
        handler: ->({{block.args[0].id}} : Altair::HTTP::Request, {{block.args[1].id}} : Altair::HTTP::Response) {
          {{ block.body }}
        }
      )
    {% else %}
      {% if to == nil %}
        {% raise "a route must declare an action with `to:` or a handler block: #{path}" %}
      {% end %}
      {% cparts = (ns + to.split("#")[0]).split("/") %}
      {% cconst = cparts.map(&.camelcase).join("::") + "Controller" %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "DELETE",
        pattern: {{full_path}},
        action: {{ns + to}},
        name: {{ route_name }},
        handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
          {{ cconst.id }}.{{ to.split("#")[1].id }}(request, response)
        }
      )
    {% end %}
    {% if named %}
      {% helper_parts = full_path.split("/").reject(&.empty?) %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = "#{nsf.id}#{named.id}_path" %}
      {% if helper_params.size > 0 %}
        def self.{{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String)
          {{helper_expr.join(" + ").id}}
        end
      {% else %}
        def self.{{helper_name.id}}
          {{ full_path }}
        end
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
      {% cparts = (ns + to.split("#")[0]).split("/") %}
      {% cconst = cparts.map(&.camelcase).join("::") + "Controller" %}
      Altair::Routing.route_set_for({{@type}}).register(
        method: "GET",
        pattern: {{ ns == "" ? "/" : "/" + ns[0..-2] }},
        action: {{ns + to}},
        name: {{ route_name }},
        handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
          {{ cconst.id }}.{{ to.split("#")[1].id }}(request, response)
        }
      )
    {% end %}
    {% helper_name = "#{nsf.id}#{route_name.id}_path" %}
    def self.{{helper_name.id}}
      {{ ns == "" ? "/" : "/" + ns[0..-2] }}
    end
  end

  # Generates the seven RESTful routes for a resource. Supports the
  # conventional options: `only:` and `except:`.
  macro resources(name, only = nil, except = nil, namespace = nil)
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
    {% plural_path = "/" + ns + plural %}
    {% new_path = plural_path + "/new" %}
    {% member_path = plural_path + "/:id" %}
    {% edit_path = member_path + "/edit" %}
    {% cparts = cpath.split("/") %}
    {% cconst = cparts.map(&.camelcase).join("::") + "Controller" %}
    {% name_plural = nsf + plural + "_path" %}
    {% name_new = "new_" + nsf + base + "_path" %}
    {% name_member = nsf + base + "_path" %}
    {% name_edit = "edit_" + nsf + base + "_path" %}
    {% actions = [:index, :new, :create, :show, :edit, :update, :destroy] %}
    {% if only %}
      {% actions = actions.select { |action| only.map(&.id.stringify).includes?(action.id.stringify) } %}
    {% end %}
    {% if except %}
      {% actions = actions.reject { |action| except.map(&.id.stringify).includes?(action.id.stringify) } %}
    {% end %}
    {% for action in actions %}
      {% if action.id.stringify == "index" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "GET",
          pattern: {{ plural_path }},
          action: {{ cpath + "#index" }},
          name: {{ name_plural }},
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.index(request, response)
          }
        )
      {% elsif action.id.stringify == "new" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "GET",
          pattern: {{ new_path }},
          action: {{ cpath + "#new" }},
          name: {{ name_new }},
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.new(request, response)
          }
        )
      {% elsif action.id.stringify == "create" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "POST",
          pattern: {{ plural_path }},
          action: {{ cpath + "#create" }},
          name: {{ name_plural }},
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.create(request, response)
          }
        )
      {% elsif action.id.stringify == "show" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "GET",
          pattern: {{ member_path }},
          action: {{ cpath + "#show" }},
          name: {{ name_member }},
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.show(request, response)
          }
        )
      {% elsif action.id.stringify == "edit" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "GET",
          pattern: {{ edit_path }},
          action: {{ cpath + "#edit" }},
          name: {{ name_edit }},
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.edit(request, response)
          }
        )
      {% elsif action.id.stringify == "update" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "PUT",
          pattern: {{ member_path }},
          action: {{ cpath + "#update" }},
          name: {{ name_member }},
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.update(request, response)
          }
        )
        Altair::Routing.route_set_for({{@type}}).register(
          method: "PATCH",
          pattern: {{ member_path }},
          action: {{ cpath + "#update" }},
          name: {{ name_member }},
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.update(request, response)
          }
        )
      {% elsif action.id.stringify == "destroy" %}
        Altair::Routing.route_set_for({{@type}}).register(
          method: "DELETE",
          pattern: {{ member_path }},
          action: {{ cpath + "#destroy" }},
          name: {{ name_member }},
          handler: ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
            {{ cconst.id }}.destroy(request, response)
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
        {% if part.starts_with?(":") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = name_plural %}
      {% if helper_params.size > 0 %}
        def self.{{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String)
          {{helper_expr.join(" + ").id}}
        end
      {% else %}
        def self.{{helper_name.id}}
          {{ full_path }}
        end
      {% end %}
    {% end %}
    {% if actions.map(&.id.stringify).includes?("new") %}
      {% helper_parts = new_path.split("/").reject(&.empty?) %}
      {% full_path = "/" + helper_parts.join("/") %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = name_new %}
      {% if helper_params.size > 0 %}
        def self.{{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String)
          {{helper_expr.join(" + ").id}}
        end
      {% else %}
        def self.{{helper_name.id}}
          {{ full_path }}
        end
      {% end %}
    {% end %}
    {% if actions.map(&.id.stringify).includes?("show") || actions.map(&.id.stringify).includes?("update") || actions.map(&.id.stringify).includes?("destroy") %}
      {% helper_parts = member_path.split("/").reject(&.empty?) %}
      {% full_path = "/" + helper_parts.join("/") %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = name_member %}
      {% if helper_params.size > 0 %}
        def self.{{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String)
          {{helper_expr.join(" + ").id}}
        end
      {% else %}
        def self.{{helper_name.id}}
          {{ full_path }}
        end
      {% end %}
    {% end %}
    {% if actions.map(&.id.stringify).includes?("edit") %}
      {% helper_parts = edit_path.split("/").reject(&.empty?) %}
      {% full_path = "/" + helper_parts.join("/") %}
      {% helper_params = [] of String %}
      {% helper_expr = [] of String %}
      {% for part in helper_parts %}
        {% if part.starts_with?(":") %}
          {% pname = part[1..] %}
          {% helper_params << pname %}
          {% helper_expr << "\"/\" + " + pname + ".to_s" %}
        {% else %}
          {% helper_expr << "\"/#{part.id}\"" %}
        {% end %}
      {% end %}
      {% helper_name = name_edit %}
      {% if helper_params.size > 0 %}
        def self.{{helper_name.id}}({{helper_params.join(", ").id}} : Int32 | Int64 | String)
          {{helper_expr.join(" + ").id}}
        end
      {% else %}
        def self.{{helper_name.id}}
          {{ full_path }}
        end
      {% end %}
    {% end %}
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
      {% if expr.is_a?(Call) && (expr.name == :get || expr.name == :post || expr.name == :put || expr.name == :patch || expr.name == :delete || expr.name == :root || expr.name == :resources || expr.name == :namespace) %}
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
