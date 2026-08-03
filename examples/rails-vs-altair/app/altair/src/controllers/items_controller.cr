# Altair benchmark — item read/write endpoints answering k6's load.
class ItemsController < ApplicationController
  # Liveness probe used by the runner to wait for readiness.
  def health : Nil
    render json: %({"ok":true})
  end

  # GET /items/:id — one row by primary key.
  def show : Nil
    id = params["id"]?.try(&.to_i?)
    unless id
      render json: %({"error":"bad id"}), status: ::HTTP::Status::BAD_REQUEST
      return
    end
    item = Item.find(id.not_nil!)
    if item
      render json: item_json(item)
    else
      render json: %({"error":"not found"}), status: ::HTTP::Status::NOT_FOUND
    end
  end

  # POST /items — insert one row from a JSON body.
  def create : Nil
    raw = request.body
    if raw.nil? || raw.empty?
      render json: %({"error":"body required"}), status: ::HTTP::Status::BAD_REQUEST
      return
    end
    payload = JSON.parse(raw)
    name = payload["name"]?.try(&.as_s)
    price = payload["price"]? ? payload["price"].try(&.as_f) : nil
    if name.nil? || price.nil?
      render json: %({"error":"name and numeric price required"}), status: ::HTTP::Status::BAD_REQUEST
      return
    end
    item = Item.create(name: name.not_nil!, price: price.not_nil!)
    render json: "{\"id\":#{item.id}}", status: ::HTTP::Status::CREATED
  end

  private def item_json(item : Item) : String
    String.build do |io|
      JSON.build(io) do |json|
        json.object do
          json.field "id", item.id
          json.field "name", item.name
          json.field "price", item.price
        end
      end
    end
  end
end
