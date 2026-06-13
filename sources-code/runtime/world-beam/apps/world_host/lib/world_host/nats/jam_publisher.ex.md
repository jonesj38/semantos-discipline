---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/nats/jam_publisher.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.323845+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/nats/jam_publisher.ex

```ex
defmodule WorldHost.Nats.JamPublisher do
  @moduledoc """
  Publishes committed jam-room cells to the NATS JetStream `jam` stream.

  Subject pattern: `jam.<room_id>.cell`

  Called by `CellRelay.Room` (same BEAM node) immediately after every cell
  commit. The call is fire-and-forget — NATS publish is async so it never
  blocks the room GenServer.

  The payload is the cell map as JSON (same shape as the WebSocket `commit`
  frame that cell_relay fans out to connected peers).
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ── Public API ─────────────────────────────────────────────────────────────

  @doc """
  Publish `cell` (a map) to `jam.<room_id>.cell`.
  Non-blocking — queues via the GenServer's mailbox.
  """
  def publish(room_id, cell) when is_binary(room_id) and is_map(cell) do
    GenServer.cast(__MODULE__, {:publish, room_id, cell})
  end

  # ── GenServer ──────────────────────────────────────────────────────────────

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_cast({:publish, room_id, cell}, state) do
    subject = "jam.#{room_id}.cell"
    body    = Jason.encode!(cell)

    case Gnat.pub(WorldHost.Nats.Conn, subject, body) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("JamPublisher: failed to publish to #{subject}: #{inspect(reason)}")
    end

    {:noreply, state}
  end
end

```
