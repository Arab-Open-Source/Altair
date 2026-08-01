# htmx — the tasks controller.
#
# One `templates` call declares the view files and compiles them into
# typed render methods. Locals are declared per template, so a wrong local
# is a compile error. Every action renders a bare fragment when the request
# comes from htmx (`HX-Request`) and a full page otherwise — the same
# action serves both worlds.
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
    @@tasks << Task.new(@@next_id, params["title"])
    @@next_id += 1
    hx_trigger(:task_changed)
    render :index, layout: false, locals: {tasks: @@tasks}
  end

  def edit : Nil
    render :edit, layout: false, locals: {task: find_task}
  end

  def update : Nil
    task = find_task
    task.title = params["title"]
    hx_trigger(:task_changed)
    render :index, layout: false, locals: {tasks: @@tasks}
  end

  def destroy : Nil
    @@tasks.reject!(&.id.==(params["id"].to_i))
    hx_trigger(:task_changed)
    render :index, layout: false, locals: {tasks: @@tasks}
  end

  private def find_task : Task
    @@tasks.find(&.id.==(params["id"].to_i)) || raise Altair::Error.new("Task not found")
  end
end
