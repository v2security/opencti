package config

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/joho/godotenv"
)

// MySQL holds database connection parameters.
type MySQL struct {
	Host     string
	Port     string
	User     string
	Password string
	Database string
}

// Config holds all runtime configuration.
type Config struct {
	MySQL   MySQL
	RepoURL string
	DataDir string
	GitBin  string
}

// Load reads .env files and validates required environment variables.
func Load() (*Config, error) {
	loadEnvFiles()

	mysql, err := loadMySQL()
	if err != nil {
		return nil, err
	}

	gitBin, err := findGit()
	if err != nil {
		return nil, err
	}

	return &Config{
		MySQL:   mysql,
		RepoURL: env("MALTRAIL_REPO", "https://github.com/stamparm/maltrail.git"),
		DataDir: env("TOOL_DATA_DIR", "../data"),
		GitBin:  gitBin,
	}, nil
}

func loadEnvFiles() {
	// Dev/test: export OPENCTI_ENV_FILE=/workspace/tunv_opencti/.env
	envFile := os.Getenv("OPENCTI_ENV_FILE")
	if envFile == "" {
		envFile = "/etc/saids/opencti/.env"
	}
	_ = godotenv.Load(envFile)
}

func loadMySQL() (MySQL, error) {
	user, err := required("MYSQL_USER")
	if err != nil {
		return MySQL{}, err
	}
	pass, err := required("MYSQL_PASSWORD")
	if err != nil {
		return MySQL{}, err
	}
	dbName, err := required("MYSQL_DATABASE")
	if err != nil {
		return MySQL{}, err
	}
	return MySQL{
		Host:     env("MYSQL_HOST", "127.0.0.1"),
		Port:     env("MYSQL_PORT", "3306"),
		User:     user,
		Password: pass,
		Database: dbName,
	}, nil
}

func findGit() (string, error) {
	if v := os.Getenv("GIT_BIN"); v != "" {
		return v, nil
	}
	path, err := exec.LookPath("git")
	if err != nil {
		return "", fmt.Errorf("git not found in PATH: %w", err)
	}
	return path, nil
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func required(key string) (string, error) {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return "", fmt.Errorf("missing required env: %s", key)
	}
	return v, nil
}
