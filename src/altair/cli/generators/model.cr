# Altair — the batteries-included web framework for Crystal.
#
# This file defines the model generator: `altair generate model Post
# title:string body:text` writes `app/models/post.cr`. The generated model
# subclasses `Altair::Record::Model` and declares its backing table, so
# attributes, finders and validations follow from the schema once the
# matching migration has run.
module Altair
  module CLI
    module Generators
      class Model
        include Base

        # The model name argument, e.g. `Post`.
        getter name : String

        def initialize(@name : String)
        end

        # The model's class name, e.g. `BlogPost`.
        def class_name : String
          classify(@name)
        end

        # The backing table name, e.g. `blog_posts`.
        def table : String
          tableize(class_name)
        end

        # The model file path, e.g. `src/app/models/blog_post.cr`.
        def path : Path
          Path.new("src/app/models/#{Altair::Inflector.underscore(class_name)}.cr")
        end

        # Writes the model file and returns its path.
        def generate : Path
          content = String.build do |io|
            io << "# #{class_name} persisted through Altair::Record.\n"
            io << "class #{class_name} < Altair::Record::Model\n"
            io << "  table :#{table}\n"
            io << "end\n"
          end
          write_file(path, content)
        end
      end
    end
  end
end
