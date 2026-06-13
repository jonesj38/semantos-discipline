---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/infra/pravega-gateway/PRAVEGA-GATEWAY.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.043228+00:00
---

# Pravega Gateway — M3.2

## Architecture decision

Pravega's native client is JVM-only. Rather than binding Zig to the JVM via CGo or FFI, M3.2 uses a **Go HTTP gateway sidecar**: a tiny Go binary that proxies brain's simple HTTP calls to Pravega's existing REST API (controller `:9090`, data-plane `:9091`). The brain Zig runtime calls the sidecar at `http://127.0.0.1:7180`; the sidecar handles all Pravega protocol details.

```
┌─────────┐   HTTP/JSON    ┌──────────────────┐   REST    ┌────────────┐
│   brain   │ ─────────────► │ pravega-gateway   │ ────────► │  Pravega   │
│  (Zig)  │  :7180         │  (Go sidecar)     │ :9090/91  │  cluster   │
└─────────┘                └──────────────────┘           └────────────┘
```

## Configuration

| Env var                  | Flag              | Default                  | Description                    |
|--------------------------|-------------------|--------------------------|--------------------------------|
| `PRAVEGA_CONTROLLER_URL` | `--controller-url`| `http://localhost:9090`  | Pravega controller REST URL    |
| `PRAVEGA_DATA_URL`       | `--data-url`      | `http://localhost:9091`  | Pravega data-plane REST URL    |
| `PRAVEGA_GATEWAY_PORT`   | `--port`          | `7180`                   | Gateway listen port            |

## Building

```bash
cd infra/pravega-gateway
go build -o pravega-gateway .
```

Requires Go 1.22+. No external dependencies — stdlib only.

## Running alongside brain

```bash
# Terminal 1: Start Pravega (M3.1 docker-compose)
cd infra/pravega && docker compose up -d

# Terminal 2: Start gateway
cd infra/pravega-gateway && ./pravega-gateway

# Terminal 3: Run brain (calls gateway at http://127.0.0.1:7180)
cd runtime/semantos-brain && ./brain ...
```

## Routes

| Method | Gateway path                                              | Upstream                                        |
|--------|-----------------------------------------------------------|-------------------------------------------------|
| GET    | `/health`                                                 | `{"status":"ok"}` (local)                       |
| POST   | `/v1/scopes`                                             | `:9090/v1/scopes`                               |
| POST   | `/v1/scopes/:scope/streams`                              | `:9090/v1/scopes/:scope/streams`                |
| POST   | `/v1/scopes/:scope/streams/:stream/events`               | `:9091/v1/scopes/:scope/streams/:stream/event`  |
| POST   | `/v1/scopes/:scope/readergroups`                         | `:9091/v1/scopes/:scope/readergroups`           |
| POST   | `/v1/scopes/:scope/readergroups/:rg/readers`             | `:9091 equivalent`                              |
| GET    | `/v1/scopes/:scope/readergroups/:rg/readers/:rid/events` | `:9091 equivalent`                              |

Note: Pravega's data-plane uses singular `/event` for writes; the gateway translates `/events` → `/event`.

## Zig client

`runtime/semantos-brain/src/pravega_client.zig` provides `PravegatClient`:

```zig
var client = try PravegatClient.init(allocator, .{
    .gateway_url = "http://127.0.0.1:7180",
    .scope = "my-scope",
});
defer client.deinit();

try client.ensureScope();
try client.ensureStream("my-stream");
try client.writeEvent("my-stream", "key", "{\"hello\":\"world\"}");

const rg = try client.createReaderGroup("my-stream");
defer allocator.free(rg);
const rid = try client.createReader(rg);
defer allocator.free(rid);
const event = try client.readEvent(rg, rid);
if (event) |ev| {
    defer allocator.free(ev);
    // process ev...
}
```

## Tests

```bash
# Zig unit tests (mock HTTP, no Pravega required)
cd core/cell-engine && zig build test-pravega-client

# Go gateway unit + proxy routing tests (no Pravega required)
cd infra/pravega-gateway && go test ./tests/ -run "TestHealth|TestProxyRouting|TestProxyStatus|TestGatewayListenPort" -v

# Shell integration smoke test (requires Pravega docker-compose)
bash infra/pravega/tests/m3_2_gateway_test.sh
```
