# Altair — the batteries-included web framework for Crystal.
#
# This file defines the controller generator: `altair generate controller
# Posts` writes `app/controllers/posts_controller.cr` with the seven RESTful
# actions plus the matching view files (`index`, `show`, `new`, `edit`) and
# a shared `_form` partial. The controller declares the `templates` macro
# with typed locals, so every generated view is compile-time checked.
module Altair
  module CLI
    module Generators
      class Controller
        include Base

        # The controller name argument, e.g. `Posts`.
        getter name : String

        # The actions to generate; defaults to the RESTful seven.
        getter actions : Array(String)

        # The columns of the backing model, used for form fields.
        getter columns : Array(Column)

        def initialize(@name : String, @actions = DEFAULT_ACTIONS, @columns = [] of Column)
        end

        DEFAULT_ACTIONS = %w[index show new create edit update destroy]

        # The controller's class name, e.g. `PostsController`. Plural to match
        # the `resources :posts` routes the scaffold registers.
        def class_name : String
          plural = Altair::Inflector.pluralize(classify(@name))
          "#{classify(plural)}Controller"
        end

        # The model the controller manages, e.g. `Post`.
        def model_class : String
          classify(Altair::Inflector.singularize(classify(@name)))
        end

        # The table / resource name, e.g. `posts`.
        def table : String
          tableize(classify(@name))
        end

        # The controller file path, e.g. `src/app/controllers/posts_controller.cr`.
        def path : Path
          Path.new("src/app/controllers/#{Altair::Inflector.underscore(table)}_controller.cr")
        end

        # The views directory, e.g. `src/app/views/posts/`.
        def views_dir : Path
          Path.new("src/app/views/#{table}")
        end

        # Writes the controller and its views, returning the controller path.
        def generate : Path
          write_file(path, controller_content)
          view_content.each do |file, content|
            write_file(views_dir.join(file), content)
          end
          path
        end

        private def form_fields : Array(Column)
          @columns.reject(&.name.==("id"))
        end

        private def controller_content : String
          String.build do |io|
            io << "# #{class_name} — RESTful actions for #{model_class}.\n"
            io << "class #{class_name} < ApplicationController\n"
            io << "  templates \"#{table}\",\n"
            io << "    root: __DIR__ + \"/../views\",\n"
            io << "    layout: \"application\",\n"
            io << "    index: {#{model_class.downcase}s: Array(#{model_class})},\n"
            io << "    show: {#{model_var}: #{model_class}},\n"
            io << "    new: {#{model_var}: #{model_class}},\n"
            io << "    edit: {#{model_var}: #{model_class}}\n"
            io << "\n"
            io << "  def index : Nil\n"
            io << "    render :index, locals: {#{model_var}s: #{model_class}.all.to_a}\n"
            io << "  end\n"
            io << "\n"
            io << "  def show : Nil\n"
            io << "    if #{model_var} = find_record\n"
            io << "      render :show, locals: {#{model_var}: #{model_var}}\n"
            io << "    else\n"
            io << "      render text: \"#{model_class} not found\", status: ::HTTP::Status::NOT_FOUND\n"
            io << "    end\n"
            io << "  end\n"
            io << "\n"
            io << "  def new : Nil\n"
            io << "    render :new, locals: {#{model_var}: #{model_class}.new}\n"
            io << "  end\n"
            io << "\n"
            io << "  def create : Nil\n"
            io << "    #{model_var} = #{model_class}.new(#{assign_arguments.join(", ")})\n"
            io << "    if #{model_var}.save\n"
            io << "      redirect_to \"/#{table}/\#{#{model_var}.id}\"\n"
            io << "    else\n"
            io << "      response.status = ::HTTP::Status::UNPROCESSABLE_ENTITY\n"
            io << "      render :new, locals: {#{model_var}: #{model_var}}\n"
            io << "    end\n"
            io << "  end\n"
            io << "\n"
            io << "  def edit : Nil\n"
            io << "    if #{model_var} = find_record\n"
            io << "      render :edit, locals: {#{model_var}: #{model_var}}\n"
            io << "    else\n"
            io << "      render text: \"#{model_class} not found\", status: ::HTTP::Status::NOT_FOUND\n"
            io << "    end\n"
            io << "  end\n"
            io << "\n"
            io << "  def update : Nil\n"
            io << "    if #{model_var} = find_record\n"
            form_fields.each do |column|
              io << "      #{model_var}.#{column.name} = #{param_expr(column)}\n"
            end
            io << "      if #{model_var}.save\n"
            io << "        redirect_to \"/#{table}/\#{#{model_var}.id}\"\n"
            io << "      else\n"
            io << "        response.status = ::HTTP::Status::UNPROCESSABLE_ENTITY\n"
            io << "        render :edit, locals: {#{model_var}: #{model_var}}\n"
            io << "      end\n"
            io << "    else\n"
            io << "      render text: \"#{model_class} not found\", status: ::HTTP::Status::NOT_FOUND\n"
            io << "    end\n"
            io << "  end\n"
            io << "\n"
            io << "  def destroy : Nil\n"
            io << "    if #{model_var} = find_record\n"
            io << "      #{model_var}.delete\n"
            io << "      redirect_to \"/#{table}\"\n"
            io << "    else\n"
            io << "      render text: \"#{model_class} not found\", status: ::HTTP::Status::NOT_FOUND\n"
            io << "    end\n"
            io << "  end\n"
            io << "\n"
            io << "  private def find_record : #{model_class}?\n"
            io << "    params[\"id\"]?.try(&.to_i?).try { |id| #{model_class}.find(id) }\n"
            io << "  end\n"
            io << "end\n"
          end
        end

        private def model_var : String
          Altair::Inflector.underscore(model_class)
        end

        private def assign_arguments : Array(String)
          form_fields.map do |column|
            "#{column.name}: #{param_expr(column)}"
          end
        end

        # The expression reading `params[name]` coerced to the column type.
        private def param_expr(column : Column) : String
          case column.type
          when :integer then "params[\"#{column.name}\"]?.try(&.to_i) || 0"
          when :bigint  then "params[\"#{column.name}\"]?.try(&.to_i64) || 0_i64"
          when :float   then "params[\"#{column.name}\"]?.try(&.to_f) || 0.0"
          when :boolean then "params[\"#{column.name}\"]? == \"1\""
          when :string, :text, :datetime, :decimal, :json
            "params[\"#{column.name}\"]? || \"\""
          else
            "params[\"#{column.name}\"]? || \"\""
          end
        end

        # Returns the view files keyed by file name, ready to write.
        private def view_content : Hash(String, String)
          files = {} of String => String
          files["index.ecr"] = index_view
          files["show.ecr"] = show_view
          files["new.ecr"] = form_view(method: "post", action: "\"/#{table}\"")
          files["edit.ecr"] = form_view(method: "put", action: "\"/#{table}/<%= #{model_var}.id %>\"")
          files
        end

        private def index_view : String
          String.build do |io|
            io << "<h1>#{model_class}s</h1>\n"
            io << "<% if #{model_var}s.empty? %>\n"
            io << "  <p>No #{model_var}s yet.</p>\n"
            io << "<% else %>\n"
            io << "  <ul>\n"
            io << "  <% #{model_var}s.each do |#{model_var}| %>\n"
            io << "    <li>\n"
            io << "      <a href=\"/#{table}/<%= #{model_var}.id %>\"><%= #{model_var}.#{display_column} %></a>\n"
            io << "      <a href=\"/#{table}/<%= #{model_var}.id %>/edit\">Edit</a>\n"
            io << "      <form class=\"inline\" action=\"/#{table}/<%= #{model_var}.id %>\" method=\"post\">\n"
            io << "        <input type=\"hidden\" name=\"_method\" value=\"DELETE\">\n"
            io << "        <button type=\"submit\">Delete</button>\n"
            io << "      </form>\n"
            io << "    </li>\n"
            io << "  <% end %>\n"
            io << "  </ul>\n"
            io << "<% end %>\n"
          end
        end

        private def show_view : String
          String.build do |io|
            io << "<h1>#{model_class} <%= #{model_var}.id %></h1>\n"
            form_fields.each do |column|
              io << "<p><strong>#{column.name}</strong>: <%= #{model_var}.#{column.name} %></p>\n"
            end
            io << "<p><a href=\"/#{table}/<%= #{model_var}.id %>/edit\">Edit</a> · <a href=\"/#{table}\">Back</a></p>\n"
          end
        end

        # The page shell for `new` and `edit`, wrapping the shared form.
        private def form_view(method : String, action : String) : String
          String.build do |io|
            io << "<h1>#{model_class} form</h1>\n"
            io << form_fields_html(method, action)
          end
        end

        # The shared `<form>` markup with the fields and `_method` override.
        private def form_fields_html(method : String, action : String) : String
          String.build do |io|
            io << "<% #{model_var}.errors.full_messages.each do |message| %>\n"
            io << "  <p class=\"error\"><%= message %></p>\n"
            io << "<% end %>\n"
            io << "<form action=#{action} method=\"post\">\n"
            unless method == "post"
              io << "  <input type=\"hidden\" name=\"_method\" value=\"#{method.upcase}\">\n"
            end
            form_fields.each do |column|
              io << "  <label>#{column.name} <input name=\"#{column.name}\" type=\"text\" value=\"<%= #{model_var}.#{column.name} %>\"></label>\n"
            end
            io << "  <button type=\"submit\">Save</button>\n"
            io << "</form>\n"
          end
        end

        # The column shown as the list link text; defaults to the first
        # non-`id` column, or `id` when the table has none.
        private def display_column : String
          form_fields.first?.try(&.name) || "id"
        end
      end
    end
  end
end
