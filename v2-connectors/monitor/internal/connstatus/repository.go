package connstatus

import (
	"encoding/json"
	"fmt"

	"connector-monitor/internal/es"
)

// Repo fetches connector status data from Elasticsearch.
type Repo struct {
	es *es.Client
}

// NewRepo creates a connector status repository.
func NewRepo(client *es.Client) *Repo {
	return &Repo{es: client}
}

// GetAll fetches all connector documents from ES internal_objects index.
func (r *Repo) GetAll() ([]Connector, error) {
	body := map[string]any{
		"size":    1000,
		"query":   map[string]any{"term": map[string]any{"entity_type.keyword": "connector"}},
		"_source": []string{"internal_id", "name", "built_in", "updated_at", "connector_info"},
	}

	res, err := r.es.Search("internal_objects", body)
	if err != nil {
		return nil, fmt.Errorf("get connectors: %w", err)
	}

	out := make([]Connector, 0, len(res.Hits.Hits))
	for _, hit := range res.Hits.Hits {
		c, err := parseConnector(hit.Source)
		if err != nil {
			continue
		}
		out = append(out, c)
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

func parseConnector(src json.RawMessage) (Connector, error) {
	var raw rawConnector
	if err := json.Unmarshal(src, &raw); err != nil {
		return Connector{}, err
	}

	updatedAt, err := es.ParseTime(raw.UpdatedAt)
	if err != nil {
		return Connector{}, fmt.Errorf("parse updated_at: %w", err)
	}

	c := Connector{
		ID:        raw.InternalID,
		Name:      raw.Name,
		BuiltIn:   raw.BuiltIn,
		UpdatedAt: updatedAt,
	}

	if raw.Info != nil {
		if v, _ := raw.Info["last_run_datetime"].(string); v != "" {
			if t, err := es.ParseTime(v); err == nil {
				c.LastRun = &t
			}
		}
		if v, _ := raw.Info["next_run_datetime"].(string); v != "" {
			if t, err := es.ParseTime(v); err == nil {
				c.NextRun = &t
			}
		}
	}
	return c, nil
}
