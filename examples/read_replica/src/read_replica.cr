# Read-replica demo — entry point.
#
#   crystal run scripts/db.cr -- migrate   # build both databases
#   crystal run src/read_replica.cr        # serve on http://localhost:4000
require "./app"

ReplicaDemo.run!
