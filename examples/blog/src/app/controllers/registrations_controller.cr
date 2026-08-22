# Blog — the registrations controller: account creation.
class RegistrationsController < ApplicationController
  def register_page : Nil
    render html: page_html(register_html(User.new))
  end

  def register : Nil
    user = User.new(email: params["email"]?.to_s.strip.downcase)
    user.password = params["password"]?
    user.password_confirmation = params["password_confirmation"]?
    if user.save
      sign_in(user.id.not_nil!.to_s)
      redirect_to posts_path
    else
      render html: page_html(register_html(user)),
        status: ::HTTP::Status::UNPROCESSABLE_ENTITY
    end
  end

  private def register_html(user : User) : String
    errors = user.errors.full_messages.map { |message| "<p class=\"error\">#{message}</p>" }.join
    <<-HTML
      <h1>Create an account</h1>
      #{errors}
      <form action="/register" method="post">
        <label>Email <input type="email" name="email" value="#{user.email}"></label>
        <label>Password <input type="password" name="password"></label>
        <label>Confirm password <input type="password" name="password_confirmation"></label>
        <button>Register</button>
      </form>
      HTML
  end
end
