# htmx — the tasks controller.
#
# One `templates` call declares the view files and compiles them into
# typed render methods. Locals are declared per template, so a wrong local
# is a compile error. Every action renders a bare fragment when the request
# comes from htmx (`HX-Request`) and a full page otherwise — the same
# action serves both worlds.
#
# Params are fetched with types (`params.fetch("id", Int32)` — malformed
# ids become 422, never a 500), and missing tasks raise `KeyError`, which
# the app turns into a 404 via `rescue_from` — try deleting a task that
# is already gone.
class Task
  getter id : Int32
  property title : String

  def initialize(@id : Int32, @title : String)
  end
end

class TasksController < ApplicationController
  templates "tasks",
    root: __DIR__ + "/../views",
    layout: "application",
    index: {tasks: Array(Task)},
    edit: {task: Task}

  @@tasks = [] of Task
  @@next_id = 1

  def index : Nil
    render :index, layout: !request.hx_request?, locals: {tasks: @@tasks}
  end

  def create : Nil
    @@tasks << Task.new(@@next_id, params.fetch("title", String))
    @@next_id += 1
    hx_trigger_after_swap(:task_changed)
    render :index, layout: false, locals: {tasks: @@tasks}
  end

  def edit : Nil
    render :edit, layout: false, locals: {task: find_task}
  end

  def update : Nil
    task = find_task
    task.title = params.fetch("title", String)
    hx_trigger_after_settle(:task_changed)
    render :index, layout: false, locals: {tasks: @@tasks}
  end

  def destroy : Nil
    index = @@tasks.index(&.id.==(params.fetch("id", Int32)))
    raise KeyError.new("Task #{params["id"]} not found") unless index
    @@tasks.delete_at(index)
    hx_trigger(:task_changed)
    render :index, layout: false, locals: {tasks: @@tasks}
  end

  private def find_task : Task
    @@tasks.find(&.id.==(params.fetch("id", Int32))) || raise KeyError.new("Task not found")
  end
end
