// Altair benchmark - Express reference server.
//
// Intentionally stock: a single node process on its default event loop, no
// cluster, default pg pool (max 10 connections). This is the untuned
// baseline the other runtimes are measured against.
const express = require("express");
const { Pool } = require("pg");

const app = express();
app.use(express.json());

const table = process.env.BENCH_TABLE || "items";
const pool = new Pool({ connectionString: process.env.DATABASE_URL || "" });

app.get("/health", (_req, res) => res.json({ ok: true }));

app.post("/items", async (req, res) => {
  const { name, price } = req.body || {};
  if (!name || typeof price !== "number") {
    return res.status(400).json({ error: "name and numeric price required" });
  }
  const result = await pool.query(
    `INSERT INTO ${table} (name, price) VALUES ($1, $2) RETURNING id`,
    [name, price]
  );
  res.status(201).json({ id: result.rows[0].id });
});

app.get("/items/:id", async (req, res) => {
  const result = await pool.query(
    `SELECT id, name, price FROM ${table} WHERE id = $1`,
    [req.params.id]
  );
  if (result.rowCount === 0) {
    return res.status(404).json({ error: "not found" });
  }
  res.json(result.rows[0]);
});

const port = Number(process.env.PORT || 4001);
app.listen(port, "0.0.0.0");