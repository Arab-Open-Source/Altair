# Routing

Routes are declared in `src/config/routes.cr` with a compile-time DSL:

```crystal
class Blog < Altair::Application
  routes do
    root to: "pages#index"
    get "/posts/:id", to: "posts#show", constraints: {id: /\d+/}
    resources :posts do
      member do
        get :preview
      end
    end
    redirect "/old", to: "/new"
  end
end
```

Helpers such as `post_path(5)` and `new_post_path` are real methods, so a
wrong arity is a compile error. Routing works on URL segments, not regexes.
A `.json` suffix is available as `params["format"]`. `HEAD` matches `GET`
routes and drops the body; `_method` override works on POST forms. Glob
segments must be the last segment. `bin/altair routes` prints the table.
