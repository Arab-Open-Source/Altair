# Altair — view helpers.
#
# Unit specs for the helper methods: link_to, content_tag (string and
# block forms), button_to, javascript_include_tag and attribute
# translation.
require "../spec_helper"

private class HelpersProbe
  include Altair::View::Helpers
end

describe Altair::View::Helpers do
  it "renders a link with escaped name and path" do
    HelpersProbe.new.link_to("A & B", "/a?x=1&y=2").should eq(%(<a href="/a?x=1&amp;y=2">A &amp; B</a>))
  end

  it "renders a link with extra attributes and hx translation" do
    HelpersProbe.new.link_to("Posts", "/posts", class: "nav", hx_get: "/posts").should eq(
      %(<a href="/posts" class="nav" hx-get="/posts">Posts</a>)
    )
  end

  it "renders a content tag with escaped content" do
    HelpersProbe.new.content_tag(:h1, "<b>Hi</b>").should eq("<h1>&lt;b&gt;Hi&lt;/b&gt;</h1>")
  end

  it "renders a content tag with attributes" do
    HelpersProbe.new.content_tag(:button, "Save", type: "submit", data_id: "5").should eq(
      %(<button type="submit" data-id="5">Save</button>)
    )
  end

  it "renders a content tag from a block, embedding its output as-is" do
    HelpersProbe.new.content_tag(:article, class: "card") { "<strong>body</strong>" }.should eq(
      %(<article class="card"><strong>body</strong></article>)
    )
  end

  it "composes a component from block content and nested helpers" do
    probe = HelpersProbe.new
    card = probe.content_tag(:article, class: "card") do
      probe.content_tag(:h2, "Title") + probe.link_to("Read", "/posts/1")
    end
    card.should eq(
      %(<article class="card"><h2>Title</h2><a href="/posts/1">Read</a></article>)
    )
  end

  it "renders a button posting to a path" do
    HelpersProbe.new.button_to("Delete", "/posts/1", method: :delete).should eq(
      %(<form action="/posts/1" method="post"><input type="hidden" name="_method" value="DELETE"><button>Delete</button></form>)
    )
  end

  it "escapes the button action like the link path" do
    HelpersProbe.new.button_to("Go", %(/posts?x=1&y=2)).should eq(
      %(<form action="/posts?x=1&amp;y=2" method="post"><button>Go</button></form>)
    )
  end

  it "translates hx_, data_ and aria_ attributes" do
    HelpersProbe.new.attribute_name(:hx_target).should eq("hx-target")
    HelpersProbe.new.attribute_name(:data_id).should eq("data-id")
    HelpersProbe.new.attribute_name(:aria_label).should eq("aria-label")
    HelpersProbe.new.attribute_name(:class).should eq("class")
  end
end
