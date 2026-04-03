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
	"connector-monitor/internal/connstats"
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

	client := es.NewClient(cfg.Elasticsearch.URL, cfg.Elasticsearch.IndexPrefix)
	statusRepo := connstatus.NewRepo(client)
	statsRepo := connstats.NewRepo(client)

	// Time range: yesterday 00:00 → 23:59:59 (ICT)
	now := time.Now().In(vnTZ)
	y, m, d := now.Date()
	today := time.Date(y, m, d, 0, 0, 0, 0, vnTZ)
	from := today.AddDate(0, 0, -1)
	to := today.Add(-time.Second)

	slog.Info("report range", "from", from.Format("2006-01-02 15:04"), "to", to.Format("2006-01-02 15:04"))

	// Fetch connectors and work stats in parallel
	var (
		connectors []connstatus.Connector
		workMap    map[string]connstats.WorkStats
		errConn    error
		errWork    error
	)

	var wg sync.WaitGroup
	wg.Add(2)
	go func() { defer wg.Done(); connectors, errConn = statusRepo.GetAll() }()
	go func() { defer wg.Done(); workMap, errWork = statsRepo.GetByRange(from, to) }()
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

	var message string
	if cfg.Telegram.Format == "text" {
		message = formatSummaryText(from, to, connectors, workMap)
	} else {
		message = formatSummaryTable(from, to, connectors, workMap)
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
	slog.Info("summary report sent", "connectors", len(connectors))
}

func summaryHeader(sb *strings.Builder, from, to time.Time, totalRuns, totalItems, totalErrors int) {
	dateStr := telegram.Esc(from.In(vnTZ).Format("02/01/2006"))
	rangeStr := fmt.Sprintf("%s 00:00 → %s 23:59",
		telegram.Esc(from.In(vnTZ).Format("02/01")),
		telegram.Esc(to.In(vnTZ).Format("02/01")),
	)

	fmt.Fprintf(sb, "📊 *Event Summary*\n")
	fmt.Fprintf(sb, "_%s  \\(%s\\)_\n\n", dateStr, rangeStr)
	fmt.Fprintf(sb, "• *Runs* — Số lần connector chạy \\(work cycle\\)\n")
	fmt.Fprintf(sb, "• *Items* — Số đối tượng STIX đã xử lý\n")
	fmt.Fprintf(sb, "• *Errors* — Số lỗi phát sinh khi import\n\n")
	fmt.Fprintf(sb, "Tổng: %s runs  \\|  %s items  \\|  %s errors\n",
		telegram.Esc(formatNumber(totalRuns)),
		telegram.Esc(formatNumber(totalItems)),
		telegram.Esc(formatNumber(totalErrors)),
	)
}

func calcTotals(connectors []connstatus.Connector, workMap map[string]connstats.WorkStats) (int, int, int) {
	var runs, items, errors int
	for _, c := range connectors {
		s := workMap[c.ID]
		runs += s.WorksCount
		items += s.ItemsDone
		errors += s.ErrorCount
	}
	return runs, items, errors
}

func formatSummaryTable(from, to time.Time, connectors []connstatus.Connector, workMap map[string]connstats.WorkStats) string {
	var sb strings.Builder

	totalRuns, totalItems, totalErrors := calcTotals(connectors, workMap)
	summaryHeader(&sb, from, to, totalRuns, totalItems, totalErrors)
	sb.WriteString("\n")

	nameW := 26
	sb.WriteString("```\n")
	fmt.Fprintf(&sb, " %-*s │ %5s │ %7s │ %6s\n", nameW, "Connector", "Runs", "Items", "Errors")
	fmt.Fprintf(&sb, "─%s─┼───────┼─────────┼────────\n", strings.Repeat("─", nameW))

	for _, c := range connectors {
		s := workMap[c.ID]
		errMark := " "
		if s.ErrorCount > 0 {
			errMark = "!"
		}
		fmt.Fprintf(&sb, " %-*s │ %5d │ %7s │ %s%5s\n",
			nameW,
			truncate(c.Name, nameW),
			s.WorksCount,
			formatNumber(s.ItemsDone),
			errMark,
			formatNumber(s.ErrorCount),
		)
	}

	fmt.Fprintf(&sb, "─%s─┼───────┼─────────┼────────\n", strings.Repeat("─", nameW))
	fmt.Fprintf(&sb, " %-*s │ %5d │ %7s │  %5s\n",
		nameW, "TOTAL",
		totalRuns,
		formatNumber(totalItems),
		formatNumber(totalErrors),
	)

	sb.WriteString("```")
	return sb.String()
}

func formatSummaryText(from, to time.Time, connectors []connstatus.Connector, workMap map[string]connstats.WorkStats) string {
	var sb strings.Builder

	totalRuns, totalItems, totalErrors := calcTotals(connectors, workMap)
	summaryHeader(&sb, from, to, totalRuns, totalItems, totalErrors)

	// Active connectors (has runs)
	sb.WriteString("\n📦 *Hoạt động:*\n")
	hasActivity := false
	for _, c := range connectors {
		s := workMap[c.ID]
		if s.WorksCount > 0 {
			hasActivity = true
			detail := fmt.Sprintf("%s runs · %s items",
				formatNumber(s.WorksCount),
				formatNumber(s.ItemsDone),
			)
			if s.ErrorCount > 0 {
				detail += fmt.Sprintf(" · %s errors", formatNumber(s.ErrorCount))
			}
			fmt.Fprintf(&sb, "  ✅ %s\n", telegram.Esc(c.Name))
			fmt.Fprintf(&sb, "     %s\n", telegram.Esc(detail))
		}
	}
	if !hasActivity {
		sb.WriteString("  Không có\n")
	}

	// Idle connectors (no runs at all)
	sb.WriteString("\n💤 *Không chạy:*\n")
	idleNames := []string{}
	for _, c := range connectors {
		if workMap[c.ID].WorksCount == 0 {
			idleNames = append(idleNames, c.Name)
		}
	}
	if len(idleNames) > 0 {
		sb.WriteString("  ")
		sb.WriteString(telegram.Esc(strings.Join(idleNames, ", ")))
		sb.WriteString("\n")
	}

	return sb.String()
}

// formatNumber adds thousand separators (e.g. 163392 → "163,392").
func formatNumber(n int) string {
	if n < 0 {
		return "-" + formatNumber(-n)
	}
	s := fmt.Sprintf("%d", n)
	if len(s) <= 3 {
		return s
	}

	var result strings.Builder
	remainder := len(s) % 3
	if remainder > 0 {
		result.WriteString(s[:remainder])
	}
	for i := remainder; i < len(s); i += 3 {
		if result.Len() > 0 {
			result.WriteByte(',')
		}
		result.WriteString(s[i : i+3])
	}
	return result.String()
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-1] + "…"
}
