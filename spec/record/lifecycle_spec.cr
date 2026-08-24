# Altair — record lifecycle specs.
#
# Specs for post-commit lifecycle hooks (`after_commit` /
# `after_rollback`) and the direct-write helpers (`touch`,
# `increment!`, `decrement!`). Commit hooks bind to the record's own
# save or delete completing — nested manual transactions release as
# savepoints and do not defer them.
require "./model_fixtures_spec"

class AuditedWidget < Altair::Record::Model
  table :audit_widgets

  getter log = [] of Symbol

  before_save :log_before_save
  after_commit :log_commit
  after_rollback :log_rollback

  def log_before_save
    @log << :before_save
  end

  def log_commit
    @log << :commit
  end

  def log_rollback
    @log << :rollback
  end
end

class RollbackWidget < Altair::Record::Model
  table :audit_widgets

  class_property? boom = false

  getter log = [] of Symbol

  after_save :maybe_boom
  after_commit :log_commit
  after_rollback :log_rollback

  def maybe_boom
    raise "boom" if @@boom
  end

  def log_commit
    @log << :commit
  end

  def log_rollback
    @log << :rollback
  end
end

describe Altair::Record::Model, "lifecycle" do
  before_each do
    RecordSpec.setup_database
    RollbackWidget.boom = false
  end

  describe "commit and rollback hooks" do
    it "fires after_commit once the create transaction lands" do
      widget = AuditedWidget.create(name: "kept")
      widget.log.should eq([:before_save, :commit])
      AuditedWidget.find(widget.id.not_nil!).should_not be_nil
    end

    it "fires after_commit around updates" do
      widget = AuditedWidget.create(name: "kept")
      widget.log.clear
      widget.update(name: "renamed").should be_true
      widget.log.should eq([:before_save, :commit])
    end

    it "fires after_commit around deletes" do
      widget = AuditedWidget.create(name: "kept")
      widget.log.clear
      widget.delete.should be_true
      widget.log.should eq([:commit])
    end

    it "fires after_rollback and leaves no row when a callback raises" do
      RollbackWidget.boom = true
      widget = RollbackWidget.new(name: "lost")
      expect_raises(Exception, /boom/) { widget.save }
      RollbackWidget.all.to_a.should be_empty
      widget.log.last.should eq(:rollback)
    end
  end

  describe "touch" do
    it "bumps updated_at without running save callbacks" do
      widget = AuditedWidget.create(name: "kept")
      widget.log.clear
      before = widget.updated_at.not_nil!
      sleep 10.milliseconds
      widget.touch
      reloaded = AuditedWidget.find!(widget.id.not_nil!)
      reloaded.updated_at.not_nil!.should be > before
      widget.log.should be_empty
    end

    it "also bumps explicitly listed timestamp columns" do
      widget = AuditedWidget.create(name: "kept")
      created_before = widget.created_at.not_nil!
      sleep 10.milliseconds
      widget.touch(:created_at)
      reloaded = AuditedWidget.find!(widget.id.not_nil!)
      reloaded.created_at.not_nil!.should be > created_before
      reloaded.counter.should eq(0)
    end

    it "raises on a new record" do
      expect_raises(Altair::Error) { AuditedWidget.new(name: "fresh").touch }
    end
  end

  describe "atomic counters" do
    it "increments in one statement and reloads the attribute" do
      widget = AuditedWidget.create(name: "kept")
      widget.increment!(:counter)
      widget.counter.should eq(1)
      AuditedWidget.find!(widget.id.not_nil!).counter.should eq(1)
      widget.increment!(:counter, 4).counter.should eq(5)
    end

    it "decrements symmetrically" do
      widget = AuditedWidget.create(name: "kept")
      widget.increment!(:counter, 7)
      widget.decrement!(:counter, 3).counter.should eq(4)
    end
  end
end
