package trail

import (
	"bufio"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
)

// Labels are the trail category directories used throughout the package.
var Labels = []string{"malware", "malicious", "suspicious"}

// Parse reads trail .txt files and returns a deduplicated map of IOC value → label.
// If diff.All is true, all files under baseDir are read; otherwise only diff.Changed files.
func Parse(baseDir string, diff *Diff) (map[string]string, error) {
	if diff.All {
		return parseAll(baseDir)
	}
	return parseChanged(baseDir, diff.Changed)
}

// GroupByLabel inverts an IOC map into label → []value for batch SQL.
func GroupByLabel(iocMap map[string]string) map[string][]string {
	result := make(map[string][]string, len(Labels))
	for _, l := range Labels {
		result[l] = nil
	}
	for value, label := range iocMap {
		result[label] = append(result[label], value)
	}
	return result
}

func parseAll(baseDir string) (map[string]string, error) {
	iocMap := make(map[string]string)
	for _, label := range Labels {
		dir := filepath.Join(baseDir, label)
		if !isDir(dir) {
			continue
		}
		err := filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if d.IsDir() || !isTxtFile(d.Name()) {
				return nil
			}
			return scanFile(path, label, iocMap)
		})
		if err != nil {
			return nil, fmt.Errorf("walk %s: %w", label, err)
		}
	}
	return iocMap, nil
}

func parseChanged(baseDir string, files []string) (map[string]string, error) {
	iocMap := make(map[string]string)
	seen := make(map[string]struct{}, len(files))

	for _, rel := range files {
		clean := filepath.Clean(strings.TrimSpace(rel))
		if clean == "" || clean == "." {
			continue
		}
		if _, dup := seen[clean]; dup {
			continue
		}
		seen[clean] = struct{}{}

		label := labelFromPath(clean)
		if label == "" {
			continue
		}
		path := filepath.Join(baseDir, clean)
		if err := scanFile(path, label, iocMap); err != nil {
			slog.Warn("skip file", "path", rel, "err", err)
		}
	}
	return iocMap, nil
}

// scanFile reads one .txt file and adds cleaned IOC values to the map.
func scanFile(path, label string, out map[string]string) error {
	f, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		if v := cleanLine(sc.Text()); v != "" {
			out[v] = label
		}
	}
	return sc.Err()
}

// cleanLine extracts an IOC value (IP or domain) from a raw text line.
// Strips comments (#, //), ports (:NNN), CIDR (/NN), and lines with brackets.
func cleanLine(line string) string {
	line = strings.TrimSpace(line)
	if line == "" || line[0] == '#' || strings.HasPrefix(line, "//") {
		return ""
	}
	if strings.ContainsAny(line, "[]\\") {
		return ""
	}
	if i := strings.Index(line, "/"); i != -1 {
		line = line[:i]
	}
	if i := strings.Index(line, ":"); i != -1 {
		line = line[:i]
	}
	return strings.TrimSpace(line)
}

// labelFromPath extracts the label from a relative path like "malware/emotet.txt".
func labelFromPath(rel string) string {
	parts := strings.SplitN(filepath.ToSlash(rel), "/", 2)
	if len(parts) < 2 {
		return ""
	}
	switch parts[0] {
	case "malware", "malicious", "suspicious":
		return parts[0]
	}
	return ""
}

func isTxtFile(name string) bool {
	return strings.HasSuffix(strings.ToLower(name), ".txt")
}
