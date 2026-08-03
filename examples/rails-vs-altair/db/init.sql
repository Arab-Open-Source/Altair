-- One table per framework. Mirrors the schema the Rails scaffold would
-- generate: id + name + price, priced as DOUBLE PRECISION to match the
-- Altair Record model's :float column typing.

CREATE TABLE IF NOT EXISTS items_altair (
  id    SERIAL PRIMARY KEY,
  name  TEXT NOT NULL,
  price DOUBLE PRECISION NOT NULL
);

CREATE TABLE IF NOT EXISTS items_rails (
  id    SERIAL PRIMARY KEY,
  name  TEXT NOT NULL,
  price DOUBLE PRECISION NOT NULL
);