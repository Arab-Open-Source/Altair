# Showcase — the users controller.
#
# Sign-up (new/create) and a public profile page. `show` requires a
# signed-in visitor. Note the `current_user.not_nil!` in `create`: the
# `require_login` before-action has already guaranteed a session, but the
# compiler needs the explicit unwrap because `current_user` is a lookup.
class UsersController < ApplicationController
  templates "users",
    root: __DIR__ + "/../views",
    layout: "application",
    new: {user: User, errors: Array(String)},
    show: {user: User}

  before_action :require_login, only: :show

  # GET /users/new — the sign-up form.
  def new : Nil
    render :new, locals: {user: User.new, errors: [] of String}
  end

  # POST /users — create the account and sign in immediately.
  def create : Nil
    user = User.new(
      name: params["name"]? || "",
      email: params["email"]? || "",
      password: params["password"]? || ""
    )
    if user.save
      sign_in(user.id.to_s)
      flash["notice"] = "Welcome, #{user.name}!"
      redirect_to posts_path
    else
      response.status = ::HTTP::Status::UNPROCESSABLE_ENTITY
      render :new, locals: {user: user, errors: user.errors.full_messages}
    end
  end

  # GET /users/:id — the public profile.
  def show : Nil
    if user = User.find(params.fetch("id", Int32))
      render :show, locals: {user: user}
    else
      render text: "User not found", status: ::HTTP::Status::NOT_FOUND
    end
  end
end
