# Hello World — the posts controller.
#
# A simple in-memory resource: posts live in an array (no database before
# Phase 5) and the seven RESTful actions from `resources :posts` are
# implemented as class methods.
class PostsController
  class Post
    property id : Int32
    property title : String

    def initialize(@id : Int32, @title : String)
    end
  end

  @@posts = Array(Post).new
  @@next_id = 1

  def self.index(request : Altair::HTTP::Request, response : Altair::HTTP::Response) : Nil
    body = @@posts.map { |post| "<li>#{post.id}: #{post.title}</li>" }.join
    response.html("<h1>Posts</h1><ul>#{body}</ul>")
  end

  def self.new(request : Altair::HTTP::Request, response : Altair::HTTP::Response) : Nil
    response.html("<h1>New Post</h1><form method=\"post\" action=\"/posts\"><input name=\"title\"><button>Create</button></form>")
  end

  def self.create(request : Altair::HTTP::Request, response : Altair::HTTP::Response) : Nil
    @@posts << Post.new(@@next_id, request.params["title"])
    @@next_id += 1
    response.redirect("/posts")
  end

  def self.show(request : Altair::HTTP::Request, response : Altair::HTTP::Response) : Nil
    if post = find(request.params["id"].to_i)
      response.html("<h1>#{post.title}</h1><p>Post ##{post.id}</p>")
    else
      response.status = ::HTTP::Status::NOT_FOUND
      response.print("404 Not Found")
    end
  end

  def self.edit(request : Altair::HTTP::Request, response : Altair::HTTP::Response) : Nil
    if post = find(request.params["id"].to_i)
      response.html("<h1>Edit #{post.title}</h1>")
    else
      response.status = ::HTTP::Status::NOT_FOUND
      response.print("404 Not Found")
    end
  end

  def self.update(request : Altair::HTTP::Request, response : Altair::HTTP::Response) : Nil
    if post = find(request.params["id"].to_i)
      post.title = request.params["title"]
      response.redirect("/posts/#{post.id}")
    else
      response.status = ::HTTP::Status::NOT_FOUND
      response.print("404 Not Found")
    end
  end

  def self.destroy(request : Altair::HTTP::Request, response : Altair::HTTP::Response) : Nil
    if post = find(request.params["id"].to_i)
      @@posts.delete(post)
      response.redirect("/posts")
    else
      response.status = ::HTTP::Status::NOT_FOUND
      response.print("404 Not Found")
    end
  end

  private def self.find(id : Int32) : Post?
    @@posts.find { |post| post.id == id }
  end
end
