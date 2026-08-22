# Blog — the asset pipeline script.
#
# Compiles `assets/` into fingerprinted files under `public/assets/` and
# writes the manifest the view helpers resolve through:
#
# ```
# crystal run scripts/assets.cr
# ```
require "altair"

entries = Altair::Assets::Pipeline.new(Path.new(Dir.current)).precompile
if entries.empty?
  puts "No assets found in assets/."
else
  entries.each { |entry| puts "#{entry.logical} -> #{entry.url}" }
end
