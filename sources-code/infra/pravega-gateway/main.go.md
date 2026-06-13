---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/infra/pravega-gateway/main.go
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.043489+00:00
---

# infra/pravega-gateway/main.go

```go
// M3.2 — Pravega gateway sidecar.
//
// HTTP server on :7180 (default) that proxies wsh's simple HTTP calls
// to Pravega's existing REST API (controller :9090, data-plane :9091).
//
// Configuration (env vars override flags):
//   PRAVEGA_CONTROLLER_URL  (default http://localhost:9090)
//   PRAVEGA_DATA_URL        (default http://localhost:9091)
//   PRAVEGA_GATEWAY_PORT    (default 7180)
//
// Flags:
//   --controller-url <url>
//   --data-url <url>
//   --port <port>
//
// Usage:
//   go build -o pravega-gateway .
//   ./pravega-gateway
//   ./pravega-gateway --port 7181

package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"

	"semantos/pravega-gateway/gateway"
)

func main() {
	// Defaults.
	defaultController := "http://localhost:9090"
	defaultData := "http://localhost:9091"
	defaultPort := "7180"

	// Override defaults from env.
	if v := os.Getenv("PRAVEGA_CONTROLLER_URL"); v != "" {
		defaultController = v
	}
	if v := os.Getenv("PRAVEGA_DATA_URL"); v != "" {
		defaultData = v
	}
	if v := os.Getenv("PRAVEGA_GATEWAY_PORT"); v != "" {
		defaultPort = v
	}

	// Flags.
	controllerURL := flag.String("controller-url", defaultController, "Pravega controller REST URL")
	dataURL := flag.String("data-url", defaultData, "Pravega data-plane REST URL")
	port := flag.String("port", defaultPort, "Gateway listen port")
	flag.Parse()

	cfg := gateway.Config{
		ControllerURL: *controllerURL,
		DataURL:       *dataURL,
		Port:          *port,
	}

	addr := fmt.Sprintf("0.0.0.0:%s", cfg.Port)
	log.Printf("pravega-gateway: listening on %s (controller=%s, data=%s)",
		addr, cfg.ControllerURL, cfg.DataURL)

	handler := gateway.Handler(cfg)
	if err := http.ListenAndServe(addr, handler); err != nil {
		log.Fatalf("pravega-gateway: fatal: %v", err)
	}
}

```
