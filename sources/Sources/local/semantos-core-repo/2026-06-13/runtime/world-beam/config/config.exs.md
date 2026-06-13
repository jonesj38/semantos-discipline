---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/config/config.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.311953+00:00
---

# runtime/world-beam/config/config.exs

```exs
import Config

# ── Shared BEAM configuration ─────────────────────────────────────────────────
# Settings here apply across both world_host and cell_relay unless overridden
# in the respective app's config block.

config :phoenix, :json_library, Jason

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:region_id, :entity_id, :room_id, :tick]

# ── world_host ────────────────────────────────────────────────────────────────

config :world_host, WorldHostWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [formats: [json: WorldHostWeb.ErrorJSON], layout: false],
  pubsub_server: WorldHost.PubSub,
  server: true

config :world_host,
  tick_rate_hz: 20,
  demo_region_id: "region-0001",
  demo_cube_count: 3,
  wait_for_sidecar: true

# ── cell_relay ────────────────────────────────────────────────────────────────

config :cell_relay,
  port: 5178,
  data_dir: "data"

import_config "#{config_env()}.exs"

```
