# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Inflector`: pluralization, singularization, camelization
# and underscoring, covering regular rules, irregular nouns and uncountables.
require "../spec_helper"

describe Altair::Inflector do
  describe ".pluralize" do
    it "follows the regular rules" do
      Altair::Inflector.pluralize("user").should eq("users")
      Altair::Inflector.pluralize("category").should eq("categories")
      Altair::Inflector.pluralize("box").should eq("boxes")
      Altair::Inflector.pluralize("bus").should eq("buses")
      Altair::Inflector.pluralize("address").should eq("addresses")
      Altair::Inflector.pluralize("knife").should eq("knives")
      Altair::Inflector.pluralize("wolf").should eq("wolves")
      Altair::Inflector.pluralize("hero").should eq("heroes")
      Altair::Inflector.pluralize("matrix").should eq("matrices")
      Altair::Inflector.pluralize("status").should eq("statuses")
    end

    it "handles irregular nouns" do
      Altair::Inflector.pluralize("person").should eq("people")
      Altair::Inflector.pluralize("child").should eq("children")
      Altair::Inflector.pluralize("man").should eq("men")
      Altair::Inflector.pluralize("mouse").should eq("mice")
      Altair::Inflector.pluralize("foot").should eq("feet")
      Altair::Inflector.pluralize("cactus").should eq("cacti")
      Altair::Inflector.pluralize("criterion").should eq("criteria")
    end

    it "leaves uncountable nouns untouched" do
      Altair::Inflector.pluralize("sheep").should eq("sheep")
      Altair::Inflector.pluralize("fish").should eq("fish")
      Altair::Inflector.pluralize("information").should eq("information")
      Altair::Inflector.pluralize("series").should eq("series")
    end
  end

  describe ".singularize" do
    it "follows the regular rules" do
      Altair::Inflector.singularize("users").should eq("user")
      Altair::Inflector.singularize("categories").should eq("category")
      Altair::Inflector.singularize("boxes").should eq("box")
      Altair::Inflector.singularize("knives").should eq("knife")
      Altair::Inflector.singularize("heroes").should eq("hero")
      Altair::Inflector.singularize("matrices").should eq("matrix")
      Altair::Inflector.singularize("statuses").should eq("status")
      Altair::Inflector.singularize("analyses").should eq("analysis")
    end

    it "handles irregular nouns" do
      Altair::Inflector.singularize("people").should eq("person")
      Altair::Inflector.singularize("children").should eq("child")
      Altair::Inflector.singularize("men").should eq("man")
      Altair::Inflector.singularize("mice").should eq("mouse")
      Altair::Inflector.singularize("criteria").should eq("criterion")
    end

    it "leaves uncountable nouns untouched" do
      Altair::Inflector.singularize("sheep").should eq("sheep")
      Altair::Inflector.singularize("information").should eq("information")
    end
  end

  describe ".camelize" do
    it "converts snake_case to CamelCase" do
      Altair::Inflector.camelize("blog_post").should eq("BlogPost")
      Altair::Inflector.camelize("user").should eq("User")
      Altair::Inflector.camelize("api_key_value").should eq("ApiKeyValue")
    end

    it "honours a custom separator" do
      Altair::Inflector.camelize("blog-post", '-').should eq("BlogPost")
    end
  end

  describe ".underscore" do
    it "converts CamelCase to snake_case" do
      Altair::Inflector.underscore("BlogPost").should eq("blog_post")
      Altair::Inflector.underscore("User").should eq("user")
      Altair::Inflector.underscore("APIKey").should eq("api_key")
    end
  end

  describe ".uncountable?" do
    it "recognizes uncountable nouns" do
      Altair::Inflector.uncountable?("information").should be_true
      Altair::Inflector.uncountable?("sheep").should be_true
      Altair::Inflector.uncountable?("user").should be_false
    end
  end

  describe ".tableize" do
    it "converts a model name to its table name" do
      Altair::Inflector.tableize("User").should eq("users")
      Altair::Inflector.tableize("BlogPost").should eq("blog_posts")
      Altair::Inflector.tableize("Category").should eq("categories")
    end
  end

  describe ".foreign_key" do
    it "derives the foreign key from a model name" do
      Altair::Inflector.foreign_key("Comment").should eq("comment_id")
      Altair::Inflector.foreign_key("BlogPost").should eq("blog_post_id")
    end
  end

  describe ".irregular" do
    it "registers an irregular mapping for pluralize and singularize" do
      Altair::Inflector.irregular("person", "people")
      Altair::Inflector.irregular("datum", "data")
      Altair::Inflector.pluralize("datum").should eq("data")
      Altair::Inflector.singularize("data").should eq("datum")
    end

    it "overrides the default pluralization" do
      Altair::Inflector.irregular("criterion", "criteria")
      Altair::Inflector.pluralize("criterion").should eq("criteria")
    end
  end
end
