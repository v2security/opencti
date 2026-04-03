package domain

import "time"

// ConnectorStatus represents a connector's heartbeat state from Elasticsearch.
type ConnectorStatus struct {
	ID        string
	Name      string
	BuiltIn   bool
	UpdatedAt time.Time
	LastRun   *time.Time
	NextRun   *time.Time
}

// WorkStats holds aggregated work statistics for a connector in a time range.
type WorkStats struct {
	ConnectorID string
	WorksCount  int
	ItemsDone   int
	ErrorCount  int
}
