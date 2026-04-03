package main

import (
	"flag"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"sync"
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

	client := es.NewClient(cfg.Elasticsearch.URL, cfg.Elasticsearch.IndexPrefix)

	// Time range: yesterday 00:00 → 23:59:59 (ICT)
	now := time.Now().In(vnTZ)
	y, m, d := now.Date()
	today := time.Date(y, m, d, 0, 0, 0, 0, vnTZ)
	from := today.AddDate(0, 0, -1)
	to := today.Add(-time.Second)

	slog.Info("report range", "from", from.Format("2006-01-02 15:04"), "to", to.Format("2006-01-02 15:04"))

	// Fetch connectors and work stats in parallel
	var (
		connectors []domain.ConnectorStatus
		workMap    map[string]domain.WorkStats
		errConn    error
		errWork    error
	)

	var wg sync.WaitGroup
	wg.Add(2)
	go func() { defer wg.Done(); connectors, errConn = client.GetConnectors() }()
	go func() { defer wg.Done(); workMap, errWork = client.GetWorkStats(from, to) }()
	wg.Wait()

	if errConn != nil {
		slog.Error("get connectors", "err", errConn)
		os.Exit(1)
	}
	if errWork != nil {
		slog.Error("get work stats", "err", errWork)
		os.Exit(1)
	}

	slog.Info("data fetched", "connectors", len(connectors), "work_buckets", len(workMap))

	message := formatSummary(from, to, connectors, workMap)

	if *stdoutOnly {
		fmt.Println(message)
		return
	}

	tg := telegram.NewSender(cfg.Telegram.BotToken, cfg.Telegram.ChatID)
	if err := tg.Send(message); err != nil {
		slog.Error("send telegram", "err", err)
		os.Exit(1)
	}
	slog.Info("summary report sent", "connectors", len(connectors))
}

func formatSummary(from, to time.Time, connectors []domain.ConnectorStatus, workMap map[string]domain.WorkStats) string {
	var sb strings.Builder

	dateStr := telegram.Esc(from.In(vnTZ).Format("02/01/2006"))
	rangeStr := fmt.Sprintf("%s 00:00 → %s 23:59",
		telegram.Esc(from.In(vnTZ).Format("02/01")),
		telegram.Esc(to.In(vnTZ).Format("02/01")),
	)

	fmt.Fprintf(&sb, "📊 *Event Summary* — %s\n", dateStr)
	fmt.Fprintf(&sb, "Khoảng: %s\n\n", rangeStr)

	// Table header
	sb.WriteString("```\n")
	fmt.Fprintf(&sb, "%-28s %5s %7s %6s\n", "Connector", "Runs", "Items", "Errors")
	sb.WriteString(strings.Repeat("─", 50))
	sb.WriteString("\n")

	for _, c := range connectors {
		stats := workMap[c.ID]
		fmt.Fprintf(&sb, "%-28s %5d %7d %6d\n",
			truncate(c.Name, 28),
			stats.WorksCount,
			stats.ItemsDone,
			stats.ErrorCount,
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
