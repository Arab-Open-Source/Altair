# Rails vs Altair benchmark — item read/write endpoints answering k6's load,
# mirroring the Altair ItemsController 1:1.
class ItemsController < ApplicationController
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  # Liveness probe used by the runner to wait for readiness.
  def health
    render json: { ok: true }
  end

  # GET /items/:id — one row by primary key.
  def show
    item = Item.find(params[:id])
    render json: { id: item.id, name: item.name, price: item.price.to_f }
  end

  # POST /items — insert one row from a JSON body.
  def create
    payload = JSON.parse(request.body.read)
    item = Item.create!(name: payload["name"], price: BigDecimal(payload["price"].to_s))
    render json: { id: item.id }, status: :created
  rescue JSON::ParserError, ActiveRecord::RecordInvalid, KeyError
    render json: { error: "name and numeric price required" }, status: :bad_request
  end

  private

  def not_found
    render json: { error: "not found" }, status: :not_found
  end
end