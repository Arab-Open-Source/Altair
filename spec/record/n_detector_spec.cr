# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Record::NDetector`: the development-mode N+1 detector
# arms only in the Development environment with the config flag enabled,
# counts identical SQL within a request window, warns once a statement
# crosses the threshold, resets at every request boundary and stays inert
# outside a window.
require "../spec_helper"
require "./model_fixtures_spec"
require "log/io_backend"

private def with_environment(env : Altair::Env, &block : -> Nil) : Nil
  previous = Altair.env
  Altair.env = env
  begin
    block.call
  ensure
    Altair.env = previous
  end
end

private def arm_detector(detect : Bool = true, threshold : Int32 = 3) : Nil
  app = SpecApp.instance
  app.config.detect_n_plus_one = detect
  app.config.n_plus_one_threshold = threshold
  Altair::Core::RequestHandler.new(app)
  nil
end

private def with_log_capture(&block : -> Nil) : String
  io = IO::Memory.new
  backend = Log::IOBackend.new(io, dispatcher: Log::DispatchMode::Sync)
  Log.builder.bind("altair.record", :info, backend)
  begin
    block.call
  ensure
    Log.builder.clear
  end
  io.to_s
end

private def seed_posts(count : Int32) : Array(Post)
  posts = Array.new(count) { |index| Post.create(title: "P#{index}", views: index) }
  posts.each { |post| Comment.create(post_id: post.id, body: "b") }
  posts
end

describe Altair::Record::NDetector do
  before_each do
    RecordSpec.setup_database
  end

  after_each do
    SpecApp.instance.config.detect_n_plus_one = true
    SpecApp.instance.config.n_plus_one_threshold = 3
  end

  it "does not arm outside the Development environment" do
    with_environment(Altair::Env::Test) do
      arm_detector
      Altair::Record::NDetector.enabled?.should be_false
    end
  end

  it "does not arm when the config flag is disabled" do
    with_environment(Altair::Env::Development) do
      arm_detector(detect: false)
      Altair::Record::NDetector.enabled?.should be_false
    end
  end

  it "arms in Development when the flag is enabled" do
    with_environment(Altair::Env::Development) do
      arm_detector
      Altair::Record::NDetector.enabled?.should be_true
    end
  end

  it "warns when the same SQL fires past the threshold within a request" do
    with_environment(Altair::Env::Development) do
      arm_detector
      posts = seed_posts(4)
      output = with_log_capture do
        Altair::Record::NDetector.begin_request
        posts.each { |post| post.comments.size }
        Altair::Record::NDetector.end_request
      end
      output.should contain("likely N+1")
      output.should contain("eager load it with `includes`")
    end
  end

  it "stays silent below the threshold" do
    with_environment(Altair::Env::Development) do
      arm_detector
      posts = seed_posts(2)
      output = with_log_capture do
        Altair::Record::NDetector.begin_request
        posts.each { |post| post.comments.size }
        Altair::Record::NDetector.end_request
      end
      output.should_not contain("likely N+1")
    end
  end

  it "warns exactly once per statement per request" do
    with_environment(Altair::Env::Development) do
      arm_detector
      posts = seed_posts(9)
      output = with_log_capture do
        Altair::Record::NDetector.begin_request
        posts.each { |post| post.comments.size }
        Altair::Record::NDetector.end_request
      end
      output.scan("likely N+1").size.should eq(1)
    end
  end

  it "resets the count at every request boundary" do
    with_environment(Altair::Env::Development) do
      arm_detector
      posts = seed_posts(4)
      output = with_log_capture do
        Altair::Record::NDetector.begin_request
        posts.first(2).each { |post| post.comments.size }
        Altair::Record::NDetector.end_request
        Altair::Record::NDetector.begin_request
        posts.last(2).each { |post| post.comments.size }
        Altair::Record::NDetector.end_request
      end
      output.should_not contain("likely N+1")
    end
  end

  it "logs nothing outside a request window" do
    with_environment(Altair::Env::Development) do
      arm_detector
      posts = seed_posts(9)
      output = with_log_capture do
        posts.each { |post| post.comments.size }
      end
      output.should_not contain("likely N+1")
    end
  end

  it "respects a raised threshold" do
    with_environment(Altair::Env::Development) do
      arm_detector(threshold: 6)
      posts = seed_posts(5)
      output = with_log_capture do
        Altair::Record::NDetector.begin_request
        posts.each { |post| post.comments.size }
        Altair::Record::NDetector.end_request
      end
      output.should_not contain("likely N+1")
    end
  end

  it "warns for each distinct repeated statement" do
    with_environment(Altair::Env::Development) do
      arm_detector
      posts = seed_posts(4)
      output = with_log_capture do
        Altair::Record::NDetector.begin_request
        posts.each { |post| post.comments.size }
        posts.each { |post| post.comments.each { |comment| comment.post_id } }
        Altair::Record::NDetector.end_request
      end
      output.scan("likely N+1").size.should eq(1)
    end
  end

  it "logs nothing for an empty request window" do
    with_environment(Altair::Env::Development) do
      arm_detector
      output = with_log_capture do
        Altair::Record::NDetector.begin_request
        Altair::Record::NDetector.end_request
      end
      output.should be_empty
    end
  end
end
