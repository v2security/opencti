package es

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Client is a lightweight Elasticsearch HTTP client.
type Client struct {
	url    string
	prefix string
	http   *http.Client
}

// NewClient creates an ES client with a 15-second timeout.
func NewClient(url, prefix string) *Client {
	return &Client{
		url:    strings.TrimRight(url, "/"),
		prefix: prefix,
		http:   &http.Client{Timeout: 15 * time.Second},
	}
}

// SearchResult is the top-level response from ES _search.
type SearchResult struct {
	Hits struct {
		Total struct {
			Value int `json:"value"`
		} `json:"total"`
		Hits []Hit `json:"hits"`
	} `json:"hits"`
	Aggregations json.RawMessage `json:"aggregations"`
}

// Hit is a single document from ES _search results.
type Hit struct {
	Source json.RawMessage `json:"_source"`
}

// Search posts a query to <prefix>_<index>-*/_search.
func (c *Client) Search(index string, body map[string]any) (*SearchResult, error) {
	data, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("marshal query: %w", err)
	}

	url := fmt.Sprintf("%s/%s_%s-*/_search", c.url, c.prefix, index)
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("es request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		raw, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("es %d: %s", resp.StatusCode, string(raw))
	}

	var result SearchResult
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}
	return &result, nil
}

// ParseTime supports both RFC3339 and RFC3339Nano from OpenCTI timestamps.
func ParseTime(s string) (time.Time, error) {
	for _, layout := range []string{time.RFC3339Nano, time.RFC3339} {
		if t, err := time.Parse(layout, s); err == nil {
			return t, nil
		}
	}
	return time.Time{}, fmt.Errorf("unsupported time format: %q", s)
}
