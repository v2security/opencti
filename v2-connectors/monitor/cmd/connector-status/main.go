package main

import (
	"flag"
	"fmt"
	"log/slog"
	"math"
	"os"
	"strings"
	"time"

	"connector-monitor/internal/config"
	"connector-monitor/internal/domain"
	"connector-monitor/internal/es"
	"connector-monitor/internal/telegram"
)

var vnTZ = func() *time.Location {
	loc, err := time.LoadLocation("Asia/Ho_Chi_Minh")
	if err != nil {
		return time.UTC
	}
	return loc
}()

func main() {
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})))

	stdoutOnly := flag.Bool("stdout-only", false, "print to terminal, do not send Telegram")
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		slog.Error("load config", "err", err)
		os.Exit(1)
	}

	if !*stdoutOnly && (cfg.Telegram.BotToken == "" || cfg.Telegram.ChatID == "") {
		slog.Error("telegram bot_token and chat_id are required")
		os.Exit(1)
	}

	// Step 1: Fetch connectors from ES
	slog.Info("step 1/2: fetch connectors")
	client := es.NewClient(cfg.Elasticsearch.URL, cfg.Elasticsearch.IndexPrefix)
	connectors, err := client.GetConnectors()
	if err != nil {
		slog.Error("get connectors", "err", err)
		os.Exit(1)
	}
	slog.Info("connectors found", "count", len(connectors))

	// Step 2: Format and send
	slog.Info("step 2/2: format and send")
	message := formatStatus(connectors)

	if *stdoutOnly {
		fmt.Println(message)
		return
	}

	tg := telegram.NewSender(cfg.Telegram.BotToken, cfg.Telegram.ChatID)
	if err := tg.Send(message); err != nil {
		slog.Error("send telegram", "err", err)
		os.Exit(1)
	}
	slog.Info("status report sent", "connectors", len(connectors))
}

func formatStatus(connectors []domain.ConnectorStatus) string {
	now := time.Now().In(vnTZ)
	var sb strings.Builder

	fmt.Fprintf(&sb, "🔔 *Connector Status* — %s\n\n", telegram.Esc(now.Format("02/01/2006 15:04 MST")))

	sb.WriteString("```\n")
	fmt.Fprintf(&sb, "%-28s %8s %s\n", "Connector", "Status", "Last Ping")
	sb.WriteString(strings.Repeat("─", 54))
	sb.WriteString("\n")

	for _, c := range connectors {
		active := domain.IsActive(c)

		status := "✓ active"
		pingStr := c.UpdatedAt.In(vnTZ).Format("15:04")
		if !active {
			mins := int(math.Floor(time.Since(c.UpdatedAt).Minutes()))
			status = "✗ inactive"
			pingStr += fmt.Sprintf(" (%s)", formatDuration(mins))
		}

		fmt.Fprintf(&sb, "%-28s %10s %s\n",
			truncate(c.Name, 28),
			status,
			pingStr,
		)
	}

	sb.WriteString("```\n")
	return sb.String()
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-1] + "…"
}

func formatDuration(mins int) string {
	if mins < 60 {
		return fmt.Sprintf("%d phút", mins)
	}
	h := mins / 60
	m := mins % 60
	if m == 0 {
		return fmt.Sprintf("%d giờ", h)
	}
	return fmt.Sprintf("%d giờ %d phút", h, m)
}
