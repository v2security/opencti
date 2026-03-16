package store

import (
	"database/sql"
	"fmt"
	"log/slog"
	"strings"

	_ "github.com/go-sql-driver/mysql"

	"source-maltrail/internal/config"
)

const batchSize = 500

// Open creates and validates a MySQL connection from the given config.
func Open(cfg config.MySQL) (*sql.DB, error) {
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?charset=utf8mb4&parseTime=true",
		cfg.User, cfg.Password, cfg.Host, cfg.Port, cfg.Database,
	)
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("mysql open: %w", err)
	}
	if err := db.Ping(); err != nil {
		db.Close()
		return nil, fmt.Errorf("mysql ping: %w", err)
	}
	return db, nil
}

// UpdateLabels batch-updates ids_blacklist for each label group.
// Only rows with source='suspicious' are updated. Returns total affected rows.
func UpdateLabels(db *sql.DB, byLabel map[string][]string) (int64, error) {
	var total int64
	for label, values := range byLabel {
		n, err := updateLabel(db, label, values)
		if err != nil {
			return total, err
		}
		if n > 0 {
			slog.Info("label updated", "label", label, "rows", n)
		}
		total += n
	}
	return total, nil
}

func updateLabel(db *sql.DB, label string, values []string) (int64, error) {
	if len(values) == 0 {
		return 0, nil
	}

	var total int64
	for i := 0; i < len(values); i += batchSize {
		end := min(i+batchSize, len(values))
		chunk := values[i:end]

		ph := strings.Repeat("?,", len(chunk))
		ph = ph[:len(ph)-1]

		query := fmt.Sprintf(
			"UPDATE ids_blacklist SET source = ? WHERE value IN (%s) AND source = 'suspicious'",
			ph,
		)

		args := make([]any, 0, 1+len(chunk))
		args = append(args, label)
		for _, v := range chunk {
			args = append(args, v)
		}

		res, err := db.Exec(query, args...)
		if err != nil {
			return total, fmt.Errorf("update %s batch %d: %w", label, i/batchSize, err)
		}
		n, _ := res.RowsAffected()
		total += n
	}
	return total, nil
}
