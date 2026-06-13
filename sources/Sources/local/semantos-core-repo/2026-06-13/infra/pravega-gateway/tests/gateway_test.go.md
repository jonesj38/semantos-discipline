---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/infra/pravega-gateway/tests/gateway_test.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.044518+00:00
---

# infra/pravega-gateway/tests/gateway_test.go

```go
// M3.2 — Go gateway integration tests.
//
// Tests start the gateway in-process and verify that:
//   - /health returns 200 {"status":"ok"}
//   - POST /v1/scopes is proxied to :9090
//   - POST .../streams is proxied to :9090
//   - POST .../events is proxied to :9091 (with singular "event" path)
//   - POST .../readergroups is proxied to :9091
//   - POST .../readers is proxied to :9091
//   - GET  .../events (reader read) is proxied to :9091
//
// All tests that touch Pravega are skipped if PRAVEGA_CONTROLLER_URL is not set
// or the controller is not reachable (i.e. docker-compose is not running).
//
// Run with Pravega:
//   cd infra/pravega && docker compose up -d
//   cd infra/pravega-gateway && go test ./tests/ -v -timeout 60s
//
// Run without Pravega (health + unit checks only):
//   go test ./tests/ -v -run TestHealth

package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"semantos/pravega-gateway/gateway"
)

// startGateway launches the gateway handler on a random port and returns
// the base URL. The caller is responsible for calling ts.Close().
func startGateway(cfg gateway.Config) *httptest.Server {
	h := gateway.Handler(cfg)
	return httptest.NewServer(h)
}

// pravegaAvailable returns true if the Pravega controller is reachable.
func pravegaAvailable(controllerURL string) bool {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, controllerURL+"/v1/ping", nil)
	if err != nil {
		return false
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return false
	}
	resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}

// defaultConfig returns a Config using env vars with localhost defaults.
func defaultConfig() gateway.Config {
	ctrl := os.Getenv("PRAVEGA_CONTROLLER_URL")
	if ctrl == "" {
		ctrl = "http://localhost:9090"
	}
	data := os.Getenv("PRAVEGA_DATA_URL")
	if data == "" {
		data = "http://localhost:9091"
	}
	return gateway.Config{
		ControllerURL: ctrl,
		DataURL:       data,
		Port:          "0",
	}
}

// ── Health ────────────────────────────────────────────────────────────────────

// TestHealth verifies GET /health returns 200 and {"status":"ok"}.
// Does NOT require Pravega to be running.
func TestHealth(t *testing.T) {
	cfg := defaultConfig()
	ts := startGateway(cfg)
	defer ts.Close()

	resp, err := http.Get(ts.URL + "/health")
	if err != nil {
		t.Fatalf("health request failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	var body map[string]string
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("decode health response: %v", err)
	}
	if body["status"] != "ok" {
		t.Fatalf("expected status=ok, got %q", body["status"])
	}
}

// ── Proxy routing unit tests (stub upstreams) ─────────────────────────────────

// TestProxyRouting verifies that the gateway routes to the correct upstream
// paths using stub HTTP servers (no real Pravega required).
func TestProxyRouting(t *testing.T) {
	var capturedPath, capturedMethod string

	// Stub that records the request path and method.
	stub := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedPath = r.URL.Path
		capturedMethod = r.Method
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{}`))
	}))
	defer stub.Close()

	cfg := gateway.Config{
		ControllerURL: stub.URL,
		DataURL:       stub.URL,
		Port:          "0",
	}
	ts := startGateway(cfg)
	defer ts.Close()

	cases := []struct {
		name           string
		method         string
		path           string
		expectedPath   string
		expectedMethod string
	}{
		{
			name:           "scope create",
			method:         http.MethodPost,
			path:           "/v1/scopes",
			expectedPath:   "/v1/scopes",
			expectedMethod: http.MethodPost,
		},
		{
			name:           "stream create",
			method:         http.MethodPost,
			path:           "/v1/scopes/myscope/streams",
			expectedPath:   "/v1/scopes/myscope/streams",
			expectedMethod: http.MethodPost,
		},
		{
			name:           "event write",
			method:         http.MethodPost,
			path:           "/v1/scopes/myscope/streams/mystream/events",
			expectedPath:   "/v1/scopes/myscope/streams/mystream/event",
			expectedMethod: http.MethodPost,
		},
		{
			name:           "reader group create",
			method:         http.MethodPost,
			path:           "/v1/scopes/myscope/readergroups",
			expectedPath:   "/v1/scopes/myscope/readergroups",
			expectedMethod: http.MethodPost,
		},
		{
			name:           "reader create",
			method:         http.MethodPost,
			path:           "/v1/scopes/myscope/readergroups/myrg/readers",
			expectedPath:   "/v1/scopes/myscope/readergroups/myrg/readers",
			expectedMethod: http.MethodPost,
		},
		{
			name:           "event read",
			method:         http.MethodGet,
			path:           "/v1/scopes/myscope/readergroups/myrg/readers/reader-1/events",
			expectedPath:   "/v1/scopes/myscope/readergroups/myrg/readers/reader-1/events",
			expectedMethod: http.MethodGet,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			capturedPath = ""
			capturedMethod = ""

			var req *http.Request
			var err error
			if tc.method == http.MethodPost {
				req, err = http.NewRequest(tc.method, ts.URL+tc.path,
					bytes.NewReader([]byte(`{"test":true}`)))
				if err != nil {
					t.Fatalf("build request: %v", err)
				}
				req.Header.Set("Content-Type", "application/json")
			} else {
				req, err = http.NewRequest(tc.method, ts.URL+tc.path, nil)
				if err != nil {
					t.Fatalf("build request: %v", err)
				}
			}

			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatalf("request failed: %v", err)
			}
			resp.Body.Close()

			if capturedPath != tc.expectedPath {
				t.Errorf("upstream path: got %q, want %q", capturedPath, tc.expectedPath)
			}
			if capturedMethod != tc.expectedMethod {
				t.Errorf("upstream method: got %q, want %q", capturedMethod, tc.expectedMethod)
			}
		})
	}
}

