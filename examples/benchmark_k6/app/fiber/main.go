// Altair benchmark - Fiber (Go) server.
//
// Tuned: GOMAXPROCS tracks the deployment CPU budget, and the pgx pool is
// sized explicitly. The HTTP layer uses Fiber's default
// (single-process, preemptive goroutine scheduling).
package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"runtime"
	"strconv"
	"sync"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// itemBody is pooled to avoid a per-request allocation on the write path.
type itemBody struct {
	Name  string  `json:"name"`
	Price float64 `json:"price"`
}

var bodyPool = sync.Pool{
	New: func() any { return new(itemBody) },
}

func main() {
	// GOMAXPROCS defaults to NumCPU; BENCH_WORKERS (if set) overrides it so the
	// Go scheduler matches the other runtimes' worker budget.
	if w := env("BENCH_WORKERS", ""); w != "" {
		if n, err := strconv.Atoi(w); err == nil && n > 0 {
			runtime.GOMAXPROCS(n)
		}
	}

	// Build the query strings once per process. The table is fixed for the
	// process lifetime, so re-interpolating it on every request only added
	// allocation; the original code ran fmt.Sprintf on each request.
	table := env("BENCH_TABLE", "items")
	insertQuery := fmt.Sprintf("INSERT INTO %s (name, price) VALUES ($1, $2) RETURNING id", table)
	selectQuery := fmt.Sprintf("SELECT name, price FROM %s WHERE id = $1", table)

	// Configure the pool from the same DSN the other runtimes use, then size it
	// to match them and prepare once per physical connection so steady-state
	// traffic reuses named prepared statements instead of re-describing on
	// every QueryRow.
	config, err := pgxpool.ParseConfig(env("DATABASE_URL", "postgres://bench:bench@postgres:5432/bench"))
	if err != nil {
		log.Fatal(err)
	}
	maxConns, _ := strconv.Atoi(env("BENCH_POOL", "30"))
	config.MaxConns = int32(maxConns)
	config.MinConns = int32(maxConns)
	config.AfterConnect = func(ctx context.Context, conn *pgx.Conn) error {
		// Prepare the named statements once per physical connection so the
		// QueryRow/Query calls below reuse them (one round trip each) instead
		// of re-describing the statement on every request.
		if _, err := conn.Prepare(ctx, "insert_item", insertQuery); err != nil {
			return fmt.Errorf("prepare insert: %w", err)
		}
		if _, err := conn.Prepare(ctx, "select_item", selectQuery); err != nil {
			return fmt.Errorf("prepare select: %w", err)
		}
		return nil
	}
	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()

	port := env("PORT", "8080")

	app := fiber.New()

	app.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(map[string]bool{"ok": true})
	})

	ctx := context.Background()

	app.Post("/items", func(c *fiber.Ctx) error {
		bp := bodyPool.Get().(*itemBody)
		bp.Name = ""
		bp.Price = 0
		defer func() {
			bp.Name = ""
			bp.Price = 0
			bodyPool.Put(bp)
		}()
		if err := c.BodyParser(bp); err != nil || bp.Name == "" {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "name and numeric price required"})
		}
		var id int64
		if err := pool.QueryRow(ctx, "insert_item", bp.Name, bp.Price).Scan(&id); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
		}
		return c.Status(fiber.StatusCreated).JSON(fiber.Map{"id": id})
	})

	app.Get("/items/:id", func(c *fiber.Ctx) error {
		id, err := strconv.ParseInt(c.Params("id"), 10, 64)
		if err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "bad id"})
		}
		var name string
		var price float64
		if err := pool.QueryRow(ctx, "select_item", id).Scan(&name, &price); err != nil {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "not found"})
		}
		return c.JSON(fiber.Map{"id": id, "name": name, "price": price})
	})

	log.Printf("fiber listening on :%s (GOMAXPROCS=%d cpus=%d)", port, runtime.GOMAXPROCS(0), runtime.NumCPU())
	if err := app.Listen(":" + port); err != nil {
		log.Fatal(err)
	}
}
