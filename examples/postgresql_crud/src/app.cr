# Boots the PostgreSQL MVC CRUD web application.
require "altair"
require "altair/record/adapters/postgresql"
require "../db/schema"
require "./models/product"
require "./controllers/products_controller"
require "./application"
require "./routes"

PostgreSQLCrud.run!
