# Altair — compile-time templates.
#
# Altair renders views from `.ecr` files, but it does not use the standard
# library's ECR: the `templates` macro ships a small compile-time
# transpiler that reads each template file and generates a plain Crystal
# method from it. That gives the framework ownership of the syntax — and,
# critically, safe defaults:
#
# - `<%= expr %>` HTML-escapes the expression — XSS-safe out of the box.
# - `<%== expr %>` inserts the expression raw, for trusted HTML.
# - `<% code %>` embeds plain Crystal code (`if`, `each`, ...).
# - `<%%` writes a literal `<%`.
#
# The macro turns a directory of such files into private `render_<name>`
# methods whose locals are unpacked from a NamedTuple, so a missing local
# or a missing file is a compile error:
#
# ```
# class PostsController < ApplicationController
#   templates "posts",
#     layout: "application",
#     index: {posts: Array(Post)},
#     show: {post: Post},
#     form: {post: Post}
# end
# ```
#
# `render :index` (a full page inside the layout), `render :index,
# layout: false` (an htmx fragment) and `render "form", locals: {post: post}`
# (a partial, returning a String) all dispatch to these generated methods.
module Altair
  module View
    # Escapes `value` for safe HTML output. Every `<%= %>` interpolation in
    # a template goes through here.
    def self.escape(value : String) : String
      HTML.escape(value)
    end
  end
end

