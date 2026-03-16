// tools/ioc-mysql-migrate — MySQL schema migration for IOC tables.
//
// Reads .env from the same directory as the binary (and cwd).
//
// Env vars:
//
//	MYSQL_HOST (default 127.0.0.1), MYSQL_PORT (3306),
//	MYSQL_USER (required), MYSQL_PASSWORD (required), MYSQL_DATABASE (required)
//
// Usage:
//
//	go build -o migrate . && ./migrate
package main

import (
	"database/sql"
	"embed"
	"fmt"
	"log"
	"os"
	"sort"
	"strings"

	_ "github.com/go-sql-driver/mysql"
	"github.com/joho/godotenv"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func loadEnvFiles() {
	// Dev/test: export OPENCTI_ENV_FILE=/workspace/tunv_opencti/.env
	envFile := os.Getenv("OPENCTI_ENV_FILE")
	if envFile == "" {
		envFile = "/etc/saids/opencti/.env"
	}
	_ = godotenv.Load(envFile)
}

func required(key string) string {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		log.Fatalf("missing required env: %s", key)
	}
	return v
}

func main() {
	log.SetPrefix("[migrate] ")
	loadEnvFiles()

	host := env("MYSQL_HOST", "127.0.0.1")
	port := env("MYSQL_PORT", "3306")
	user := required("MYSQL_USER")
	password := required("MYSQL_PASSWORD")
	database := required("MYSQL_DATABASE")

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

	// Read embedded migrations
	files, err := migrationsFS.ReadDir("migrations")
	if err != nil {
		log.Fatalf("Cannot read embedded migrations: %v", err)
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

		content, err := migrationsFS.ReadFile("migrations/" + name)
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
