package connstats

// WorkStats holds aggregated work statistics for a connector in a time range.
type WorkStats struct {
	ConnectorID string
	WorksCount  int
	ItemsDone   int
	ErrorCount  int
}
