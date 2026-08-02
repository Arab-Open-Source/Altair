# Full MVC CRUD controller backed by the Product model.
class ProductsController < Altair::Controller
  templates "products",
    root: __DIR__ + "/../views",
    layout: "application",
    index: {products: Array(Product)},
    show: {product: Product},
    new: {product: Product},
    edit: {product: Product}

  def index : Nil
    render :index, locals: {products: Product.all.to_a}
  end

  def show : Nil
    if product = find_product
      render :show, locals: {product: product}
    else
      render text: "Product not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  def new : Nil
    render :new, locals: {product: Product.new}
  end

  def create : Nil
    product = Product.new(name: params["name"]? || "")
    product.price = parsed_price
    if product.save
      redirect_to "/products/#{product.id}"
    else
      response.status = ::HTTP::Status::UNPROCESSABLE_ENTITY
      render :new, locals: {product: product}
    end
  end

  def edit : Nil
    if product = find_product
      render :edit, locals: {product: product}
    else
      render text: "Product not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  def update : Nil
    if product = find_product
      product.name = params["name"]? || ""
      product.price = parsed_price
      if product.save
        redirect_to "/products/#{product.id}"
      else
        response.status = ::HTTP::Status::UNPROCESSABLE_ENTITY
        render :edit, locals: {product: product}
      end
    else
      render text: "Product not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  def destroy : Nil
    if product = find_product
      product.delete
      redirect_to "/products"
    else
      render text: "Product not found", status: ::HTTP::Status::NOT_FOUND
    end
  end

  private def find_product : Product?
    params["id"]?.try(&.to_i?).try { |id| Product.find(id) }
  end

  private def parsed_price : Float64
    params["price"]?.try(&.to_f?) || 0.0
  end
end
