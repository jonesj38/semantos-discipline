---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/config/prod.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.310897+00:00
---

# runtime/world-beam/config/prod.exs

```exs
import Config

config :world_host, WorldHostWeb.Endpoint,
  server: true,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :logger, level: :info

```