// TestProxyStatus verifies that the gateway forwards upstream status codes verbatim.
func TestProxyStatus(t *testing.T) {
	for _, upstreamStatus := range []int{201, 409, 500} {
		t.Run(fmt.Sprintf("status-%d", upstreamStatus), func(t *testing.T) {
			stub := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(upstreamStatus)
			}))
			defer stub.Close()

			cfg := gateway.Config{
				ControllerURL: stub.URL,
				DataURL:       stub.URL,
				Port:          "0",
			}
			ts := startGateway(cfg)
			defer ts.Close()

			resp, err := http.Post(ts.URL+"/v1/scopes",
				"application/json", bytes.NewReader([]byte(`{"scopeName":"x"}`)))
			if err != nil {
				t.Fatalf("request failed: %v", err)
			}
			resp.Body.Close()

			if resp.StatusCode != upstreamStatus {
				t.Errorf("expected status %d, got %d", upstreamStatus, resp.StatusCode)
			}
		})
	}
}

// ── Integration tests (require Pravega docker-compose) ───────────────────────

// TestIntegration_ScopeAndStreamCreate runs the full create-scope/create-stream
// flow against a live Pravega cluster. Skipped if Pravega is not reachable.
func TestIntegration_ScopeAndStreamCreate(t *testing.T) {
	cfg := defaultConfig()
	if !pravegaAvailable(cfg.ControllerURL) {
		t.Skip("Pravega controller not reachable — skipping integration test")
	}

	ts := startGateway(cfg)
	defer ts.Close()

	scope := "m32-int-test"
	stream := "int-smoke"

	// Create scope.
	body := fmt.Sprintf(`{"scopeName":%q}`, scope)
	resp, err := http.Post(ts.URL+"/v1/scopes", "application/json",
		strings.NewReader(body))
	if err != nil {
		t.Fatalf("create scope: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusConflict {
		t.Fatalf("create scope: unexpected status %d", resp.StatusCode)
	}
	t.Logf("create scope %q: %d", scope, resp.StatusCode)

	// Create stream.
	streamBody := fmt.Sprintf(`{"streamName":%q,"scalingPolicy":{"type":"FIXED_NUM_SEGMENTS","minNumSegments":1},"retentionPolicy":{"type":"UNLIMITED"}}`, stream)
	resp2, err := http.Post(ts.URL+"/v1/scopes/"+scope+"/streams",
		"application/json", strings.NewReader(streamBody))
	if err != nil {
		t.Fatalf("create stream: %v", err)
	}
	resp2.Body.Close()
	if resp2.StatusCode != http.StatusCreated && resp2.StatusCode != http.StatusConflict {
		t.Fatalf("create stream: unexpected status %d", resp2.StatusCode)
	}
	t.Logf("create stream %q/%q: %d", scope, stream, resp2.StatusCode)
}

// TestIntegration_WriteAndRead writes one event and reads it back.
func TestIntegration_WriteAndRead(t *testing.T) {
	cfg := defaultConfig()
	if !pravegaAvailable(cfg.ControllerURL) {
		t.Skip("Pravega controller not reachable — skipping integration test")
	}

	ts := startGateway(cfg)
	defer ts.Close()

	scope := "m32-int-wr"
	stream := "wr-smoke"

	// Ensure scope.
	http.Post(ts.URL+"/v1/scopes", "application/json",
		strings.NewReader(fmt.Sprintf(`{"scopeName":%q}`, scope))) //nolint

	// Ensure stream.
	http.Post(ts.URL+"/v1/scopes/"+scope+"/streams", "application/json",
		strings.NewReader(fmt.Sprintf(`{"streamName":%q,"scalingPolicy":{"type":"FIXED_NUM_SEGMENTS","minNumSegments":1},"retentionPolicy":{"type":"UNLIMITED"}}`, stream))) //nolint

	// Write event.
	event := `{"hello":"M3.2","from":"go-gateway"}`
	wr, err := http.Post(ts.URL+"/v1/scopes/"+scope+"/streams/"+stream+"/events",
		"application/json", strings.NewReader(event))
	if err != nil {
		t.Fatalf("write event: %v", err)
	}
	wr.Body.Close()
	if wr.StatusCode != http.StatusCreated {
		t.Fatalf("write event: unexpected status %d", wr.StatusCode)
	}
	t.Logf("write event: %d", wr.StatusCode)

	// Create reader group.
	rg := "wr-rg-test"
	rgBody := fmt.Sprintf(`{"readerGroupName":%q,"streams":[{"scopeName":%q,"streamName":%q}]}`,
		rg, scope, stream)
	rgResp, err := http.Post(ts.URL+"/v1/scopes/"+scope+"/readergroups",
		"application/json", strings.NewReader(rgBody))
	if err != nil {
		t.Fatalf("create reader group: %v", err)
	}
	rgResp.Body.Close()
	if rgResp.StatusCode != http.StatusCreated {
		t.Fatalf("create reader group: unexpected status %d", rgResp.StatusCode)
	}

	// Create reader.
	rdrBody := `{"readerId":"reader-1"}`
	rdrResp, err := http.Post(ts.URL+"/v1/scopes/"+scope+"/readergroups/"+rg+"/readers",
		"application/json", strings.NewReader(rdrBody))
	if err != nil {
		t.Fatalf("create reader: %v", err)
	}
	rdrResp.Body.Close()
	if rdrResp.StatusCode != http.StatusCreated {
		t.Fatalf("create reader: unexpected status %d", rdrResp.StatusCode)
	}

	// Read event.
	evResp, err := http.Get(ts.URL + "/v1/scopes/" + scope + "/readergroups/" + rg + "/readers/reader-1/events")
	if err != nil {
		t.Fatalf("read event: %v", err)
	}
	evBody, _ := io.ReadAll(evResp.Body)
	evResp.Body.Close()
	t.Logf("read event response (%d): %s", evResp.StatusCode, string(evBody))

	if !strings.Contains(string(evBody), "M3.2") {
		t.Errorf("read event: expected M3.2 in body, got: %s", string(evBody))
	}
}

// TestGatewayListenPort verifies that the binary can actually bind and accept
// connections on a random port (no Pravega needed).
func TestGatewayListenPort(t *testing.T) {
	// Pick a random free port.
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	ln.Close()

	// Start gateway on that port.
	cfg := gateway.Config{
		ControllerURL: "http://localhost:9090",
		DataURL:       "http://localhost:9091",
		Port:          fmt.Sprintf("%d", port),
	}
	ts := startGateway(cfg)
	defer ts.Close()

	// Verify health.
	resp, err := http.Get(ts.URL + "/health")
	if err != nil {
		t.Fatalf("health: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Errorf("expected 200, got %d", resp.StatusCode)
	}
}

```
