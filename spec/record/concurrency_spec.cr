# Specs for concurrency correctness: `Relation#lock` (SELECT ... FOR
# UPDATE), `Model#upsert` (INSERT ... ON CONFLICT DO UPDATE), and
# unique-index-backed uniqueness — a constraint violation surfaces as a
# validation error instead of a raised exception. The same battery runs on
# SQLite (default) and PostgreSQL (gated on ALTAIR_TEST_PG_URL).
require "../spec_helper"
require "./model_fixtures_spec"

class ConcurrencyItem < Altair::Record::Model
  table :concurrency_items
end

module ConcurrencySpec
  def self.setup_table : Nil
    connection = Altair::Record.connection
    postgres = connection.adapter.supports_returning?(:insert)
    id_column = postgres ? "\"id\" INTEGER GENERATED ALWAYS AS IDENTITY" : "id INTEGER PRIMARY KEY AUTOINCREMENT"
    connection.exec("DROP TABLE IF EXISTS concurrency_items")
    connection.exec(
      "CREATE TABLE concurrency_items (" \
      "#{id_column}, " \
      "\"slug\" TEXT NOT NULL UNIQUE, " \
      "\"views\" INTEGER NOT NULL DEFAULT 0, " \
      "\"created_at\" TIMESTAMP, \"updated_at\" TIMESTAMP)"
    )
  end
end

private def concurrency_contract(name : String, setup : Proc(Nil), teardown : Proc(Nil)? = nil)
  describe name do
    before_each { setup.call }
    after_each do
      # The battery writes outside transactions (that is the point of the
      # upsert examples); drop the table so no row outlives the example
      # into later files sharing this database file.
      Altair::Record.connection.exec("DROP TABLE IF EXISTS concurrency_items")
      teardown.try(&.call)
    end

    describe "#lock" do
      it "raises on engines without row locks" do
        unless Altair::Record.connection.adapter.supports_select_for_update?
          expect_raises(ArgumentError) do
            ConcurrencyItem.all.lock.to_a
          end
        end
      end

      it "runs the locked query inside a transaction on row-lock engines" do
        next unless Altair::Record.connection.adapter.supports_select_for_update?
        ConcurrencyItem.create(slug: "locked", views: 1)
        rows = nil
        ConcurrencyItem.transaction do
          rows = ConcurrencyItem.all.where(slug: "locked").lock.to_a
        end
        rows.not_nil!.size.should eq(1)
      end
    end

    describe "#upsert" do
      it "inserts when the conflict target is new" do
        item = ConcurrencyItem.new(slug: "first", views: 5)
        item.upsert(conflict_target: [:slug])
        item.id.should_not be_nil
        ConcurrencyItem.count.should eq(1)
        ConcurrencyItem.find(item.id.not_nil!).not_nil!.views.should eq(5)
      end

      it "updates the conflicting row instead of raising" do
        ConcurrencyItem.create(slug: "dup", views: 1)
        item = ConcurrencyItem.new(slug: "dup", views: 42)
        item.upsert(conflict_target: [:slug])
        ConcurrencyItem.count.should eq(1)
        stored = ConcurrencyItem.all.where(slug: "dup").first.not_nil!
        stored.views.should eq(42)
        item.id.should eq(stored.id)
      end

      it "honors an explicit update_columns list" do
        ConcurrencyItem.create(slug: "scoped", views: 1)
        item = ConcurrencyItem.new(slug: "scoped", views: 99)
        item.upsert(conflict_target: [:slug], update_columns: [] of Symbol)
        stored = ConcurrencyItem.all.where(slug: "scoped").first.not_nil!
        stored.views.should eq(1)
      end

      it "rejects unknown columns" do
        expect_raises(ArgumentError) do
          ConcurrencyItem.new(slug: "x").upsert(conflict_target: [:nonsense])
        end
      end
    end

    describe "unique-index-backed uniqueness" do
      it "turns a constraint violation into validation errors" do
        ConcurrencyItem.create(slug: "taken", views: 0)
        dupe = ConcurrencyItem.new(slug: "taken", views: 0)
        dupe.save.should be_false
        dupe.errors[:slug].should eq(["has already been taken"])
        ConcurrencyItem.count.should eq(1)
      end
    end
  end
end

concurrency_contract("concurrency correctness", -> { ConcurrencySpec.setup_table })

# PostgreSQL arm: point the shared application at the contract database
# for the duration of the battery, then restore the original instance.
class ConcurrencyPgApp < Altair::Application
  class_property original : Altair::Application? = nil
end

private def pg_setup : Nil
  ConcurrencyPgApp.original = Altair.application_instance
  Altair.application_instance = nil
  Altair::Record.close_connection
  ConcurrencyPgApp.instance
  ConcurrencyPgApp.config.db_url = ENV["ALTAIR_TEST_PG_URL"]?
  ConcurrencySpec.setup_table
end

private def pg_teardown : Nil
  Altair.application_instance = ConcurrencyPgApp.original
  Altair::Record.close_connection
end

if ENV["ALTAIR_TEST_PG_URL"]?
  concurrency_contract("concurrency correctness on PostgreSQL", -> { pg_setup }, -> { pg_teardown })
else
  it "runs the PostgreSQL concurrency contract when ALTAIR_TEST_PG_URL is set" do
    pending! "set ALTAIR_TEST_PG_URL to run the PostgreSQL concurrency contract"
  end
end
