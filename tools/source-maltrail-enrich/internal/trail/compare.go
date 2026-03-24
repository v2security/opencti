package trail

import (
	"crypto/sha256"
	"encoding/hex"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Diff holds the result of comparing old vs new trail directories.
type Diff struct {
	Changed []string // Relative paths of changed .txt files.
	All     bool     // True when all files should be processed.
}

// Compare walks newDir and diffs each .txt file against oldDir using SHA256.
func Compare(oldDir, newDir string) (*Diff, error) {
	if oldDir == "" || !isDir(oldDir) {
		return &Diff{All: true}, nil
	}

	var changed []string
	err := filepath.WalkDir(newDir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || !strings.HasSuffix(strings.ToLower(d.Name()), ".txt") {
			return nil
		}

		rel, err := filepath.Rel(newDir, path)
		if err != nil {
			return err
		}

		oldPath := filepath.Join(oldDir, rel)
		if !isFile(oldPath) || filesDiffer(oldPath, path) {
			changed = append(changed, rel)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	sort.Strings(changed)
	return &Diff{Changed: changed}, nil
}

// filesDiffer compares two files by size first, then SHA256 hash.
func filesDiffer(a, b string) bool {
	infoA, errA := os.Stat(a)
	infoB, errB := os.Stat(b)
	if errA != nil || errB != nil {
		return true
	}
	if infoA.Size() != infoB.Size() {
		return true
	}

	hashA, errA := sha256sum(a)
	hashB, errB := sha256sum(b)
	return errA != nil || errB != nil || hashA != hashB
}

// sha256sum returns the hex-encoded SHA256 digest of a file.
func sha256sum(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
