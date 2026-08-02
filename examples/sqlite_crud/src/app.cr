# Boots the SQLite3 MVC CRUD web application.
require "altair"
require "../db/schema"
require "./application"
require "./models/product"
require "./controllers/products_controller"
require "./routes"

SQLiteCrud.run!
