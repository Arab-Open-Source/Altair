# Altair — the batteries-included web framework for Crystal.
#
# This is the framework's own CLI entry point. `shards build altair`
# produces a standalone `altair` binary from this file, and a fresh
# checkout can run the same commands with `crystal run bin/altair.cr`.
require "./altair"

exit Altair::CLI.run(ARGV)
