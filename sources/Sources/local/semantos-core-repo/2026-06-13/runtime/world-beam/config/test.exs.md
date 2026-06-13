---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/config/test.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.311701+00:00
---

# runtime/world-beam/config/test.exs

```exs
import Config

config :world_host, WorldHostWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_only_secret_key_base_000000000000000000000000000000000000000000000000",
  server: false

config :world_host,
  wait_for_sidecar: false,
  verifier_client: WorldHost.VerifierClient.Mock,
  demo_cube_count: 0

config :cell_relay,
  port: 5179,
  data_dir: "test/tmp/data"

config :logger, level: :warning

```
