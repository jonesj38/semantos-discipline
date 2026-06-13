---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/infra/pravega-gateway/gateway/proxy.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.045136+00:00
---

# infra/pravega-gateway/gateway/proxy.go

```go
// M3.2 — Pravega REST proxy logic.
//
// Routes:
//   GET  /health                                                 → 200 {"status":"ok"}
//   POST /v1/scopes                                              → :9090/v1/scopes
//   POST /v1/scopes/:scope/streams                               → :9090/v1/scopes/:scope/streams
//   POST /v1/scopes/:scope/streams/:stream/events                → :9091/v1/scopes/:scope/streams/:stream/event
//   POST /v1/scopes/:scope/readergroups                          → :9091/v1/scopes/:scope/readergroups
//   POST /v1/scopes/:scope/readergroups/:rg/readers              → :9091/v1/scopes/:scope/readergroups/:rg/readers
//   GET  /v1/scopes/:scope/readergroups/:rg/readers/:rid/events  → :9091 equivalent
//
// Proxy behaviour:
//   - Forwards request body and Content-Type verbatim.
//   - Returns upstream status code and body verbatim.
//   - Logs every proxied call to stderr.

package gateway

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
)

// Config holds the upstream Pravega endpoints and listen port.
type Config struct {
	ControllerURL string // e.g. "http://localhost:9090"
	DataURL       string // e.g. "http://localhost:9091"
	Port          string // e.g. "7180"
}

// Handler returns an http.Handler that implements the gateway routes.
func Handler(cfg Config) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(HealthResponse{Status: "ok"})
	})

	// POST /v1/scopes  → controller
	mux.HandleFunc("POST /v1/scopes", func(w http.ResponseWriter, r *http.Request) {
		upstream := cfg.ControllerURL + "/v1/scopes"
		proxyRequest(w, r, upstream)
	})

	// All /v1/scopes/{scope}/... routes — dispatch by suffix.
	mux.HandleFunc("/v1/scopes/", func(w http.ResponseWriter, r *http.Request) {
		dispatchScopeRoutes(w, r, cfg)
	})

	return mux
}

// dispatchScopeRoutes handles parameterised routes under /v1/scopes/{scope}/...
// Go 1.22 pattern matching doesn't support path parameters natively in
// ServeMux without 3rd-party libs, so we parse manually.
func dispatchScopeRoutes(w http.ResponseWriter, r *http.Request, cfg Config) {
	// Strip leading "/v1/scopes/"
	rest := strings.TrimPrefix(r.URL.Path, "/v1/scopes/")
	// rest is one of:
	//   {scope}/streams
	//   {scope}/streams/{stream}/events
	//   {scope}/readergroups
	//   {scope}/readergroups/{rg}/readers
	//   {scope}/readergroups/{rg}/readers/{rid}/events

	parts := strings.SplitN(rest, "/", -1)
	if len(parts) < 2 {
		http.NotFound(w, r)
		return
	}

	scope := parts[0]

	switch {
	// POST /v1/scopes/{scope}/streams — controller
	case len(parts) == 2 && parts[1] == "streams" && r.Method == http.MethodPost:
		upstream := fmt.Sprintf("%s/v1/scopes/%s/streams", cfg.ControllerURL, scope)
		proxyRequest(w, r, upstream)

	// POST /v1/scopes/{scope}/streams/{stream}/events — data plane
	case len(parts) == 4 && parts[1] == "streams" && parts[3] == "events" && r.Method == http.MethodPost:
		stream := parts[2]
		// Pravega data-plane endpoint uses singular "event"
		upstream := fmt.Sprintf("%s/v1/scopes/%s/streams/%s/event", cfg.DataURL, scope, stream)
		proxyRequest(w, r, upstream)

	// POST /v1/scopes/{scope}/readergroups — data plane
	case len(parts) == 2 && parts[1] == "readergroups" && r.Method == http.MethodPost:
		upstream := fmt.Sprintf("%s/v1/scopes/%s/readergroups", cfg.DataURL, scope)
		proxyRequest(w, r, upstream)

	// POST /v1/scopes/{scope}/readergroups/{rg}/readers — data plane
	case len(parts) == 4 && parts[1] == "readergroups" && parts[3] == "readers" && r.Method == http.MethodPost:
		rg := parts[2]
		upstream := fmt.Sprintf("%s/v1/scopes/%s/readergroups/%s/readers", cfg.DataURL, scope, rg)
		proxyRequest(w, r, upstream)

	// GET /v1/scopes/{scope}/readergroups/{rg}/readers/{rid}/events — data plane
	case len(parts) == 6 && parts[1] == "readergroups" && parts[3] == "readers" && parts[5] == "events" && r.Method == http.MethodGet:
		rg := parts[2]
		rid := parts[4]
		upstream := fmt.Sprintf("%s/v1/scopes/%s/readergroups/%s/readers/%s/events", cfg.DataURL, scope, rg, rid)
		proxyRequest(w, r, upstream)

	default:
		http.NotFound(w, r)
	}
}

// proxyRequest forwards the incoming request to upstream and pipes the
// response back verbatim.
func proxyRequest(w http.ResponseWriter, r *http.Request, upstream string) {
	// Read request body.
	body, err := io.ReadAll(r.Body)
	if err != nil {
		log.Printf("proxy: read body error: %v", err)
		http.Error(w, "failed to read request body", http.StatusInternalServerError)
		return
	}

	// Build upstream request.
	req, err := http.NewRequestWithContext(r.Context(), r.Method, upstream, strings.NewReader(string(body)))
	if err != nil {
		log.Printf("proxy: build request error: %v", err)
		http.Error(w, "failed to build upstream request", http.StatusInternalServerError)
		return
	}

	// Forward Content-Type.
	if ct := r.Header.Get("Content-Type"); ct != "" {
		req.Header.Set("Content-Type", ct)
	}
	// Forward Accept.
	if ac := r.Header.Get("Accept"); ac != "" {
		req.Header.Set("Accept", ac)
	}

	// Execute upstream request.
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Printf("proxy: upstream %s %s error: %v", r.Method, upstream, err)
		http.Error(w, "upstream request failed", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	log.Printf("proxy: %s %s → %s [%d]", r.Method, r.URL.Path, upstream, resp.StatusCode)

	// Pipe response back.
	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("proxy: read upstream body error: %v", err)
		http.Error(w, "failed to read upstream response", http.StatusBadGateway)
		return
	}

	// Copy upstream Content-Type.
	if ct := resp.Header.Get("Content-Type"); ct != "" {
		w.Header().Set("Content-Type", ct)
	}
	w.WriteHeader(resp.StatusCode)
	_, _ = w.Write(respBody)
}

```
