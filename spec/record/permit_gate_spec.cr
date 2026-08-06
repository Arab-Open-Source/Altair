# Altair — the database admission control policy.
#
# Specs for `Altair::Record::PermitGate`: arming from a config value, the
# notorious no-op when disabled, and capping concurrent connection
# acquisitions to the configured limit.
require "../spec_helper"

private def reset_gate : Nil
  Altair::Record::PermitGate.enable(0)
  nil
end

private def gate_connection : Altair::Record::Connection
  conn = Altair::Record.connection_for(SpecApp.instance)
  conn.exec("DROP TABLE IF EXISTS widgets")
  conn.exec("CREATE TABLE widgets (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL)")
  conn
end

describe Altair::Record::PermitGate do
  after_each { reset_gate }

  it "is inert until armed" do
    Altair::Record::PermitGate.enabled?.should be_false
  end

  it "arms when given a positive limit" do
    Altair::Record::PermitGate.enable(4)
    Altair::Record::PermitGate.enabled?.should be_true
  end

  it "caps concurrent acquisitions to the configured limit" do
    Altair::Record::PermitGate.enable(2)
    conn = Altair::Record.connection_for(SpecApp.instance)
    conn.exec("DROP TABLE IF EXISTS gates")
    conn.exec("CREATE TABLE gates (id INTEGER PRIMARY KEY AUTOINCREMENT)")
    begin
      lock = Mutex.new
      current = 0
      peak = 0
      done = Channel(Bool).new
      n = 8
      n.times do
        spawn do
          lock.synchronize do
            current += 1
            peak = current if current > peak
          end
          conn.exec("INSERT INTO gates DEFAULT VALUES")
        ensure
          lock.synchronize { current -= 1 }
          done.send(true)
        end
      end
      n.times { done.receive }
      peak.should be <= 2
    ensure
      conn.close
    end
  end

  it "allows standalone calls past the gate when no limit is set" do
    Altair::Record::PermitGate.enable(0)
    conn = gate_connection
    begin
      count = conn.query_one("SELECT COUNT(*) FROM widgets") { |rs| rs.read(Int64) }
      count.should eq(0)
    ensure
      conn.close
    end
  end

  it "raises a bounded timeout when no permit frees up within the deadline" do
    Altair::Record::PermitGate.enable(1, 30.milliseconds)
    began = Channel(Nil).new
    release = Channel(Nil).new
    finished = Channel(Bool).new
    # Hold the single permit on another fiber until told otherwise.
    spawn do
      Altair::Record.run_checkout_hooks do
        began.send(nil)
        release.receive
      end
    ensure
      finished.send(true)
    end
    began.receive
    # A contended acquisition must time out instead of parking forever.
    expect_raises(Altair::Concurrency::Timeout) do
      Altair::Record.run_checkout_hooks { }
    end
    release.send(nil)
    finished.receive.should be_true
    # The held permit was returned, so a fresh acquisition succeeds.
    Altair::Record.run_checkout_hooks { }.should be_nil
  end
end
