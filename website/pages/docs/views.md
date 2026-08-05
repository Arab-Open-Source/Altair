# Views

Views are `.ecr` templates compiled at build time into typed render methods.
Output is **auto-escaped by default** — `<%= %>` escapes, `<%== %>` is raw —
so user input is XSS-safe out of the box.

## Declaring templates

A controller names its view files with `templates`, declaring the locals
each one receives:

```crystal
class TasksController < ApplicationController
  templates "tasks",
    root: __DIR__ + "/../views",
    layout: "application",
    index: {tasks: Array(Task)},
    edit: {task: Task}
end
```

The macro compiles `views/tasks/index.ecr` and `views/tasks/edit.ecr` into
`render :index` and `render :edit`. A wrong local name or type in the action
call is a compile error.

## Template syntax

```ecr
<% if tasks.empty? %>
  <p class="empty">No tasks yet.</p>
<% else %>
  <ul>
    <% tasks.each do |task| %>
      <li><%= task.title %></li>
    <% end %>
  </ul>
<% end %>
```

- `<%= expr %>` — interpolate, escaped
- `<%== expr %>` — interpolate, raw
- `<% code %>` — plain Crystal
- Helper calls (`link_to`, `content_tag`, `render`, the form builder) are
  already escaped HTML, so they render unchanged even inside `<%= %>`.

## Layouts

A template renders inside the layout's `yield`:

```ecr
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Altair</title>
</head>
<body>
  <header><h1><a href="/">Altair</a></h1></header>
  <main>
<% yield %>
  </main>
</body>
</html>
```

Pass `layout: false` to render a bare fragment — handy for partial page
updates.

## Partials

`render` a partial by name with its locals; it returns a String you can
embed anywhere:

```crystal
render "form", locals: {post: post}
```

## Helpers

```ecr
<%= link_to "Edit", "/tasks/#{task.id}/edit" %>
<%= content_tag :li, "task", id: "task-#{task.id}" %>
<%= button_to "delete", "/tasks/#{task.id}", method: :delete %>
<%= javascript_include_tag :htmx %>
```

`link_to` and `button_to` accept extra attributes and pass them through to
the generated tag, so htmx attributes work directly:

```ecr
<%= link_to "edit", "/tasks/#{task.id}/edit", hx_get: "/tasks/#{task.id}/edit",
            hx_target: "#task-#{task.id}", hx_swap: "outerHTML" %>
```

## Form builder

`form_for` yields a builder with typed field helpers; the generated form is
auto-escaped:

```ecr
<% form_for("/tasks") do |f| %>
  <%= f.label("title", "What needs doing?") %>
  <%= f.text_field("title", placeholder: "Add a task") %>
  <%= f.submit("Add") %>
<% end %>
```

Fields include `text_field`, `email_field`, `password_field`, `hidden_field`,
`label` and `submit`. Pass method and htmx attributes through `form_for`:

```ecr
<% form_for("/tasks", hx_post: "/tasks", hx_target: "#task-list", hx_swap: "outerHTML") do |f| %>
  <%= f.text_field("title") %>
  <%= f.submit("Add") %>
<% end %>
```

## htmx

The htmx layer ships helpers for the request side and the response side. On
the request side, `request.hx_request?` tells an action whether the browser
sent the `HX-Request` header, so one action can render a full page or a bare
fragment:

```crystal
render :index, layout: !request.hx_request?, locals: {tasks: @@tasks}
```

On the response side, `hx_trigger_after_swap(:task_changed)` and
`hx_trigger_after_settle(:task_changed)` emit the `HX-Trigger` header, which
the page listens for to update the UI.
