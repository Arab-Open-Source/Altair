# Altair — the batteries-included web framework for Crystal.
#
# This file implements `Altair::Inflector`, the framework's word-inflection
# engine. It is the foundation of Altair's "convention over configuration"
# promise: table names are pluralized (`users`), class names are camelized
# (`BlogPost`) and file names are underscored (`blog_post`) automatically, so
# that models, controllers, routes and database tables connect to each other
# without a single line of mapping code. The engine is a pragmatic subset of
# the common English inflection rules: regular plural and singular
# transformations plus the most common irregular and uncountable nouns.
module Altair
  module Inflector
    IRREGULAR_PLURALS = {
      "person"     => "people",
      "man"        => "men",
      "woman"      => "women",
      "child"      => "children",
      "foot"       => "feet",
      "tooth"      => "teeth",
      "goose"      => "geese",
      "mouse"      => "mice",
      "ox"         => "oxen",
      "sex"        => "sexes",
      "move"       => "moves",
      "zombie"     => "zombies",
      "hero"       => "heroes",
      "datum"      => "data",
      "cactus"     => "cacti",
      "focus"      => "foci",
      "thesis"     => "theses",
      "analysis"   => "analyses",
      "crisis"     => "crises",
      "index"      => "indices",
      "matrix"     => "matrices",
      "vertex"     => "vertices",
      "axis"       => "axes",
      "phenomenon" => "phenomena",
      "criterion"  => "criteria",
      "medium"     => "media",
      "bacterium"  => "bacteria",
      "curriculum" => "curricula",
    }

    UNCOUNTABLES = {
      "equipment", "information", "rice", "money", "fish", "sheep",
      "deer", "species", "series", "news",
    }

    # User-registered irregular singular/plural pairs, checked before the
    # built-in table.
    @@irregulars : Hash(String, String) = {} of String => String

    PLURAL_RULES = [
      {/(quiz)$/, "\\1zes"},
      {/^(ox)$/, "\\1en"},
      {/([ml])ouse$/, "\\1ice"},
      {/(matr|vert|ind)(ix|ex)$/, "\\1ices"},
      {/(x|ch|ss|sh)$/, "\\1es"},
      {/([^aeiouy]|qu)y$/, "\\1ies"},
      {/(hive)$/, "\\1s"},
      {/(?:([^f])fe|([lr])f)$/, "\\1\\2ves"},
      {/sis$/, "ses"},
      {/([ti])um$/, "\\1a"},
      {/(buffal|tomat)o$/, "\\1oes"},
      {/(bu)s$/, "\\1ses"},
      {/(alias|status)$/, "\\1es"},
      {/(octop|vir)us$/, "\\1i"},
      {/(ax|test)is$/, "\\1es"},
      {/s$/, "s"},
      {/$/, "s"},
    ]

    SINGULAR_RULES = [
      {/(quiz)zes$/, "\\1"},
      {/(matr)ices$/, "\\1ix"},
      {/(vert|ind)ices$/, "\\1ex"},
      {/^(ox)en$/, "\\1"},
      {/(alias|status)es$/, "\\1"},
      {/(octop|vir)i$/, "\\1us"},
      {/(cris|ax|test)es$/, "\\1is"},
      {/(shoe)s$/, "\\1"},
      {/(o)es$/, "\\1"},
      {/(bus)es$/, "\\1"},
      {/([ml])ice$/, "\\1ouse"},
      {/(x|ch|ss|sh)es$/, "\\1"},
      {/(m)ovies$/, "\\1ovie"},
      {/(s)eries$/, "\\1eries"},
      {/([^aeiouy]|qu)ies$/, "\\1y"},
      {/([lr])ves$/, "\\1f"},
      {/(tive)s$/, "\\1"},
      {/(hive)s$/, "\\1"},
      {/([^f])ves$/, "\\1fe"},
      {/(^analy)ses$/, "\\1sis"},
      {/((a)naly|(b)a|(d)iagno|(p)arenthe|(p)rogno|(s)ynop|(t)he)ses$/, "\\1\\2sis"},
      {/([ti])a$/, "\\1um"},
      {/(n)ews$/, "\\1ews"},
      {/s$/, ""},
    ]

    # Registers an irregular singular/plural pair, consulted before the
    # built-in rules:
    #
    # ```
    # Altair::Inflector.irregular("octopus", "octopi")
    # ```
    def self.irregular(singular : String, plural : String) : Nil
      @@irregulars[singular] = plural
    end

    # Converts a model name to its table name:
    #
    # ```
    # Altair::Inflector.tableize("Post")     # => "posts"
    # Altair::Inflector.tableize("BlogPost") # => "blog_posts"
    # ```
    def self.tableize(model_name : String) : String
      pluralize(underscore(model_name))
    end

    # Converts a model name to its foreign key:
    #
    # ```
    # Altair::Inflector.foreign_key("Post")     # => "post_id"
    # Altair::Inflector.foreign_key("BlogPost") # => "blog_post_id"
    # ```
    def self.foreign_key(model_name : String) : String
      "#{underscore(model_name)}_id"
    end

    # Converts a singular noun to its plural form:
    #
    # ```
    # Altair::Inflector.pluralize("user")     # => "users"
    # Altair::Inflector.pluralize("category") # => "categories"
    # Altair::Inflector.pluralize("person")   # => "people"
    # Altair::Inflector.pluralize("sheep")    # => "sheep"
    # ```
    def self.pluralize(word : String) : String
      return word if word.empty?
      @@irregulars[word]? || IRREGULAR_PLURALS[word]? || pluralize_regular(word)
    end

    # Converts a plural noun to its singular form:
    #
    # ```
    # Altair::Inflector.singularize("users")      # => "user"
    # Altair::Inflector.singularize("categories") # => "category"
    # Altair::Inflector.singularize("people")     # => "person"
    # ```
    def self.singularize(word : String) : String
      return word if word.empty?
      @@irregulars.each do |singular, plural|
        return singular if word == plural
      end
      IRREGULAR_PLURALS.each do |singular, plural|
        return singular if word == plural
      end
      singularize_regular(word)
    end

    # Converts snake_case or kebab-case words to CamelCase:
    #
    # ```
    # Altair::Inflector.camelize("blog_post") # => "BlogPost"
    # ```
    def self.camelize(term : String, separator : Char = '_') : String
      term.split(separator).map(&.capitalize).join
    end

    # Converts CamelCase to snake_case:
    #
    # ```
    # Altair::Inflector.underscore("BlogPost") # => "blog_post"
    # ```
    def self.underscore(camel_case : String) : String
      camel_case
        .gsub(/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
        .gsub(/([a-z\d])([A-Z])/, "\\1_\\2")
        .downcase
    end

    # Returns `true` if the word has no singular/plural distinction, such as
    # "information" or "sheep".
    def self.uncountable?(word : String) : Bool
      UNCOUNTABLES.includes?(word.downcase)
    end

    private def self.pluralize_regular(word : String) : String
      return word if uncountable?(word)
      PLURAL_RULES.each do |rule, replacement|
        return word.gsub(rule, replacement) if word.matches?(rule)
      end
      word
    end

    private def self.singularize_regular(word : String) : String
      return word if uncountable?(word)
      SINGULAR_RULES.each do |rule, replacement|
        return word.gsub(rule, replacement) if word.matches?(rule)
      end
      word
    end
  end
end
