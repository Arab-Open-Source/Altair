# Showcase — the stateless JSON API.
#
# Two endpoints backed by signed JWTs (`Altair::Auth::JWT`, HS256 with the
# application secret). `/api/token` exchanges credentials for a token;
# `/api/me` verifies a `Authorization: Bearer <token>` header. The token
# endpoint skips the session-based CSRF check — this is the entry point
# for clients that carry no session at all.
class ApiController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:token]

  # POST /api/token — issue a token good for one hour.
  def token : Nil
    user = User.find_by_email(params["email"]? || "")
    if user && user.password == params["password"]?
      secret = Showcase.config.secret_key_base.not_nil!
      jwt = Altair::Auth::JWT.sign({"sub" => user.id.to_s}, secret, expires_in: 1.hour)
      render json: {token: jwt, sub: user.id}
    else
      render json: {error: "invalid credentials"}, status: ::HTTP::Status::UNAUTHORIZED
    end
  end

  # GET /api/me — verify the bearer token and answer the user's profile.
  def me : Nil
    token = request.headers["Authorization"]?.try(&.lchop("Bearer ").strip)
    secret = Showcase.config.secret_key_base.not_nil!
    claims = token ? Altair::Auth::JWT.verify(token, secret) : nil
    if claims && (user = User.find(claims["sub"]?.try(&.to_i) || 0))
      render json: {id: user.id, name: user.name, email: user.email}
    else
      render json: {error: "unauthorized"}, status: ::HTTP::Status::UNAUTHORIZED
    end
  end
end
