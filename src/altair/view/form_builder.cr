# Altair — the form builder.
#
# A block-based builder that renders a `<form>` with a `_method` override
# for non-GET verbs and escaped values everywhere. htmx attributes pass
# through as `hx-*`. Inside a template:
#
# ```
# <% form_for("/posts", hx_post: "/posts", hx_target: "#list") do |f| %>
#   <%= f.label("title", "Title") %>
#   <%= f.text_field("title", value: post.title) %>
#   <%= f.submit("Save") %>
# <% end %>
# ```
module Altair
  module View
    # Builds the fields inside a `form_for` block. Each field returns its
    # markup so it can be interpolated with `<%= %>`.
    class FormBuilder
      include Helpers

      # The verb the form will submit as (after the `_method` override).
      getter method : Symbol

      def initialize(@method : Symbol)
      end

      # Renders a `<label>` for the field `name`.
      def label(name : String, text : String) : String
        String.build do |io|
          io << "<label for=\"" << name << "\">" << Altair::View.escape(text) << "</label>"
        end
      end

      # Renders a text input, e.g. `f.text_field("title", value: "Hi")`.
      def text_field(name : String, *, value : String = "", **attrs) : String
        input_tag(:text, name, value, **attrs)
      end

      # Renders an email input.
      def email_field(name : String, *, value : String = "", **attrs) : String
        input_tag(:email, name, value, **attrs)
      end

      # Renders a password input.
      def password_field(name : String, *, value : String = "", **attrs) : String
        input_tag(:password, name, value, **attrs)
      end

      # Renders a hidden input, e.g. for CSRF tokens.
      def hidden_field(name : String, *, value : String = "", **attrs) : String
        input_tag(:hidden, name, value, **attrs)
      end

      # Renders a submit button.
      def submit(text : String = "Save", **attrs) : String
        String.build do |io|
          io << "<button type=\"submit\""
          attrs.each do |key, value|
            io << ' ' << attribute_name(key) << "=\"" << Altair::View.escape(value.to_s) << '"'
          end
          io << '>' << Altair::View.escape(text) << "</button>"
        end
      end

      private def input_tag(type : Symbol, name : String, value : String, **attrs) : String
        String.build do |io|
          io << "<input type=\"" << type << "\" name=\"" << name << '"'
          io << " value=\"" << Altair::View.escape(value) << '"' unless value.empty?
          attrs.each do |key, attr_value|
            io << ' ' << attribute_name(key) << "=\"" << Altair::View.escape(attr_value.to_s) << '"'
          end
          io << '>'
        end
      end
    end
  end
end
