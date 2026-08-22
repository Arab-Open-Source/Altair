# Altair — the batteries-included web framework for Crystal.
#
# Specs for the asset pipeline's integration seams: `Static` serves
# fingerprinted outputs with immutable caching while plain copies stay
# cache-neutral, and the view helpers resolve through the manifest once the
# project is compiled.
require "../spec_helper"

class AssetTagController < Altair::Controller
  def styles : Nil
    render html: stylesheet_link_tag("css/app.css")
  end

  def scripts : Nil
    render html: javascript_asset_tag("js/app.js")
  end

  def url_only : Nil
    render text: asset_url("css/app.css")
  end
end

class AssetTagsApp < Altair::Application
  routes do
    get "/styles", to: AssetTagController.styles
    get "/scripts", to: AssetTagController.scripts
    get "/asset-url", to: AssetTagController.url_only
  end
end

private def remove_tree(dir : Path) : Nil
  return unless Dir.exists?(dir.to_s)
  Dir.children(dir.to_s).each do |child|
    path = dir / child
    File.directory?(path.to_s) ? remove_tree(path) : File.delete(path)
  end
  Dir.delete(dir.to_s)
end

private def with_asset_app(root_path : Path, & : Int32 -> Nil)
  Altair::Test.boot(AssetTagsApp, configure: ->(app : AssetTagsApp) {
    app.root = root_path
    app.config.middleware = [->(a : Altair::Application) : Altair::Middleware { Altair::Middleware::Static.new(a) }] of Proc(Altair::Application, Altair::Middleware)
  }) do |port|
    yield port
  end
end

describe "asset serving and helpers" do
  result = Path.new("/tmp/opencode/altair-assets-http-#{Random::Secure.hex(4)}")

  before_each do
    Dir.mkdir_p((result / "assets/css").to_s)
    Dir.mkdir_p((result / "assets/js").to_s)
    File.write(result / "assets/css/app.css", "h1 { color: navy; }\n")
    File.write(result / "assets/js/app.js", "// app\n")
    Altair::Assets::Pipeline.new(result).precompile
  end

  after_each do
    remove_tree(result)
  end

  it "serves fingerprinted assets with immutable caching" do
    with_asset_app(result) do |port|
      manifest = Altair::Assets::Pipeline.manifest_for(result)
      response = Altair::Test.get(port, manifest["css/app.css"])
      response.status_code.should eq(200)
      response.headers["Cache-Control"].should eq("public, max-age=31536000, immutable")
      response.body.should contain("navy")
    end
  end

  it "serves plain copies without long-lived caching" do
    with_asset_app(result) do |port|
      response = Altair::Test.get(port, "/assets/css/app.css")
      response.status_code.should eq(200)
      response.headers.has_key?("Cache-Control").should be_false
    end
  end

  it "resolves helper tags through the compiled manifest" do
    with_asset_app(result) do |port|
      manifest = Altair::Assets::Pipeline.manifest_for(result)

      page = Altair::Test.get(port, "/styles")
      page.body.should contain(%(<link rel="stylesheet" href="#{manifest["css/app.css"]}">))

      script = Altair::Test.get(port, "/scripts")
      script.body.should contain(%(<script src="#{manifest["js/app.js"]}" defer></script>))

      raw = Altair::Test.get(port, "/asset-url")
      raw.body.should eq(manifest["css/app.css"])
    end
  end

  it "falls back to plain paths when no manifest exists" do
    File.delete(result / "public/assets/manifest.json")

    with_asset_app(result) do |port|
      page = Altair::Test.get(port, "/styles")
      page.body.should contain(%(<link rel="stylesheet" href="/assets/css/app.css">))
    end
  end
end
