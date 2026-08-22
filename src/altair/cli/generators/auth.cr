# Altair — the batteries-included web framework for Crystal.
#
# This file defines the auth generator: `altair generate auth [User]` writes
# a complete registration/login stack for the given user model — model +
# migration + unique-email index, sessions and registrations controllers
# with their views, and the login/register/logout routes. Passwords are
# hashed through `Altair::Auth::PasswordHasher` via the model's
# `password_auth` declaration; sessions reuse the framework's signed-cookie
# session and the controllers' built-in auth helpers.
module Altair
  module CLI
    module Generators
      class Auth
        include Base

        # The user model name argument, e.g. `User`.
        getter name : String

        def initialize(@name : String = "User")
        end

        # The model's class name, e.g. `User`.
        def class_name : String
          classify(@name)
        end

        # The backing table name, e.g. `users`.
        def table : String
          tableize(class_name)
        end

        # Writes the model, migration, controllers, views, schema seed and
        # routes. Returns every written path.
        def generate : Array(Path)
          paths = [] of Path
          paths << write_model
          paths << write_migration
          paths << write_sessions_controller
          paths << write_registrations_controller
          paths << write_view("sessions", "new", session_new_view)
          paths << write_view("registrations", "new", registration_new_view)
          paths << Base.seed_schema(table, user_columns)
          paths << register_routes
          paths
        end

        private def write_model : Path
          content = String.build do |io|
            io << "# #{class_name} persisted through Altair::Record with password authentication.\n"
            io << "class #{class_name} < Altair::Record::Model\n"
            io << "  table :#{table}\n"
            io << "\n"
            io << "  validates_presence_of :email\n"
            io << "  validates_uniqueness_of :email\n"
            io << "  validates_format_of :email,\n"
            io << "    with: /\\A[^@\\s]+@[^@\\s]+\\.[^@\\s]+\\z/\n"
            io << "\n"
            io << "  password_auth min_length: 8\n"
            io << "end\n"
          end
          write_file(Path.new("src/app/models/#{Inflector.underscore(class_name)}.cr"), content)
        end

        private def user_columns : Array(Column)
          [
            Column.new("id", :integer),
            Column.new("email", :string),
            Column.new("password_digest", :string),
            Column.new("created_at", :datetime),
            Column.new("updated_at", :datetime),
          ]
        end

        private def write_migration : Path
          migration = Migration.new("Create#{Inflector.pluralize(class_name)}",
            [Column.new("email", :string), Column.new("password_digest", :string)])
          if migration.exists?
            return migration.path
          end
          path = migration.generate
          append_unique_index(path)
          path
        end

        # Adds the unique email index to the generated migration, after its
        # create_table call.
        private def append_unique_index(path : Path) : Nil
          lines = File.read_lines(path.to_s)
          insert_at = (lines.index(&.includes?("def up")).try(&.+(1))) || lines.size
          indent = "    "
          lines.insert(insert_at, "#{indent}schema.add_index(:#{table}, :email, unique: true)")
          File.write(path, lines.join('\n'))
        end

        private def write_sessions_controller : Path
          content = String.build do |io|
            io << "# SessionsController — password login and logout.\n"
            io << "class SessionsController < ApplicationController\n"
            io << "  templates \"sessions\",\n"
            io << "    root: __DIR__ + \"/../views\",\n"
            io << "    layout: \"application\",\n"
            io << "    new: {}\n"
            io << "\n"
            io << "  def new : Nil\n"
            io << "    render :new\n"
            io << "  end\n"
            io << "\n"
            io << "  def create : Nil\n"
            io << "    email = params[\"email\"]?.to_s.strip.downcase\n"
            io << "    password = params[\"password\"]?.to_s\n"
            io << "    if (user = find_user(email)) && user.authenticate_password(password)\n"
            io << "      sign_in(user.id.not_nil!.to_s)\n"
            io << "      redirect_to \"/\"\n"
            io << "    else\n"
            io << "      render html: login_failed_html(email), status: ::HTTP::Status::UNPROCESSABLE_ENTITY\n"
            io << "    end\n"
            io << "  end\n"
            io << "\n"
            io << "  def destroy : Nil\n"
            io << "    sign_out\n"
            io << "    redirect_to \"/login\"\n"
            io << "  end\n"
            io << "\n"
            io << "  private def find_user(email : String) : #{class_name}?\n"
            io << "    #{class_name}.find_by_email(email)\n"
            io << "  end\n"
            io << "\n"
            io << "  private def login_failed_html(email : String) : String\n"
            io << "    String.build do |html|\n"
            io << "      html << \"<h1>Sign in</h1>\"\n"
            io << "      html << \"<p class=\\\"error\\\">Invalid email or password.</p>\"\n"
            io << "      html << \"<form action=\\\"/login\\\" method=\\\"post\\\">\"\n"
            io << "      html << \"<label>Email <input type=\\\"email\\\" name=\\\"email\\\" value=\\\"\" << email << \"\\\"></label>\"\n"
            io << "      html << \"<label>Password <input type=\\\"password\\\" name=\\\"password\\\"></label>\"\n"
            io << "      html << \"<button type=\\\"submit\\\">Sign in</button></form>\"\n"
            io << "    end\n"
            io << "  end\n"
            io << "end\n"
          end
          write_file(Path.new("src/app/controllers/sessions_controller.cr"), content)
        end

        private def write_registrations_controller : Path
          underscored = Inflector.underscore(class_name)
          content = String.build do |io|
            io << "# RegistrationsController — account creation with password confirmation.\n"
            io << "class RegistrationsController < ApplicationController\n"
            io << "  templates \"registrations\",\n"
            io << "    root: __DIR__ + \"/../views\",\n"
            io << "    layout: \"application\",\n"
            io << "    new: {#{underscored}: #{class_name}}\n"
            io << "\n"
            io << "  def new : Nil\n"
            io << "    render :new, locals: {#{underscored}: #{class_name}.new}\n"
            io << "  end\n"
            io << "\n"
            io << "  def create : Nil\n"
            io << "    user = #{class_name}.new(\n"
            io << "      email: params[\"email\"]?.to_s.strip.downcase,\n"
            io << "    )\n"
            io << "    user.password = params[\"password\"]?\n"
            io << "    user.password_confirmation = params[\"password_confirmation\"]?\n"
            io << "    if user.save\n"
            io << "      sign_in(user.id.not_nil!.to_s)\n"
            io << "      redirect_to \"/\"\n"
            io << "    else\n"
            io << "      response.status = ::HTTP::Status::UNPROCESSABLE_ENTITY\n"
            io << "      render :new, locals: {#{underscored}: user}\n"
            io << "    end\n"
            io << "  end\n"
            io << "end\n"
          end
          write_file(Path.new("src/app/controllers/registrations_controller.cr"), content)
        end

        private def write_view(dir : String, file : String, content : String) : Path
          write_file(Path.new("src/app/views/#{dir}/#{file}.ecr"), content)
        end

        private def session_new_view : String
          String.build do |io|
            io << "<h1>Sign in</h1>\n"
            io << "<form action=\"/login\" method=\"post\">\n"
            io << "  <label>Email <input type=\"email\" name=\"email\" required></label>\n"
            io << "  <label>Password <input type=\"password\" name=\"password\" required></label>\n"
            io << "  <button type=\"submit\">Sign in</button>\n"
            io << "</form>\n"
            io << "<p><a href=\"/register\">Create an account</a></p>\n"
          end
        end

        private def registration_new_view : String
          underscored = Inflector.underscore(class_name)
          String.build do |io|
            io << "<h1>Create an account</h1>\n"
            io << "<% if #{underscored}.errors.any? %>\n"
            io << "  <% #{underscored}.errors.full_messages.each do |message| %>\n"
            io << "    <p class=\"error\"><%= message %></p>\n"
            io << "  <% end %>\n"
            io << "<% end %>\n"
            io << "<form action=\"/register\" method=\"post\">\n"
            io << "  <label>Email <input type=\"email\" name=\"email\" value=\"<%= #{underscored}.email %>\"></label>\n"
            io << "  <label>Password <input type=\"password\" name=\"password\"></label>\n"
            io << "  <label>Confirm password <input type=\"password\" name=\"password_confirmation\"></label>\n"
            io << "  <button type=\"submit\">Register</button>\n"
            io << "</form>\n"
            io << "<p><a href=\"/login\">Sign in instead</a></p>\n"
          end
        end

        private def register_routes : Path
          Base.register_route_lines([
            %(get "/register", to: "registrations#new"),
            %(post "/register", to: "registrations#create"),
            %(get "/login", to: "sessions#new"),
            %(post "/login", to: "sessions#create"),
            %(delete "/logout", to: "sessions#destroy"),
          ])
        end
      end
    end
  end
end
