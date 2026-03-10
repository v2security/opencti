// tools/ioc-mysql-migration — MySQL schema migration for IOC tables.
//
// Env vars:
//   MYSQL_HOST (default 127.0.0.1), MYSQL_PORT (3306),
//   MYSQL_USER (root), MYSQL_PASSWORD (required), MYSQL_DATABASE (ids)
//
// Usage:
//   export $(grep -v '^#' ../../.env | xargs) && go run main.go
package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"

	_ "github.com/go-sql-driver/mysql"
)

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	log.SetPrefix("[migrate] ")

	password := env("MYSQL_PASSWORD", env("MYSQL_ROOT_PASSWORD", ""))
	if password == "" {
		log.Fatal("MYSQL_PASSWORD env var is required")
	}

	host := env("MYSQL_HOST", "127.0.0.1")
	port := env("MYSQL_PORT", "3306")
	user := env("MYSQL_USER", "root")
	database := env("MYSQL_DATABASE", "ids")

	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?charset=utf8mb4&parseTime=true&multiStatements=true",
		user, password, host, port, database)

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		log.Fatalf("Connect failed: %v", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatalf("MySQL not reachable: %v", err)
	}
	log.Printf("Connected to %s@%s:%s/%s", user, host, port, database)

	// Migration tracking table
	db.Exec(`CREATE TABLE IF NOT EXISTS _migrations (
		id INT NOT NULL AUTO_INCREMENT, filename VARCHAR(255) NOT NULL UNIQUE,
		applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (id)
	) ENGINE=InnoDB`)

	// Read migrations/ folder (same level as main.go)
	files, err := os.ReadDir("migrations")
	if err != nil {
		log.Fatalf("Cannot read migrations/: %v", err)
	}

	var sqlFiles []string
	for _, f := range files {
		if !f.IsDir() && strings.HasSuffix(f.Name(), ".sql") {
			sqlFiles = append(sqlFiles, f.Name())
		}
	}
	sort.Strings(sqlFiles)

	applied, skipped := 0, 0
	for _, name := range sqlFiles {
		var count int
		db.QueryRow("SELECT COUNT(*) FROM _migrations WHERE filename=?", name).Scan(&count)
		if count > 0 {
			log.Printf("  ⏭  %s (skip)", name)
			skipped++
			continue
		}

		content, err := os.ReadFile(filepath.Join("migrations", name))
		if err != nil {
			log.Fatalf("Read %s: %v", name, err)
		}

		log.Printf("  ▶  %s ...", name)
		if _, err := db.Exec(string(content)); err != nil {
			log.Fatalf("  ✗  %s: %v", name, err)
		}
		db.Exec("INSERT INTO _migrations (filename) VALUES (?)", name)
		log.Printf("  ✓  %s", name)
		applied++
	}

	log.Printf("Done — %d applied, %d skipped", applied, skipped)
}
