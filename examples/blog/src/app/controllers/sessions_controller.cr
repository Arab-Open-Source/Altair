# Blog — the sessions controller: password login and logout.
class SessionsController < ApplicationController
  def login_page : Nil
    render html: page_html(login_html)
  end

  def login : Nil
    email = params["email"]?.to_s.strip.downcase
    password = params["password"]?.to_s
    if (user = User.find_by_email(email)) && user.authenticate_password(password)
      sign_in(user.id.not_nil!.to_s)
      redirect_to posts_path
    else
      render html: page_html(login_html("Invalid email or password.")),
        status: ::HTTP::Status::UNPROCESSABLE_ENTITY
    end
  end

  def logout : Nil
    sign_out
    redirect_to login_path_route
  end

  private def login_html(error : String? = nil) : String
    error_line = error ? "<p class=\"error\">#{error}</p>" : ""
    <<-HTML
      <h1>Sign in</h1>
      #{error_line}
      <form action="/login" method="post">
        <label>Email <input type="email" name="email" required></label>
        <label>Password <input type="password" name="password" required></label>
        <button>Sign in</button>
      </form>
      <p><a href="/register">Create an account</a></p>
      HTML
  end

  private def login_path_route : String
    "/login"
  end
end
