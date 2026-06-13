---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/config/dev.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.311172+00:00
---

# runtime/world-beam/config/dev.exs

```exs
import Config

config :world_host, WorldHostWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  secret_key_base: "dev_only_secret_key_base_replace_in_prod_000000000000000000000000000000"

config :world_host, :wait_for_sidecar, false

config :logger, level: :debug

```
