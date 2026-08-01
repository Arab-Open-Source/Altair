# Altair — view helpers.
#
# The helpers every template can call: `link_to`, `content_tag`, `button_to`
# and `javascript_include_tag`. htmx is a first-class citizen: any attribute
# starting with `hx_` is emitted as `hx-*`, so `content_tag(:button, "Save",
# hx_post: "/posts", hx_target: "#list")` renders
# `hx-post="/posts" hx-target="#list"` — the framework's htmx support is a
# convention, not a dependency.
module Altair
  module View
    module Helpers
      # Renders a link: `<a href="path">name</a>`. Extra attributes are
      # passed through (and `hx_*` becomes `hx-*`):
      #
      # ```
      # link_to "Posts", posts_path, class: "nav"
      # link_to "Edit", edit_post_path(post.id), hx_get: edit_post_path(post.id)
      # ```
      def link_to(name : String, path : String, **attrs) : String
        String.build do |io|
          io << "<a href=\"" << Altair::View.escape(path) << '"'
          attrs.each do |key, value|
            io << ' ' << attribute_name(key) << "=\"" << Altair::View.escape(value.to_s) << '"'
          end
          io << '>' << Altair::View.escape(name) << "</a>"
        end
      end

      # Renders an element with an escaped content and attribute list:
      #
      # ```
      # content_tag(:h1, post.title)
      # content_tag(:button, "Save", type: "submit", hx_post: "/posts")
      # ```
      def content_tag(name : Symbol, content : String = "", **attrs) : String
        String.build do |io|
          io << '<' << name
          attrs.each do |key, value|
            io << ' ' << attribute_name(key) << "=\"" << Altair::View.escape(value.to_s) << '"'
          end
          io << '>' << Altair::View.escape(content) << "</" << name << '>'
        end
      end

      # Renders a form button that submits to `path`. Non-GET verbs are
      # sent through the `_method` override, so a `DELETE` works from a
      # plain form. htmx attributes can be passed straight through:
      #
      # ```
      # button_to "Delete", post_path(post.id), method: :delete,
      #   hx_delete: post_path(post.id), hx_target: "#post-#{post.id}",
      #   hx_swap: "outerHTML"
      # ```
      def button_to(name : String, path : String, method : Symbol = :post, **attrs) : String
        String.build do |io|
          io << "<form action=\"" << path << "\" method=\"post\""
          attrs.each do |key, value|
            io << ' ' << attribute_name(key) << "=\"" << Altair::View.escape(value.to_s) << '"'
          end
          io << '>'
          unless method.in?(:get, :post)
            io << "<input type=\"hidden\" name=\"_method\" value=\"" << method.to_s.upcase << "\">"
          end
          io << "<button>" << Altair::View.escape(name) << "</button></form>"
        end
      end

      # Includes a script tag. The only built-in asset is `:htmx`; the
      # source is resolved by priority: the `from:` argument, the
      # `config.htmx_src` setting, a URL built from `config.htmx_version`
      # (or the `version:` argument), and finally the framework's pinned
      # default CDN:
      #
      # ```
      # javascript_include_tag :htmx
      # javascript_include_tag :htmx, version: "2.0.4"
      # javascript_include_tag :htmx, from: "/js/htmx.min.js"
      # ```
      def javascript_include_tag(name : Symbol, *, version : String? = nil, from : String? = nil) : String
        raise ArgumentError.new("Unknown asset: #{name}") unless name == :htmx
        src = from || htmx_src(version)
        %(<script src="#{src}" defer></script>)
      end

      # Translates an attribute name: `hx_post` becomes `hx-post`,
      # `data_id` becomes `data-id`, and plain names are untouched.
      def attribute_name(key : Symbol) : String
        name = key.to_s
        if name.starts_with?("hx_") || name.starts_with?("data_") || name.starts_with?("aria_")
          name.gsub("_", "-")
        else
          name
        end
      end

      private def htmx_src(version : String?) : String
        return "https://unpkg.com/htmx.org@#{version}/dist/htmx.min.js" if version
        app = Altair.application_instance
        return Altair::Htmx::CDN unless app
        config = app.config
        return config.htmx_src.not_nil! if config.htmx_src
        if v = config.htmx_version
          "https://unpkg.com/htmx.org@#{v}/dist/htmx.min.js"
        else
          Altair::Htmx::CDN
        end
      end
    end
  end
end
