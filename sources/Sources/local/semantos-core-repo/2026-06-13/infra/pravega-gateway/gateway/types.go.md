---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/infra/pravega-gateway/gateway/types.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.044853+00:00
---

# infra/pravega-gateway/gateway/types.go

```go
// M3.2 — Pravega gateway request/response types.
//
// All types are plain Go structs that marshal to/from JSON.
// The gateway proxies Pravega's existing REST API verbatim,
// so these types reflect the Pravega REST wire format.

package gateway

// ScopeCreateRequest is the body for POST /v1/scopes.
type ScopeCreateRequest struct {
	ScopeName string `json:"scopeName"`
}

// StreamCreateRequest is the body for POST /v1/scopes/:scope/streams.
type StreamCreateRequest struct {
	StreamName      string          `json:"streamName"`
	ScalingPolicy   ScalingPolicy   `json:"scalingPolicy"`
	RetentionPolicy RetentionPolicy `json:"retentionPolicy"`
}

// ScalingPolicy mirrors Pravega's scalingPolicy object.
type ScalingPolicy struct {
	Type            string `json:"type"`
	MinNumSegments  int    `json:"minNumSegments,omitempty"`
}

// RetentionPolicy mirrors Pravega's retentionPolicy object.
type RetentionPolicy struct {
	Type string `json:"type"`
}

// EventWriteRequest is the body for POST .../events.
// The gateway forwards the raw body verbatim — this type is
// here for documentation; actual proxy code passes body bytes through.

// ReaderGroupCreateRequest is the body for POST .../readergroups.
type ReaderGroupCreateRequest struct {
	ReaderGroupName string   `json:"readerGroupName"`
	Streams         []Stream `json:"streams"`
}

// Stream identifies a Pravega stream within a scope.
type Stream struct {
	ScopeName  string `json:"scopeName"`
	StreamName string `json:"streamName"`
}

// ReaderCreateRequest is the body for POST .../readers.
type ReaderCreateRequest struct {
	ReaderID string `json:"readerId"`
}

// HealthResponse is the response body for GET /health.
type HealthResponse struct {
	Status string `json:"status"`
}

```
