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
	"connector-monitor/internal/connstatus"
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
	repo := connstatus.NewRepo(client)
	connectors, err := repo.GetAll()
	if err != nil {
		slog.Error("get connectors", "err", err)
		os.Exit(1)
	}
	slog.Info("connectors found", "count", len(connectors))

	// Step 2: Format and send
	slog.Info("step 2/2: format and send")
	var message string
	if cfg.Telegram.Format == "text" {
		message = formatStatusText(connectors)
	} else {
		message = formatStatusTable(connectors)
	}

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

func formatStatusTable(connectors []connstatus.Connector) string {
	now := time.Now().In(vnTZ)
	var sb strings.Builder

	activeCount, inactiveCount := countStatus(connectors)

	fmt.Fprintf(&sb, "🔔 *Connector Status*\n")
	fmt.Fprintf(&sb, "_%s_\n", telegram.Esc(now.Format("02/01/2006 15:04 +07")))
	fmt.Fprintf(&sb, "Total: %s  \\|  Active: %s  \\|  Inactive: %s\n\n",
		telegram.Esc(fmt.Sprintf("%d", len(connectors))),
		telegram.Esc(fmt.Sprintf("%d", activeCount)),
		telegram.Esc(fmt.Sprintf("%d", inactiveCount)),
	)

	nameW := 26
	sb.WriteString("```\n")
	fmt.Fprintf(&sb, " %-*s │ %-8s │ %s\n", nameW, "Connector", "Status", "Last Ping")
	fmt.Fprintf(&sb, "─%s─┼──────────┼────────────────\n", strings.Repeat("─", nameW))

	for _, c := range connectors {
		active := connstatus.IsActive(c)
		pingStr := c.UpdatedAt.In(vnTZ).Format("15:04")

		var statusIcon, statusLabel string
		if active {
			statusIcon = "●"
			statusLabel = "OK"
		} else {
			statusIcon = "○"
			mins := int(math.Floor(time.Since(c.UpdatedAt).Minutes()))
			statusLabel = "DOWN"
			pingStr += " (" + formatDuration(mins) + ")"
		}

		fmt.Fprintf(&sb, " %-*s │ %s %-6s │ %s\n",
			nameW,
			truncate(c.Name, nameW),
			statusIcon,
			statusLabel,
			pingStr,
		)
	}

	sb.WriteString("```")
	return sb.String()
}

func formatStatusText(connectors []connstatus.Connector) string {
	now := time.Now().In(vnTZ)
	var sb strings.Builder

	activeCount, inactiveCount := countStatus(connectors)

	fmt.Fprintf(&sb, "🔔 *Connector Status*\n")
	fmt.Fprintf(&sb, "_%s_\n", telegram.Esc(now.Format("02/01/2006 15:04 +07")))
	fmt.Fprintf(&sb, "Total: %s  \\|  Active: %s  \\|  Inactive: %s\n",
		telegram.Esc(fmt.Sprintf("%d", len(connectors))),
		telegram.Esc(fmt.Sprintf("%d", activeCount)),
		telegram.Esc(fmt.Sprintf("%d", inactiveCount)),
	)

	// Show DOWN connectors first if any
	if inactiveCount > 0 {
		sb.WriteString("\n⚠️ *DOWN:*\n")
		for _, c := range connectors {
			if !connstatus.IsActive(c) {
				mins := int(math.Floor(time.Since(c.UpdatedAt).Minutes()))
				fmt.Fprintf(&sb, "  ○ *%s*\n", telegram.Esc(c.Name))
				fmt.Fprintf(&sb, "     Ping: %s \\(%s trước\\)\n",
					telegram.Esc(c.UpdatedAt.In(vnTZ).Format("15:04")),
					telegram.Esc(formatDuration(mins)),
				)
			}
		}
	}

	sb.WriteString("\n✅ *Active:*\n")
	for _, c := range connectors {
		if connstatus.IsActive(c) {
			fmt.Fprintf(&sb, "  ● %s — %s\n",
				telegram.Esc(c.Name),
				telegram.Esc(c.UpdatedAt.In(vnTZ).Format("15:04")),
			)
		}
	}

	return sb.String()
}

func countStatus(connectors []connstatus.Connector) (active, inactive int) {
	for _, c := range connectors {
		if connstatus.IsActive(c) {
			active++
		}
	}
	inactive = len(connectors) - active
	return
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
