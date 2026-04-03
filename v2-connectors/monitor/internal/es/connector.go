package es

import (
	"encoding/json"
	"fmt"

	"connector-monitor/internal/domain"
)

// GetConnectors fetches all connector documents from ES internal_objects index.
func (c *Client) GetConnectors() ([]domain.ConnectorStatus, error) {
	body := map[string]any{
		"size":    1000,
		"query":   map[string]any{"term": map[string]any{"entity_type.keyword": "connector"}},
		"_source": []string{"internal_id", "name", "built_in", "updated_at", "connector_info"},
	}

	res, err := c.Search("internal_objects", body)
	if err != nil {
		return nil, fmt.Errorf("get connectors: %w", err)
	}

	out := make([]domain.ConnectorStatus, 0, len(res.Hits.Hits))
	for _, hit := range res.Hits.Hits {
		cs, err := parseConnector(hit.Source)
		if err != nil {
			continue
		}
		out = append(out, cs)
	}
	return out, nil
}

type rawConnector struct {
	InternalID string         `json:"internal_id"`
	Name       string         `json:"name"`
	BuiltIn    bool           `json:"built_in"`
	UpdatedAt  string         `json:"updated_at"`
	Info       map[string]any `json:"connector_info"`
}

func parseConnector(src json.RawMessage) (domain.ConnectorStatus, error) {
	var raw rawConnector
	if err := json.Unmarshal(src, &raw); err != nil {
		return domain.ConnectorStatus{}, err
	}

	updatedAt, err := ParseTime(raw.UpdatedAt)
	if err != nil {
		return domain.ConnectorStatus{}, fmt.Errorf("parse updated_at: %w", err)
	}

	cs := domain.ConnectorStatus{
		ID:        raw.InternalID,
		Name:      raw.Name,
		BuiltIn:   raw.BuiltIn,
		UpdatedAt: updatedAt,
	}

	if raw.Info != nil {
		if v, _ := raw.Info["last_run_datetime"].(string); v != "" {
			if t, err := ParseTime(v); err == nil {
				cs.LastRun = &t
			}
		}
		if v, _ := raw.Info["next_run_datetime"].(string); v != "" {
			if t, err := ParseTime(v); err == nil {
				cs.NextRun = &t
			}
		}
	}
	return cs, nil
}
