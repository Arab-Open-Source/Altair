# Showcase — the sessions controller.
#
# A singular `resource :session`: one session per visitor. `create` checks
# the email/password against the users table and calls `sign_in`; `destroy`
# signs out via the `DELETE` verb. Login and logout set flash messages that
# the layout renders on the next request.
class SessionsController < ApplicationController
  templates "sessions",
    root: __DIR__ + "/../views",
    layout: "application",
    new: nil

  # GET /session/new — the login form.
  def new : Nil
    if logged_in?
      redirect_to posts_path
    else
      render :new
    end
  end

  # POST /session — verify credentials and start a session.
  def create : Nil
    user = User.find_by_email(params["email"]?)
    if user && user.password == params["password"]?
      sign_in(user.id.to_s)
      flash["notice"] = "Welcome back, #{user.name}!"
      redirect_to posts_path
    else
      flash["alert"] = "Invalid email or password."
      redirect_to new_session_path
    end
  end

  # DELETE /session — end the session and return home.
  def destroy : Nil
    sign_out
    flash["notice"] = "Signed out."
    redirect_to root_path
  end
end
