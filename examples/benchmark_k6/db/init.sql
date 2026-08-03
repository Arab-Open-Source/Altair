-- Altair benchmark - database bootstrap.
--
-- One database ("bench") holds one table per framework so the write and
-- read loads never step on each other. The Altair table happens to be
-- created here too; the example does not run the Record migration runner
-- (the benchmark cares about request throughput, not schema plumbing).
CREATE TABLE IF NOT EXISTS items_express (
  id    SERIAL PRIMARY KEY,
  name  TEXT NOT NULL,
  price DOUBLE PRECISION NOT NULL
);

CREATE TABLE IF NOT EXISTS items_fiber (
  id    SERIAL PRIMARY KEY,
  name  TEXT NOT NULL,
  price DOUBLE PRECISION NOT NULL
);

CREATE TABLE IF NOT EXISTS items_altair (
  id    SERIAL PRIMARY KEY,
  name  TEXT NOT NULL,
  price DOUBLE PRECISION NOT NULL
);