# PostgreSQL ORM CRUD

This is a complete MVC web application. `Product` is the model,
`ProductsController` provides the seven REST actions, ECR files are the views,
and PostgreSQL is the database through `will/crystal-pg`.

Create an empty database and provide its URL:

```bash
shards install
export DATABASE_URL="postgres://postgres:secret@localhost:5432/altair_crud"
crystal run scripts/db.cr -- migrate
crystal run src/app.cr
```

Open <http://localhost:4200/products>. The UI supports:

- Create: `POST /products`
- Read: `GET /products` and `GET /products/:id`
- Update: `PUT /products/:id`
- Delete: `DELETE /products/:id`

The ORM uses PostgreSQL `$n` bind placeholders, an identity primary key and
`INSERT ... RETURNING` internally. The MVC structure and CRUD code match the
SQLite3 example.
