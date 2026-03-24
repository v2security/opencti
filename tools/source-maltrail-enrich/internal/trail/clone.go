package trail

import (
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
)

const (
	dirClone = "maltrail-repo"
	dirFirst = "maltrail-first"
	dirNew   = "maltrail-new"
	dirOld   = "maltrail-old"
)

// CloneResult describes the outcome of a clone + rotate operation.
type CloneResult struct {
	NewDir   string // Path to the freshly cloned trail data.
	OldDir   string // Path to the previous data (empty on first run).
	FirstRun bool   // True when there is no previous data.
}

// CloneAndRotate performs directory rotation then a shallow git clone:
//  1. Delete old, rename new → old
//  2. git clone --depth 1
//  3. Copy malware/malicious/suspicious into the new directory
//  4. Remove the clone
func CloneAndRotate(gitBin, repoURL, dataDir string) (*CloneResult, error) {
	cloneDir := filepath.Join(dataDir, dirClone)
	firstDir := filepath.Join(dataDir, dirFirst)
	newDir := filepath.Join(dataDir, dirNew)
	oldDir := filepath.Join(dataDir, dirOld)

	targetDir, firstRun, err := rotate(firstDir, newDir, oldDir)
	if err != nil {
		return nil, fmt.Errorf("rotate: %w", err)
	}

	if err := os.MkdirAll(targetDir, 0755); err != nil {
		return nil, fmt.Errorf("mkdir %s: %w", targetDir, err)
	}

	// Remove stale clone if it exists
	_ = os.RemoveAll(cloneDir)

	slog.Info("cloning", "repo", repoURL)
	cmd := exec.Command(gitBin, "clone", "--depth", "1", repoURL, cloneDir)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("git clone: %w", err)
	}

	for _, folder := range Labels {
		src := filepath.Join(cloneDir, "trails", "static", folder)
		dst := filepath.Join(targetDir, folder)
		if !isDir(src) {
			slog.Warn("source folder missing", "path", src)
			continue
		}
		if err := copyDir(src, dst); err != nil {
			return nil, fmt.Errorf("copy %s: %w", folder, err)
		}
	}

	_ = os.RemoveAll(cloneDir)

	res := &CloneResult{NewDir: targetDir, FirstRun: firstRun}
	if !firstRun {
		res.OldDir = oldDir
	}
	return res, nil
}

// rotate handles the 3-state directory rotation logic.
func rotate(firstDir, newDir, oldDir string) (targetDir string, firstRun bool, err error) {
	hasOld := isDir(oldDir)
	hasNew := isDir(newDir)
	hasFirst := isDir(firstDir)

	switch {
	case !hasOld && !hasNew && !hasFirst:
		return firstDir, true, nil

	case hasFirst && !hasOld && !hasNew:
		if err := os.Rename(firstDir, oldDir); err != nil {
			return "", false, fmt.Errorf("rename first→old: %w", err)
		}
		return newDir, false, nil

	default:
		if hasOld {
			if err := os.RemoveAll(oldDir); err != nil {
				return "", false, fmt.Errorf("remove old: %w", err)
			}
		}
		if hasNew {
			if err := os.Rename(newDir, oldDir); err != nil {
				return "", false, fmt.Errorf("rename new→old: %w", err)
			}
		}
		return newDir, false, nil
	}
}

// copyDir recursively copies src to dst.
func copyDir(src, dst string) error {
	return filepath.WalkDir(src, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(src, path)
		target := filepath.Join(dst, rel)

		if d.IsDir() {
			return os.MkdirAll(target, 0755)
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(target, data, 0644)
	})
}
