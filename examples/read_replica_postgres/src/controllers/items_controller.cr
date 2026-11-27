class ItemsController < Altair::Controller
  def index : Nil
    connection = Altair::Record.connection
    before = connection.query_target_metrics

    items = if params["source"]? == "primary"
              Item.all.on_primary.to_a
            else
              Item.all.to_a
            end

    after = connection.query_target_metrics
    response.headers["X-DB-Target"] = target_for(before, after)
    response.headers["X-DB-Failovers"] = (after[:failovers] - before[:failovers]).to_s
    render json: items.map { |item| item_json(item) }
  end

  def create : Nil
    name = params.fetch("name", String)
    price = params.fetch("price", Float64)

    item = Item.create(name: name, price: price)
    connection = Altair::Record.connection
    before = connection.query_target_metrics
    fetched = Item.find(item.id.not_nil!)
    after = connection.query_target_metrics

    response.headers["X-DB-Target"] = target_for(before, after)
    response.headers["X-DB-Failovers"] = (after[:failovers] - before[:failovers]).to_s
    render json: {
      id:          fetched.try(&.id),
      name:        fetched.try(&.name),
      price:       fetched.try(&.price),
      wrote_on:    "primary",
      read_target: target_for(before, after),
    }, status: ::HTTP::Status::CREATED
  end

  private def item_json(item : Item)
    {id: item.id, name: item.name, price: item.price}
  end

  private def target_for(
    before : NamedTuple(primary: Int64, replica: Int64, failovers: Int64),
    after : NamedTuple(primary: Int64, replica: Int64, failovers: Int64),
  ) : String
    (after[:primary] - before[:primary]).positive? ? "primary" : "replica"
  end
end
