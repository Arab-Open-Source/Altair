# Hello World — the profiles controller.
#
# A singular resource: there is exactly one profile, so `resource :profile`
# generates routes without an id (`/profile`, never `/profile/:id`) and the
# path helpers take no arguments (`profile_path`, `edit_profile_path`).
# Member routes on a singular resource are id-less too — `get :history`
# gives `GET /profile/history` and `history_profile_path`. The profile and
# its edit history live in memory, like the posts store.
class ProfilesController < ApplicationController
  record Profile, name : String, bio : String

  @@profile = Profile.new("Altair", "A batteries-included web framework for Crystal.")
  @@history = Array(String).new

  def show : Nil
    render html: page_html(<<-HTML)
      <h1>#{@@profile.name}</h1>
      <p>#{@@profile.bio}</p>
      <p><a href="#{edit_profile_path}">Edit profile</a> · <a href="#{history_profile_path}">History</a></p>
      HTML
  end

  def new : Nil
    render html: page_html("<h1>New profile</h1>#{form_html(profile_path)}")
  end

  def create : Nil
    @@profile = Profile.new(params["name"], params["bio"])
    @@history << "created"
    redirect_to profile_path
  end

  def edit : Nil
    render html: page_html("<h1>Edit profile</h1>#{form_html(profile_path, method: "PUT")}")
  end

  def update : Nil
    @@profile = Profile.new(params["name"], params["bio"])
    @@history << "updated"
    redirect_to profile_path
  end

  def destroy : Nil
    @@profile = Profile.new("Altair", "A batteries-included web framework for Crystal.")
    @@history << "reset"
    redirect_to profile_path
  end

  def history : Nil
    rows = @@history.map { |entry| "<li>#{entry}</li>" }.join
    render html: page_html("<h1>Profile history</h1><ul>#{rows}</ul>")
  end

  private def page_html(body : String) : String
    <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <link rel="stylesheet" href="/css/app.css">
          <title>Profile</title>
        </head>
        <body>
          #{body}
          <p><a href="#{profile_path}">Back to profile</a></p>
        </body>
      </html>
      HTML
  end

  private def form_html(action : String, method : String = "POST") : String
    <<-HTML
      <form action="#{action}" method="post">
        <input type="hidden" name="_method" value="#{method}">
        <label>Name <input name="name" value="#{@@profile.name}"></label>
        <label>Bio <input name="bio" value="#{@@profile.bio}"></label>
        <button>Save</button>
      </form>
      HTML
  end
end
