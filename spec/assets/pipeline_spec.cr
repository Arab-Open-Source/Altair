# Altair — the batteries-included web framework for Crystal.
#
# Specs for the asset pipeline: fingerprinted outputs, the plain dev copy,
# manifest resolution, idempotent recompiles, digest rotation on content
# change, stale pruning and helper tag rendering.
require "../spec_helper"

private def remove_tree(dir : Path) : Nil
  return unless Dir.exists?(dir.to_s)
  Dir.children(dir.to_s).each do |child|
    path = dir / child
    File.directory?(path.to_s) ? remove_tree(path) : File.delete(path)
  end
  Dir.delete(dir.to_s)
end

describe Altair::Assets::Pipeline do
  result = Path.new("/tmp/opencode/altair-assets-spec-#{Random::Secure.hex(4)}")

  before_each do
    Dir.mkdir_p((result / "assets" / "css").to_s)
    Dir.mkdir_p((result / "assets" / "js").to_s)
    File.write(result / "assets/css/app.css", "body { color: rebeccapurple; }\n")
    File.write(result / "assets/js/app.js", "console.log('hi');\n")
    File.write(result / "assets/robots.txt", "User-agent: *\n")
  end

  after_each do
    remove_tree(result)
  end

  it "writes fingerprinted and plain copies plus a manifest" do
    entries = Altair::Assets::Pipeline.new(result).precompile
    entries.size.should eq(3)
    entries.map(&.logical).should eq(["css/app.css", "js/app.js", "robots.txt"])

    css_entry = entries.find! { |e| e.logical == "css/app.css" }
    css_entry.url.should match(%r{/assets/css/app-[0-9a-f]{12}\.css})
    File.exists?(result / "public" / "assets" / "css" / "app.css").should be_true

    published = File.read(result / ("public" + css_entry.url))
    published.should eq("body { color: rebeccapurple; }\n")

    manifest = Altair::Assets::Pipeline.manifest_for(result)
    manifest["css/app.css"]?.should eq(css_entry.url)
    manifest["robots.txt"]?.should_not be_nil
  end

  it "is idempotent: rerunning produces identical digests" do
    first = Altair::Assets::Pipeline.new(result).precompile
    before = Dir.children((result / "public/assets/css").to_s).sort
    second = Altair::Assets::Pipeline.new(result).precompile
    second.map(&.url).should eq(first.map(&.url))
    Dir.children((result / "public/assets/css").to_s).sort.should eq(before)
  end

  it "rotates digests on content change and prunes stale fingerprints" do
    first = Altair::Assets::Pipeline.new(result).precompile
    old_url = first.find! { |e| e.logical == "css/app.css" }.url

    File.write(result / "assets/css/app.css", "body { color: navy; }\n")
    second = Altair::Assets::Pipeline.new(result).precompile
    new_url = second.find! { |e| e.logical == "css/app.css" }.url

    new_url.should_not eq(old_url)
    File.exists?(result / "public" / old_url.lstrip('/')).should be_false
    File.exists?(result / "public" / new_url.lstrip('/')).should be_true
    File.exists?(result / "public/assets/css/app.css").should be_true
  end

  it "returns an empty entry list for a project without assets" do
    empty_root = Path.new("/tmp/opencode/altair-assets-empty-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(empty_root.to_s)
      entries = Altair::Assets::Pipeline.new(empty_root).precompile
      entries.empty?.should be_true
      File.exists?(empty_root / "public/assets/manifest.json").should be_true
    ensure
      remove_tree(empty_root)
    end
  end

  it "reads an absent manifest as an empty hash" do
    missing = Path.new("/tmp/opencode/altair-assets-nomanifest-#{Random::Secure.hex(4)}")
    Dir.mkdir_p(missing.to_s)
    Altair::Assets::Pipeline.manifest_for(missing).empty?.should be_true
    remove_tree(missing)
  end

  it "resolves through the manifest when compiled, else the plain path" do
    Altair::Assets.url(result, "css/app.css").should eq("/assets/css/app.css")

    compiled = Altair::Assets::Pipeline.new(result).precompile
      .find! { |e| e.logical == "css/app.css" }
    Altair::Assets.url(result, "css/app.css").should eq(compiled.url)
    Altair::Assets.url(result, "/css/app.css").should eq(compiled.url)
  end
end
