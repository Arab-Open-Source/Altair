# Altair + htmx

A working [Altair](https://github.com/Arab-Open-Source/Altair) application
that shows the Phase 3 view stack in the browser: `.ecr` views compiled at
compile time by the `templates` macro, layouts with `yield`, partials,
helpers — and the framework's htmx layer. Add, edit and delete tasks
without a single page reload.

## Requirements

- [Crystal](https://crystal-lang.org) `>= 1.21.0`

No other dependencies. htmx is loaded from a pinned CDN
(`https://unpkg.com/htmx.org@2.0.10/dist/htmx.min.js`) — the framework's
default source, configurable via `config.htmx_src` / `config.htmx_version`
or per call with `javascript_include_tag :htmx, from: "/js/htmx.min.js"`.

## Run

```bash
# from inside examples/htmx/
crystal run src/htmx.cr
```

The server boots on `http://localhost:3001`. Open it in a browser, add a
task, edit it, delete it — the task list swaps in place and a toast
appears after every change (the server sets `HX-Trigger: task_changed`,
and the layout listens for it with `hx-on:task-changed`).

## What to look at

| File | Shows |
|------|-------|
| `src/config/application.cr` | Routes — plain REST, no special htmx routes |
| `src/app/controllers/tasks_controller.cr` | One `templates` call, typed locals, `hx_trigger`, fragment vs full page |
| `src/app/views/layouts/application.ecr` | Layout with `yield` + `javascript_include_tag :htmx` |
| `src/app/views/tasks/index.ecr` | The list fragment: `link_to` / `button_to` with `hx_*` attributes, `form_for` with `hx_post` |
| `src/app/views/tasks/edit.ecr` | Inline editing — the edit form swaps in place of the `<li>` |

## How it works

- **One action, two worlds.** Every action renders a bare fragment when the
  request carries `HX-Request` and a full page otherwise
  (`layout: !request.hx_request?`). htmx flows get lightweight responses;
  opening the same URL in a browser gets the full document.
- **Fragments swap by id.** The list lives in `<section id="task-list">`,
  and every form targets it (`hx-target="#task-list" hx-swap="outerHTML"`),
  so one template serves the page and every mutation.
- **`hx_*` attributes are just attributes.** `link_to`, `button_to` and
  `form_for` translate `hx_post:` to `hx-post="..."` — htmx is a
  convention, not a framework dependency. The "delete" button still works
  without JavaScript via the `_method` override.
- **`HX-Trigger` drives the UI.** `hx_trigger(:task_changed)` sets the
  response header; the layout's toast element listens with
  `hx-on:task-changed`.
- **Views are compile-time.** A typo in a local name fails the build; a
  missing template file fails the build; `<%= %>` escapes by default.

## Routes

| Method | Path | Action | Fragment |
|--------|------|--------|----------|
| `GET` | `/` | `tasks#index` | — |
| `POST` | `/tasks` | `tasks#create` | the list |
| `GET` | `/tasks/:id/edit` | `tasks#edit` | the `<li>` being edited |
| `POST` | `/tasks/:id` | `tasks#update` | the list |
| `DELETE` | `/tasks/:id` | `tasks#destroy` | the list |

## Project structure

```
htmx/
├── public/
│   └── css/
│       └── app.css             # stylesheet served by the static-files middleware
└── src/
    ├── htmx.cr                 # entry point: requires the app, then runs it
    ├── config/
    │   └── application.cr      # configuration and routes
    └── app/
        ├── controllers/
        │   ├── application_controller.cr  # base class including HtmxApp::RouteHelpers
        │   └── tasks_controller.cr        # the tasks resource + the templates call
        └── views/
            ├── layouts/
            │   └── application.ecr        # shared HTML with the htmx script
            └── tasks/
                ├── index.ecr              # the task list fragment
                └── edit.ecr               # the inline edit form fragment
```

## License

This example is part of [Altair](LICENSE), which is released under the MIT
License.
