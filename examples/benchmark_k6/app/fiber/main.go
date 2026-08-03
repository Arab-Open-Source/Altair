// Altair benchmark - Fiber (Go) server.
//
// Tuned: GOMAXPROCS is pinned to the number of CPUs the container is
// granted, and the pgx pool is sized explicitly. The HTTP layer uses
// Fiber's default (single-process, preemptive goroutine scheduling).
package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"runtime"
	"strconv"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5/pgxpool"
)

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	// Tune: bind the Go scheduler to the CPU quota granted to the process.
	runtime.GOMAXPROCS(runtime.NumCPU())

	pool, err := pgxpool.New(context.Background(), env("DATABASE_URL", "postgres://bench:bench@postgres:5432/bench"))
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()
	// Tune: pool sized for sustained load, eager minimum connections.
	pool.Config().MaxConns = 30
	pool.Config().MinConns = 5

	table := env("BENCH_TABLE", "items")
	port := env("PORT", "8080")

	app := fiber.New()

	app.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(map[string]bool{"ok": true})
	})

	app.Post("/items", func(c *fiber.Ctx) error {
		var body struct {
			Name  string  `json:"name"`
			Price float64 `json:"price"`
		}
		if err := c.BodyParser(&body); err != nil || body.Name == "" {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "name and numeric price required"})
		}
		var id int64
		query := fmt.Sprintf("INSERT INTO %s (name, price) VALUES ($1, $2) RETURNING id", table)
		if err := pool.QueryRow(context.Background(), query, body.Name, body.Price).Scan(&id); err != nil {
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
		query := fmt.Sprintf("SELECT name, price FROM %s WHERE id = $1", table)
		if err := pool.QueryRow(context.Background(), query, id).Scan(&name, &price); err != nil {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "not found"})
		}
		return c.JSON(fiber.Map{"id": id, "name": name, "price": price})
	})

	log.Printf("fiber listening on :%s (GOMAXPROCS=%d cpus=%d)", port, runtime.GOMAXPROCS(0), runtime.NumCPU())
	if err := app.Listen(":" + port); err != nil {
		log.Fatal(err)
	}
}