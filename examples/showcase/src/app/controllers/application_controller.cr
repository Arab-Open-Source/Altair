# Showcase — the shared controller base.
#
# Every controller inherits CSRF protection (`protect_from_forgery`): any
# state-changing request without a valid `_csrf` field or `X-CSRF-Token`
# header is rejected with 422. The generated path helpers are mixed in when
# `config/routes.cr` reopens this class.
abstract class ApplicationController < Altair::Controller
  protect_from_forgery

  @current_user : User?

  # The signed-in user record, or `nil`. Loaded once per request from the
  # session's `user_id`.
  private def current_user : User?
    @current_user ||= current_user_id.try(&.to_i).try { |id| User.find(id) }
  end

  # A `before_action` that redirects unauthenticated visitors to the login
  # page. Each controller opts in where it is needed. Public so the
  # callback runner can invoke it through the typed receiver.
  def require_login : Nil
    redirect_to new_session_path unless logged_in?
  end
end
