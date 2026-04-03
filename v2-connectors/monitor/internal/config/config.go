package config

import (
	"fmt"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

// Elasticsearch holds ES connection parameters.
type Elasticsearch struct {
	URL         string `yaml:"url"`
	IndexPrefix string `yaml:"index_prefix"`
}

// Telegram holds Telegram Bot API parameters.
type Telegram struct {
	BotToken string `yaml:"bot_token"`
	ChatID   string `yaml:"chat_id"`
	Format   string `yaml:"format"` // "table" (default) or "text"
}

// Config holds all runtime configuration.
type Config struct {
	Elasticsearch Elasticsearch `yaml:"elasticsearch"`
	Telegram      Telegram      `yaml:"telegram"`
}

// Load reads config.yml then overrides with environment variables.
func Load() (*Config, error) {
	cfg := &Config{
		Elasticsearch: Elasticsearch{IndexPrefix: "opencti"},
	}

	if data, err := os.ReadFile("config.yml"); err == nil {
		if err := yaml.Unmarshal(data, cfg); err != nil {
			return nil, fmt.Errorf("parse config.yml: %w", err)
		}
	}

	overrides := map[string]*string{
		"ES_URL":             &cfg.Elasticsearch.URL,
		"ES_INDEX_PREFIX":    &cfg.Elasticsearch.IndexPrefix,
		"TELEGRAM_BOT_TOKEN": &cfg.Telegram.BotToken,
		"TELEGRAM_CHAT_ID":   &cfg.Telegram.ChatID,
		"TELEGRAM_FORMAT":    &cfg.Telegram.Format,
	}
	for key, ptr := range overrides {
		if v := strings.TrimSpace(os.Getenv(key)); v != "" {
			*ptr = v
		}
	}

	if cfg.Elasticsearch.URL == "" {
		return nil, fmt.Errorf("missing required: elasticsearch.url (config.yml or ES_URL)")
	}

	// Default format
	if cfg.Telegram.Format == "" {
		cfg.Telegram.Format = "table"
	}

	return cfg, nil
}
