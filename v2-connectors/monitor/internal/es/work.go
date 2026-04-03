package es

import (
	"encoding/json"
	"fmt"
	"time"

	"connector-monitor/internal/domain"
)

// GetWorkStats fetches aggregated work statistics grouped by connector_id
// for works received within [from, to].
func (c *Client) GetWorkStats(from, to time.Time) (map[string]domain.WorkStats, error) {
	body := map[string]any{
		"size": 0,
		"query": map[string]any{
			"bool": map[string]any{
				"must": []any{
					map[string]any{"term": map[string]any{"entity_type.keyword": "work"}},
					map[string]any{"range": map[string]any{"received_time": map[string]any{
						"gte": from.UTC().Format(time.RFC3339),
						"lte": to.UTC().Format(time.RFC3339),
					}}},
				},
			},
		},
		"aggs": map[string]any{
			"by_connector": map[string]any{
				"terms": map[string]any{
					"field": "connector_id.keyword",
					"size":  1000,
				},
				"aggs": map[string]any{
					"total_items": map[string]any{"sum": map[string]any{"field": "completed_number"}},
					"errors":      map[string]any{"filter": map[string]any{"exists": map[string]any{"field": "errors.message"}}},
				},
			},
		},
	}

	res, err := c.Search("history", body)
	if err != nil {
		return nil, fmt.Errorf("get work stats: %w", err)
	}

	var aggs struct {
		ByConnector struct {
			Buckets []struct {
				Key        string `json:"key"`
				DocCount   int    `json:"doc_count"`
				TotalItems struct {
					Value float64 `json:"value"`
				} `json:"total_items"`
				Errors struct {
					DocCount int `json:"doc_count"`
				} `json:"errors"`
			} `json:"buckets"`
		} `json:"by_connector"`
	}
	if err := json.Unmarshal(res.Aggregations, &aggs); err != nil {
		return nil, fmt.Errorf("parse work aggs: %w", err)
	}

	out := make(map[string]domain.WorkStats, len(aggs.ByConnector.Buckets))
	for _, b := range aggs.ByConnector.Buckets {
		out[b.Key] = domain.WorkStats{
			ConnectorID: b.Key,
			WorksCount:  b.DocCount,
			ItemsDone:   int(b.TotalItems.Value),
			ErrorCount:  b.Errors.DocCount,
		}
	}
	return out, nil
}
