package domain

import "time"

// InactiveThreshold matches OpenCTI platform logic: sinceNowInMinutes(updated_at) < 5.
const InactiveThreshold = 5 * time.Minute

// IsActive determines whether a connector should be considered active.
// Built-in connectors are always active. Non built-in connectors are active
// only if their last heartbeat (updated_at) is within 5 minutes.
func IsActive(c ConnectorStatus) bool {
	if c.BuiltIn {
		return true
	}
	return time.Since(c.UpdatedAt) <= InactiveThreshold
}
