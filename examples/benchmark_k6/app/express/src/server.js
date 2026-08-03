// Altair benchmark - Express reference server.
//
// Tuned to match the other runtimes: worker count from BENCH_WORKERS and
// pool size from BENCH_POOL, so all three frameworks run on the same
// threads and connection count.
const cluster = require("cluster");
const os = require("os");
const express = require("express");
const { Pool } = require("pg");

const workers = Number(process.env.BENCH_WORKERS || 1);

if (cluster.isPrimary && workers > 1) {
  for (let i = 0; i < workers; i++) cluster.fork();
  cluster.on("exit", (worker) => cluster.fork());
} else {
  const app = express();
  app.use(express.json());

  const table = process.env.BENCH_TABLE || "items";
  // The pool is split across cluster workers so the process-wide connection
  // count equals BENCH_POOL (each worker holds BENCH_POOL / workers).
  const poolTotal = Number(process.env.BENCH_POOL || 10);
  const poolPerWorker = Math.max(1, Math.floor(poolTotal / workers));
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL || "",
    max: poolPerWorker,
  });

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
}