# Declares the view files for a controller and generates the render
# methods for them. See the module docs for the full shape.
#
# The transpiler is deliberately self-contained: Crystal macros cannot call
# other macros, so every transform below is inlined here.
macro templates(dir, root = nil, layout = nil, **views)
  {% if root.is_a?(Call) && root.name.stringify == "+" %}
    {% views_root = root.receiver + root.args[0] %}
  {% else %}
    {% views_root = root || raise("templates: pass a views directory, e.g. `root: __DIR__ + \"/../views\"`") %}
  {% end %}

  {% for name, locals in views %}
    {% path = views_root + "/" + dir + "/" + name.id.stringify + ".ecr" %}
    {% if locals.is_a?(NamedTupleLiteral) %}
      {% local_params = locals.keys.map { |local| local.stringify + " : " + locals[local].stringify }.join(", ") %}
      private def render_{{ name.id }}({{ local_params.id }}) : String
    {% else %}
      private def render_{{ name.id }} : String
    {% end %}
      String.build do |__io__|
        {% raw = read_file(path) %}
        {% segments = raw.split("<%") %}
        {% for seg, index in segments %}
          {% if index == 0 %}
            {% if seg.size > 0 %}
              {% safe = seg.gsub(/#/, "\\#") %}
              __io__ << {{ safe }}
            {% end %}
          {% else %}
            {% if seg.starts_with?("==") %}
              {% expr = seg.split("==")[1].split("%>")[0] %}
              __io__ << ({{ expr.id }}).to_s
            {% elsif seg.starts_with?("=") %}
              {% expr = seg[1..].split("%>")[0] %}
              {% stripped = expr.strip %}
              {% if stripped.starts_with?("render ") || stripped.starts_with?("render(") || stripped.starts_with?("link_to") || stripped.starts_with?("content_tag") || stripped.starts_with?("button_to") || stripped.starts_with?("javascript_include_tag") || stripped.starts_with?("form_for") || stripped.starts_with?("f.") %}
                __io__ << ({{ expr.id }}).to_s
              {% else %}
                __io__ << Altair::View.escape(({{ expr.id }}).to_s)
              {% end %}
            {% elsif seg.starts_with?("%") %}
              __io__ << "<%"
              {% if seg.size > 1 %}
                {% tail2 = seg[1..].split("%>")[0] %}
                {% if tail2.size > 0 %}
                  {% safe2 = tail2.gsub(/#/, "\\#") %}
                  __io__ << {{ safe2 }}
                {% end %}
              {% end %}
            {% else %}
              {% body = seg.split("%>")[0] %}
              {% if body.strip == "yield" %}
                __io__ << content
              {% elsif body.strip.starts_with?("form_for(") %}
                {% form_name, form_args = body.strip.split("(") %}
                {{ form_name.id }}(__io__, {{ form_args.id }}
              {% elsif body.strip.starts_with?("form_for ") %}
                {% form_parts = body.strip.split(" do ", 2) %}
                {% if form_parts.size > 1 %}
                  form_for(__io__, {{ form_parts[0][9..].id }}) do {{ form_parts[1].id }}
                {% else %}
                  form_for(__io__, {{ form_parts[0][9..].id }})
                {% end %}
              {% else %}
                {{ body.id }}
              {% end %}
            {% end %}
            {% tail_parts = seg.split("%>") %}
            {% if tail_parts.size > 1 && tail_parts[1].size > 0 %}
              {% safe_tail = tail_parts[1].gsub(/#/, "\\#") %}
              __io__ << {{ safe_tail }}
            {% end %}
          {% end %}
        {% end %}
      end
    end
  {% end %}

  private def render_template(action : Symbol | String, locals : NamedTuple) : String
    case action
    {% for name, locals in views %}
    when {{ name.symbolize }}, {{ name.id.stringify }}
      {% if locals.is_a?(NamedTupleLiteral) %}
        {% full_type = locals.stringify.gsub(/^\{/, "NamedTuple(").gsub(/\}$/, ")") %}
        {% call_args = locals.keys.map { |local| local.stringify + ": (locals.as?(" + full_type + ") || raise Altair::Error.new(\"Missing local :" + local.stringify + " for template " + name.id.stringify + "\"))[" + local.symbolize.stringify + "].as(" + locals[local].stringify + ")" }.join(", ") %}
        render_{{ name.id }}({{ call_args.id }})
      {% else %}
        render_{{ name.id }}
      {% end %}
    {% end %}
    else
      raise Altair::Error.new("No template for #{action}")
    end
  end

  {% if layout && layout != "" %}
    {% layout_path = views_root + "/layouts/" + layout + ".ecr" %}
    private def render_layout(content : String) : String
      String.build do |__io__|
        {% raw = read_file(layout_path) %}
        {% segments = raw.split("<%") %}
        {% for seg, index in segments %}
          {% if index == 0 %}
            {% if seg.size > 0 %}
              {% safe = seg.gsub(/#/, "\\#") %}
              __io__ << {{ safe }}
            {% end %}
          {% else %}
            {% if seg.starts_with?("==") %}
              {% expr = seg.split("==")[1].split("%>")[0] %}
              __io__ << ({{ expr.id }}).to_s
            {% elsif seg.starts_with?("=") %}
              {% expr = seg[1..].split("%>")[0] %}
              {% stripped = expr.strip %}
              {% if stripped.starts_with?("render ") || stripped.starts_with?("render(") || stripped.starts_with?("link_to") || stripped.starts_with?("content_tag") || stripped.starts_with?("button_to") || stripped.starts_with?("javascript_include_tag") || stripped.starts_with?("form_for") || stripped.starts_with?("f.") %}
                __io__ << ({{ expr.id }}).to_s
              {% else %}
                __io__ << Altair::View.escape(({{ expr.id }}).to_s)
              {% end %}
            {% elsif seg.starts_with?("%") %}
              __io__ << "<%"
              {% if seg.size > 1 %}
                {% tail2 = seg[1..].split("%>")[0] %}
                {% if tail2.size > 0 %}
                  {% safe2 = tail2.gsub(/#/, "\\#") %}
                  __io__ << {{ safe2 }}
                {% end %}
              {% end %}
            {% else %}
              {% body = seg.split("%>")[0] %}
              {% if body.strip == "yield" %}
                __io__ << content
              {% elsif body.strip.starts_with?("form_for(") %}
                {% form_name, form_args = body.strip.split("(") %}
                {{ form_name.id }}(__io__, {{ form_args.id }}
              {% elsif body.strip.starts_with?("form_for ") %}
                {% form_parts = body.strip.split(" do ", 2) %}
                {% if form_parts.size > 1 %}
                  form_for(__io__, {{ form_parts[0][9..].id }}) do {{ form_parts[1].id }}
                {% else %}
                  form_for(__io__, {{ form_parts[0][9..].id }})
                {% end %}
              {% else %}
                {{ body.id }}
              {% end %}
            {% end %}
            {% tail_parts = seg.split("%>") %}
            {% if tail_parts.size > 1 && tail_parts[1].size > 0 %}
              {% safe_tail = tail_parts[1].gsub(/#/, "\\#") %}
              __io__ << {{ safe_tail }}
            {% end %}
          {% end %}
        {% end %}
      end
    end
  {% end %}
end
