---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/nats/supervisor.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.323541+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/nats/supervisor.ex

```ex
defmodule WorldHost.Nats.Supervisor do
  @moduledoc """
  Supervision tree for the NATS event-spine integration.

  Starts:
    - `WorldHost.Nats.Connection`  — Gnat connection to the local NATS server
    - `WorldHost.Nats.JamPublisher` — publishes committed jam cells to `jam.<room_id>.cell`
    - `WorldHost.Nats.JamConsumer`  — durable pull consumer; relays persisted cells back
                                      through Phoenix.PubSub for late-joiners / replays

  Enabled only when `:world_host, :nats_url` is configured (defaults to
  `nats://127.0.0.1:4222`). Skipped silently when NATS is not configured so the
  app boots cleanly in environments without a NATS server.
  """

  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    nats_host = Application.get_env(:world_host, :nats_host, "127.0.0.1")
    nats_port = Application.get_env(:world_host, :nats_port, 4222)

    Logger.info("WorldHost.Nats starting — #{nats_host}:#{nats_port}")

    connection_settings = %{
      host: nats_host,
      port: nats_port,
    }

    children = [
      # Named Gnat connection; all other NATS modules look it up by name
      {Gnat.ConnectionSupervisor,
       %{
         name: WorldHost.Nats.Conn,
         backoff_period: 4_000,
         connection_settings: [connection_settings],
       }},
      WorldHost.Nats.StreamProvisioner,
      WorldHost.Nats.JamPublisher,
      WorldHost.Nats.JamConsumer,
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

```
