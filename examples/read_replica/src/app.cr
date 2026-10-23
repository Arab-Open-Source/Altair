# Read-replica demo — the application.
#
# `config.db_replica_url` opens a second pool. Plain SELECTs run against
# it; any write or transaction pins the request fiber's reads to the
# primary, so a handler never reads a stale copy of its own writes.
require "altair"
require "../db/schema"

class Note < Altair::Record::Model
  table :notes
end

class NotesController < Altair::Controller
  def index : Nil
    notes = Note.all.to_a
    pool = Altair::Record.connection.replica_routed? ? "replica" : "primary"
    body = String.build do |io|
      io << "served by: #{pool}\n"
      notes.each { |note| io << "- #{note.id}: #{note.body}\n" }
    end
    response.text(body)
  end

  def create : Nil
    note = Note.create(body: params["body"])
    # Same fiber as the write: reads stay pinned to the primary, so the
    # row is visible immediately even though fresh requests read the
    # replica.
    fetched = Note.find(note.id.not_nil!)
    pool = Altair::Record.connection.replica_routed? ? "replica" : "primary"
    response.text("wrote note #{note.id}\nsame-fiber read served by: #{pool} -> #{fetched.try(&.body)}\n")
  end

  def routing : Nil
    connection = Altair::Record.connection
    pool = connection.replica_routed? ? "replica" : "primary"
    response.text("plain SELECTs route to: #{pool}\n")
  end
end

class ReplicaDemo < Altair::Application
  config.name = "read_replica"
  config.db_url = "sqlite3://./db/primary.db"
  config.db_replica_url = "sqlite3://./db/replica.db"

  routes do
    get "/notes", to: NotesController.index
    post "/notes", to: NotesController.create
    get "/routing", to: NotesController.routing
  end
end
