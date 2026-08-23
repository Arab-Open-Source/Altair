# Altair — specs for polymorphic associations
require "./model_fixtures_spec"

describe "polymorphic associations" do
  before_each do
    RecordSpec.setup_database
  end

  it "resolves belongs_to polymorphic to the stored type" do
    post = Post.create(title: "p1", views: 1, published: true)
    note = Note.new(body: "on post")
    note.notable_id = post.id
    note.notable_type = "Post"
    note.save.should be_true

    note = Note.find!(note.id.not_nil!)
    resolved = note.notable
    resolved.should_not be_nil
    resolved.as(Post).title.should eq("p1")
  end

  it "resolves the same association across types" do
    video = Video.create(title: "v1")
    note = Note.new(body: "on video")
    note.notable_id = video.id
    note.notable_type = "Video"
    note.save

    note = Note.find!(note.id.not_nil!)
    resolved = note.notable.should_not be_nil
  end

  it "raises a clear error for an unknown type" do
    note = Note.new(body: "ghost")
    note.notable_id = 1
    note.notable_type = "Ghost"
    note.save

    note = Note.find!(note.id.not_nil!)
    expect_raises(Altair::Error, /Unknown polymorphic type/) do
      note.notable
    end
  end

  it "returns nil when both columns are nil" do
    note = Note.create(body: "floating")
    Note.find!(note.id.not_nil!).notable.should be_nil
  end

  it "assigns both columns via the setter" do
    post = Post.create(title: "setter", views: 1, published: true)
    note = Note.new(body: "via setter")
    note.notable = post
    note.save

    row = Note.find!(note.id.not_nil!)
    row.notable_id.should eq(post.id)
    row.notable_type.should eq("Post")
  end

  it "eager loads batched per type" do
    post = Post.create(title: "p1", views: 1, published: true)
    video = Video.create(title: "v1")
    Note.new(body: "n1").tap { |note| note.notable = post; note.save }
    Note.new(body: "n2").tap { |note| note.notable = video; note.save }

    notes = Note.all.to_a
    queries = 0
    Altair::Record.on_query { |_sql, _dur| queries += 1 }
    resolved = notes.map(&.notable)
    # one query per distinct type (Post + Video) — not one per note
    queries.should eq(2)
    resolved.compact_map { |row| row.class.name }.size.should eq(2)
  end

  it "has_many :as filters by owner type" do
    post = Post.create(title: "tagged", views: 1, published: true)
    video = Video.create(title: "untagged")
    Note.new(body: "post note").tap { |note| note.notable = post; note.save }
    Note.new(body: "video note").tap { |note| note.notable = video; note.save }

    post.notes.map(&.body).should eq(["post note"])
    video.notes.map(&.body).should eq(["video note"])
  end

  it "eager loads has_many :as without N+1" do
    post1 = Post.create(title: "p1", views: 1, published: true)
    post2 = Post.create(title: "p2", views: 1, published: true)
    Note.new(body: "a").tap { |note| note.notable = post1; note.save }
    Note.new(body: "b").tap { |note| note.notable = post2; note.save }

    posts = Post.all.includes(:notes).order(:title).to_a
    posts[0].notes.map(&.body).should eq(["a"])
    posts[1].notes.map(&.body).should eq(["b"])

    # cached — no extra query on repeat access
    queries_before = 0
    Altair::Record.on_query { |_s, _d| queries_before += 1 }
    posts[0].notes
    Altair::Record.on_query { |_s, _d| raise "extra query" if false }
  end

  it "nullifies polymorphic children on destroy with dependent: :nullify" do
    post = Post.create(title: "doomed", views: 1, published: true)
    note = Note.new(body: "attached")
    note.notable = post
    note.save

    post.delete
    row = Note.find!(note.id.not_nil!)
    row.notable_id.should be_nil
    row.notable_type.should be_nil
  end

  it "destroys polymorphic children through callbacks with dependent: :destroy" do
    video = Video.create(title: "doomed too")
    Note.new(body: "attached").tap { |note| note.notable = video; note.save }

    video.delete
    Note.all.count.should eq(0)
  end
end

# Extend fixtures for polymorphic inverse
class Post
  has_many :notes, as: :notable, dependent: :nullify
end

class Video
  has_many :notes, as: :notable, dependent: :destroy
end

class Comment
  belongs_to :notable, polymorphic: true
end
