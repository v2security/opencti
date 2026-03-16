package main

import (
	"log/slog"
	"os"
	"time"

	"source-maltrail-sync/internal/config"
	"source-maltrail-sync/internal/store"
	"source-maltrail-sync/internal/trail"
)

func main() {
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})))
	start := time.Now()

	cfg, err := config.Load()
	if err != nil {
		slog.Error("load config", "err", err)
		os.Exit(1)
	}

	// Step 1: Clone + rotate directories
	slog.Info("step 1/4: clone and rotate")
	result, err := trail.CloneAndRotate(cfg.GitBin, cfg.RepoURL, cfg.DataDir)
	if err != nil {
		slog.Error("clone", "err", err)
		os.Exit(1)
	}
	slog.Info("clone done", "new_dir", result.NewDir, "first_run", result.FirstRun)

	// Step 2: Compare old vs new
	slog.Info("step 2/4: compare old vs new")
	diff, err := trail.Compare(result.OldDir, result.NewDir)
	if err != nil {
		slog.Error("compare", "err", err)
		os.Exit(1)
	}
	if !diff.All && len(diff.Changed) == 0 {
		slog.Info("no changes detected, nothing to update", "elapsed", time.Since(start))
		return
	}
	if diff.All {
		slog.Info("processing all files (first run)")
	} else {
		slog.Info("files changed", "count", len(diff.Changed))
	}

	// Step 3: Parse IOCs from changed trail files
	slog.Info("step 3/4: parse IOCs")
	iocMap, err := trail.Parse(result.NewDir, diff)
	if err != nil {
		slog.Error("parse", "err", err)
		os.Exit(1)
	}
	grouped := trail.GroupByLabel(iocMap)
	for _, label := range trail.Labels {
		slog.Info("parsed", "label", label, "count", len(grouped[label]))
	}
	if len(iocMap) == 0 {
		slog.Info("no IOCs to update", "elapsed", time.Since(start))
		return
	}

	// Step 4: Update MySQL
	slog.Info("step 4/4: update MySQL")
	db, err := store.Open(cfg.MySQL)
	if err != nil {
		slog.Error("db open", "err", err)
		os.Exit(1)
	}
	defer db.Close()

	total, err := store.UpdateLabels(db, grouped)
	if err != nil {
		slog.Error("db update", "err", err)
		os.Exit(1)
	}

	slog.Info("done", "rows_updated", total, "elapsed", time.Since(start))
}
