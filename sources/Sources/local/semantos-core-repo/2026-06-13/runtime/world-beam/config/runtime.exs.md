---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/config/runtime.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.311429+00:00
---

# runtime/world-beam/config/runtime.exs

```exs
import Config

# Runtime config — evaluated when the release boots, not at compile time.
# All env-var reads belong here.

if config_env() == :prod do
  relay_port = String.to_integer(System.get_env("RELAY_PORT") || "5178")
  relay_data_dir = System.get_env("RELAY_DATA_DIR") || "/var/lib/cell-relay/data"

  config :cell_relay,
    port: relay_port,
    data_dir: relay_data_dir

  # world_host (Phoenix) — only present in the full 'world' release.
  # The relay-only Docker image does not include world_host, so skip its config.
  if Code.ensure_loaded?(WorldHostWeb.Endpoint) do
    secret_key_base =
      System.get_env("SECRET_KEY_BASE") ||
        raise "environment variable SECRET_KEY_BASE is missing"

    host = System.get_env("PHX_HOST") || "localhost"
    port = String.to_integer(System.get_env("PORT") || "4000")

    config :world_host, WorldHostWeb.Endpoint,
      url: [host: host, port: 443, scheme: "https"],
      http: [ip: {0, 0, 0, 0}, port: port],
      secret_key_base: secret_key_base

    # Verifier Sidecar (D-V3). Set VERIFIER_SIDECAR_URL=none to skip wait
    # (e.g. when deploying without the BSV cert stack).
    sidecar_url = System.get_env("VERIFIER_SIDECAR_URL") || "http://127.0.0.1:8787"
    config :world_host, :verifier_sidecar_url, sidecar_url

    # Skip sidecar healthcheck when explicitly disabled or when the sidecar
    # URL is set to "none" (jam-room-only deploys that don't need BRC auth).
    wait_for_sidecar = System.get_env("WAIT_FOR_SIDECAR", "true") != "false" &&
                       sidecar_url != "none"
    config :world_host, :wait_for_sidecar, wait_for_sidecar

    tick_rate = String.to_integer(System.get_env("TICK_RATE_HZ") || "20")
    config :world_host, :tick_rate_hz, tick_rate

    # NATS event spine — connects to the local nats-server.
    # Set NATS_ENABLED=false to disable (e.g. in environments without NATS).
    nats_enabled = System.get_env("NATS_ENABLED", "true") != "false"
    nats_host    = System.get_env("NATS_HOST", "127.0.0.1")
    nats_port    = String.to_integer(System.get_env("NATS_PORT", "4222"))

    config :world_host,
      nats_enabled: nats_enabled,
      nats_host: nats_host,
      nats_port: nats_port
  end
end

```
