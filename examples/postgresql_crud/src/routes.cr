# REST routes for the Product MVC resource.
class PostgreSQLCrud
  routes do
    root to: ProductsController.index
    resources :products
  end
end
