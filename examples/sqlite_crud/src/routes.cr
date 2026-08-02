# REST routes for the Product MVC resource.
class SQLiteCrud
  routes do
    root to: ProductsController.index
    resources :products
  end
end
