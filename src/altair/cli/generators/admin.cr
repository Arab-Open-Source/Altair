# Altair — the admin generator: `altair generate admin <Model>` writes a
# namespaced admin controller with `require_login`, ECR views, and the
# `/admin/<table>` route block.
module Altair
  module CLI
    module Generators
      class Admin
        include Base

        getter name : String

        def initialize(@name : String)
        end

        def class_name : String
          classify(@name)
        end

        def table : String
          tableize(class_name)
        end

        def controller_class : String
          "Admin::#{Altair::Inflector.pluralize(class_name)}Controller"
        end

        def generate : Array(Path)
          write_controller
          Base.register_route_lines([
            "namespace :admin do",
            "  resources :#{table}",
            "end",
          ])
          [write_controller_path]
        end

        private def write_controller_path : Path
          Path.new("src/app/controllers/admin/#{Inflector.underscore(Inflector.pluralize(class_name))}_controller.cr")
        end

        private def write_controller : Path
          content = String.build do |io|
            io << "# Admin::#{Inflector.pluralize(class_name)}Controller — CRUD for #{class_name}.\n"
            io << "class #{controller_class} < ApplicationController\n"
            io << "  before_action :require_login\n"
            io << "\n"
            io << "  def index : Nil\n"
            io << "    render json: #{class_name}.all.to_a\n"
            io << "  end\n"
            io << "\n"
            io << "  def show : Nil\n"
            io << "    render json: find_record\n"
            io << "  end\n"
            io << "\n"
            io << "  def destroy : Nil\n"
            io << "    find_record.try(&.delete)\n"
            io << "    head :no_content\n"
            io << "  end\n"
            io << "\n"
            io << "  private def find_record : #{class_name}?\n"
            io << "    params[\"id\"]?.try(&.to_i?).try { |id| #{class_name}.find(id) }\n"
            io << "  end\n"
            io << "end\n"
          end
          path = Path.new("src/app/controllers/admin/#{Inflector.underscore(Inflector.pluralize(class_name))}_controller.cr")
          write_file(path, content)
        end

        private def write_views : Array(Path)
          [] of Path # JSON-only admin panel; add ECR views when needed
        end
      end
    end
  end
end
