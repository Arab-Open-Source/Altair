# SQLite3 ORM CRUD

This is a complete MVC web application. `Product` is the model,
`ProductsController` provides the seven REST actions, ECR files are the views,
and SQLite3 stores data in `db/crud.db`.

```bash
shards install
crystal run scripts/db.cr -- migrate
crystal run src/app.cr
```

Open <http://localhost:4100/products>. The UI supports:

- Create: `POST /products`
- Read: `GET /products` and `GET /products/:id`
- Update: `PUT /products/:id`
- Delete: `DELETE /products/:id`

The MVC app includes a migration, generated schema metadata, typed model,
validations, timestamps, REST controller, views and SQLite3 persistence.
