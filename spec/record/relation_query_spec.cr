# Altair — the batteries-included web framework for Crystal.
#
# Specs for the Wave-A query DSL on `Altair::Record::Relation`: negation
# and OR composition of conditions, the extended operator set (`like`,
# `in`, `null`, `not_null`), the relation finders (`first`, `last`,
# `take`, `ids`, `exists?`, `any?`, `none?`, `pick`) and the bulk writes
# (`update_all`, `delete_all`).
require "./model_fixtures_spec"

describe Altair::Record::Relation do
  before_each do
    RecordSpec.setup_database
    Post.create(title: "alpha", views: 3, published: true)
    Post.create(title: "beta", views: 30, published: false)
    Post.create(title: "gamma", views: 12, published: true)
    Post.create(title: "delta", views: 45, published: false)
  end

  describe "negation and alternatives" do
    it "excludes matching pairs with where_not" do
      titles = Post.all.where_not(published: true).map(&.title.not_nil!).sort!
      titles.should eq(["beta", "delta"])
    end

    it "excludes a single column value with where_not" do
      titles = Post.all.where_not(:views, 30).map(&.title.not_nil!).sort!
      titles.should eq(["alpha", "delta", "gamma"])
    end

    it "composes alternatives with or_where keyword pairs" do
      titles = Post.all.where(views: 30).or_where(views: 45).map(&.title.not_nil!).sort!
      titles.should eq(["beta", "delta"])
    end

    it "composes alternatives with or_where operator forms" do
      titles = Post.all.where(:views, :<=, 12).or_where(:views, :>=, 45).map(&.title.not_nil!).sort!
      titles.should eq(["alpha", "delta", "gamma"])
    end

    it "keeps binds aligned across mixed where, where_not and or_where" do
      # The alternative folds into the where_not clause only — the first
      # `where` still ANDs against everything.
      titles = Post.all
        .where(:views, :>, 5)
        .where_not(title: "delta")
        .or_where(title: "alpha")
        .map(&.title.not_nil!).sort!
      titles.should eq(["beta", "gamma"])
    end

    it "carries negated clauses through merge" do
      scope = Post.all.where_not(published: true)
      titles = Post.all.where(:views, :>=, 10).merge(scope).map(&.title.not_nil!).sort!
      titles.should eq(["beta", "delta"])
    end
  end

  describe "extended operators" do
    it "matches substrings with :like" do
      titles = Post.all.where(:title, :like, "%mm%").map(&.title.not_nil!)
      titles.should eq(["gamma"])
    end

    it "filters membership with :in" do
      titles = Post.all.where(:views, :in, [3, 45]).map(&.title.not_nil!).sort!
      titles.should eq(["alpha", "delta"])
    end

    it "matches nothing for an empty :in list" do
      Post.all.where(:views, :in, [] of Altair::Record::Model::Value).to_a.should be_empty
    end

    it "matches missing values with :null" do
      Post.create(title: "epsilon", views: 1, published: true, user_id: 7)
      unowned = Post.all.where(:user_id, :null).map(&.title.not_nil!).sort!
      owned = Post.all.where(:user_id, :not_null).map(&.title.not_nil!)
      unowned.size.should eq(4)
      owned.should eq(["epsilon"])
    end

    it "rejects unknown operators at runtime" do
      expect_raises(ArgumentError) { Post.all.where(:views, :frobnicate, 1) }
    end
  end

  describe "relation finders" do
    it "fetches the first row by primary key when unordered" do
      Post.all.first.title.should eq("alpha")
      Post.all.order(:id, :desc).first.title.should eq("delta")
    end

    it "raises RecordNotFound from first on an empty scope" do
      expect_raises(Altair::Record::RecordNotFound) { Post.all.where(views: 9999).first }
    end

    it "returns nil from first? on an empty scope" do
      Post.all.where(views: 9999).first?.should be_nil
      Post.all.first?.should_not be_nil
    end

    it "fetches the last row by primary key when unordered" do
      Post.all.last.title.should eq("delta")
      Post.all.order(:id, :desc).last.title.should eq("alpha")
    end

    it "returns nil from last? on an empty scope" do
      Post.all.where(views: 9999).last?.should be_nil
    end

    it "bounds take without changing order" do
      Post.all.take(2).map(&.title.not_nil!).should eq(["alpha", "beta"])
    end

    it "lists primary keys with ids" do
      Post.all.ids.should eq([1, 2, 3, 4])
      Post.all.where(published: false).ids.should eq([2, 4])
    end

    it "answers existence without materializing rows" do
      Post.all.exists?.should be_true
      Post.all.where(views: 9999).exists?.should be_false
      Post.all.any?.should be_true
      Post.all.none?.should be_false
      Post.all.where(views: 9999).none?.should be_true
    end

    it "picks a single column value from the leading scoped row" do
      Post.all.order(:views).pick(:title).should eq("alpha")
      Post.all.where(views: 9999).pick(:title).should be_nil
    end
  end

  describe "bulk updates and deletes" do
    it "updates every scoped row in one statement" do
      changed = Post.all.where(published: false).update_all(published: true)
      changed.should eq(2)
      Post.all.map(&.published).uniq!.should eq([true])
    end

    it "returns zero when nothing matches an update" do
      Post.all.where(views: 9999).update_all(views: 1).should eq(0)
    end

    it "deletes every scoped row in one statement" do
      deleted = Post.all.where(published: true).delete_all
      deleted.should eq(2)
      Post.all.map(&.title.not_nil!).sort!.should eq(["beta", "delta"])
    end

    it "returns zero when nothing matches a delete" do
      Post.all.where(views: 9999).delete_all.should eq(0)
    end

    it "refuses bulk writes over joined relations" do
      expect_raises(ArgumentError) { Post.all.joins(:comments).update_all(views: 1) }
      expect_raises(ArgumentError) { Post.all.joins(:comments).delete_all }
    end
  end
end
