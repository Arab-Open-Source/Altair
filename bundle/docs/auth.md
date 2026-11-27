# Authentication

`altair g auth` generates a User model, migration, sessions and registrations
controllers, views and routes. `password_auth` hashes with PBKDF2-SHA256 and
no extra dependency. Controller helpers include `sign_in`, `sign_out`,
`current_user_id`, `require_login` and `authenticate!`.

```crystal
class User < Altair::Record::Model
  table :users
  password_auth min_length: 8
end
```

Session cookies are signed with `SECRET_KEY_BASE` and default to `Secure` in
production, `HttpOnly` and `SameSite=Lax`. `protect_from_forgery` enables CSRF
protection for form controllers. JWT signing is available through
`Altair::Auth::JWT`. Set a real secret in production; never commit `.env`.
