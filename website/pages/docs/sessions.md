# Sessions and auth

Sessions, flash messages, CSRF protection and login helpers ship as a
cohesive layer. The session rides a **signed cookie** — values are stored
client-side but a keyed signature makes them unforgeable, so no server-side
store is needed out of the box.

## Enabling sessions

Sessions need a signing secret. `altair new` generates a `.env` with a real
`SECRET_KEY_BASE`; in code you can also set it explicitly:

```crystal
class Blog < Altair::Application
  config.secret_key_base = ENV["SECRET_KEY_BASE"] || "dev-only-secret"
end
```

Production must use a real secret — signing without one lets an attacker
forge session cookies. The framework refuses to build a session store
without a secret.

## Reading and writing the session

Controllers expose `session`, a hash-like view over the signed cookie:

```crystal
session["user_id"] = user.id.to_s   # persists a new cookie
session["theme"]?                    # String? — absent key is nil
session.delete("theme")
session.key?("theme")                # Bool
session.clear                        # wipe everything
session.destroy                      # clear + expire the cookie
```

A session is only persisted when it **changes** — a request that just reads
session state sends no new cookie.

## Flash messages

`flash` is the one-request message store: values written through it appear
on the *next* request and then vanish. `flash.now` writes values visible
only on the current request (for re-rendered forms).

```crystal
def create : Nil
  post = Post.create(title: params["title"]?)
  if post.valid?
    flash[:notice] = "Post created"
    redirect_to posts_path
  else
    flash.now[:alert] = "Post could not be saved"
    render :new, locals: {post: post}
  end
end
```

The flash rides the same signed cookie under a reserved key and never leaks
into user-facing session state (`session.to_h` hides it).

## CSRF protection

A controller opts in with `protect_from_forgery`. Every state-changing
request (`POST`/`PATCH`/`PUT`/`DELETE`) must then carry the session's
authenticity token — as a hidden `_csrf` field or an `X-CSRF-Token` header —
or it answers **422**. Tokens are compared in constant time, so a timing
attack cannot distinguish a wrong token from a missing one.

```crystal
class PostsController < ApplicationController
  protect_from_forgery
end
```

The form helpers embed the token automatically:

```ecr
<% form_for("/posts") do |f| %>
  <%= f.text_field("title") %>
  <%= f.submit("Create") %>
<% end %>
<!-- renders a hidden <input name="_csrf" value="..."> -->
```

API clients send the same token as a header:

```crystal
HTTP::Client.post("/posts", headers: {"X-CSRF-Token" => token})
```

The token itself comes from `form_authenticity_token`, created on first
use. Only controllers that declared `protect_from_forgery` embed one.

## Login helpers

The minimal signed-in contract is a `user_id` key in the session, with
helpers around it:

```crystal
class SessionsController < ApplicationController
  def create : Nil
    user = User.find_by_email(params["email"]?)
    if user && user.authenticate(params["password"]?)
      sign_in(user.id.to_s)                    # session["user_id"] = ...
      redirect_to dashboard_path
    else
      flash.now[:alert] = "Bad email or password"
      render :new
    end
  end

  def destroy : Nil
    sign_out                               # clears the session
    redirect_to root_path
  end
end
```

Available helpers:

- `logged_in?` — true when the session carries a `user_id`
- `current_user_id` — the id, or `nil`; load the full record yourself:
  `current_user_id.try { |id| User.find(id.to_i) }`
- `sign_in(user_id)` — store the id
- `sign_out` — clear the session, preserving flash
- `reset_session` — clear, preserving flash
- `require_login` — a `before_action` filter that redirects to
  `config.login_path` (default `/login`) when not signed in
- `authenticate!` — a filter that answers **401** instead of
  redirecting; the JSON/API counterpart

```crystal
class Admin::PostsController < ApplicationController
  before_action :require_login, except: [:index, :show]
  # or, for an API controller:
  before_action :authenticate!
end
```

## Stateless JWT auth

For APIs that cannot use cookies, `Altair::Auth::JWT` signs and verifies
HS256 tokens. Verification is constant-time and returns `nil` on any
failure, so callers guard with a plain `unless`:

```crystal
token = Altair::Auth::JWT.sign(
  {"sub" => user.id.to_s},
  secret,
  expires_in: 1.hour
)

claims = Altair::Auth::JWT.verify(token, secret)   # Hash(String, String)?
if claims
  user_id = claims["sub"]
end
```

An `exp` claim is honored as-is; `expires_in:` sets the lifetime from now
when the claims carry none.
