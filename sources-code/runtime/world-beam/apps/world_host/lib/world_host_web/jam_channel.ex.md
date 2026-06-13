---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host_web/jam_channel.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.316267+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host_web/jam_channel.ex

```ex
defmodule WorldHostWeb.JamChannel do
  @moduledoc """
  Phoenix Channel for collaborative jam-room sessions.

  Topic: `jam:<room_id>` (e.g. `jam:shelf-cantor-fox`)

  ## Lifecycle

  1. **join** — verify room_id, subscribe to `Phoenix.PubSub`, replay the last
     N cells from NATS JetStream so late-joiners see the current pattern state.
  2. **commit** — client pushes a new cell (drum pattern, melody, BPM setting).
     Channel validates, forwards to `CellRelay.Room` (same BEAM node), and
     publishes to NATS JetStream via `WorldHost.Nats.JamPublisher`.
  3. **trigger** — ephemeral live trigger (drum step fire, note on). Broadcast
     through Phoenix.PubSub only — not persisted to NATS.
  4. **set_bpm** — updates the room clock. Forwarded to `CellRelay.Clock`.
  5. **clock_ping** — BEAMClock NTP packet. Echoed back as `clock_pong` with
     server timestamps for latency compensation.

  ## Presence

  Uses `Phoenix.Presence` (via WorldHost.PubSub) to track connected guests.
  The presence diff is pushed to all channel members on join/leave.
  """

  use Phoenix.Channel
  require Logger

  alias WorldHost.Nats.JamPublisher
  alias WorldHost.Nats.JamConsumer

  # ── Join ───────────────────────────────────────────────────────────────────

  @impl true
  def join("jam:" <> room_id, _params, socket) do
    socket = assign(socket, :room_id, room_id)

    # Subscribe to PubSub topic (NATS consumer broadcasts here)
    Phoenix.PubSub.subscribe(WorldHost.PubSub, "jam:#{room_id}")

    # Schedule late-join replay and presence push asynchronously
    # so the join ACK goes back to the client immediately.
    send(self(), :after_join)

    {:ok, %{room_id: room_id, guest_id: socket.assigns.guest_id}, socket}
  end

  # ── Inbound events ─────────────────────────────────────────────────────────

  @impl true
  def handle_in("commit", %{"cell" => cell}, socket) when is_map(cell) do
    room_id = socket.assigns.room_id
    handle  = socket.assigns.handle

    # Tag authorship
    cell = Map.merge(cell, %{"author" => handle, "room_id" => room_id})

    # Forward to cell_relay Room (same BEAM node) for in-memory + JSONL persistence.
    # commit/4: (room_id, cell, author_identity, author_pid)
    if Code.ensure_loaded?(CellRelay.Room) do
      try do
        {:ok, _} = CellRelay.Room.ensure_started(room_id)
        CellRelay.Room.commit(room_id, cell, handle, self())
      rescue
        _ -> :ok
      end
    end

    # Publish to NATS JetStream for durable storage
    JamPublisher.publish(room_id, cell)

    # Fan out to all Phoenix channel subscribers
    broadcast!(socket, "cell", cell)

    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("trigger", payload, socket) when is_map(payload) do
    # Ephemeral live trigger — broadcast only, not persisted
    broadcast!(socket, "trigger", Map.put(payload, "from", socket.assigns.handle))
    {:noreply, socket}
  end

  @impl true
  def handle_in("set_bpm", %{"bpm" => bpm}, socket) when is_number(bpm) do
    room_id = socket.assigns.room_id
    bpm_int = round(bpm) |> max(20) |> min(300)

    # Forward to cell_relay Clock GenServer
    case Code.ensure_loaded?(CellRelay.Clock) do
      true ->
        try do
          CellRelay.ClockRegistry
          |> Registry.lookup(room_id)
          |> case do
            [{pid, _}] -> GenServer.cast(pid, {:set_bpm, bpm_int})
            _ -> :ok
          end
        rescue
          _ -> :ok
        end

      false -> :ok
    end

    broadcast!(socket, "bpm", %{bpm: bpm_int, from: socket.assigns.handle})
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("clock_ping", %{"client_send" => cs}, socket) do
    now = System.system_time(:millisecond)
    push(socket, "clock_pong", %{client_send: cs, server_recv: now, server_send: now})
    {:noreply, socket}
  end

  @impl true
  def handle_in(event, _payload, socket) do
    Logger.debug("JamChannel: unhandled event #{event}")
    {:noreply, socket}
  end

  # ── Info (PubSub messages from NATS consumer) ──────────────────────────────

  @impl true
  def handle_info(:after_join, socket) do
    room_id  = socket.assigns.room_id
    handle   = socket.assigns.handle
    guest_id = socket.assigns.guest_id

    # Track this guest in Presence (pushes presence_state + future diffs automatically)
    {:ok, _} = WorldHostWeb.Presence.track(socket, guest_id, %{
      handle:    handle,
      joined_at: System.system_time(:millisecond),
    })

    # Push current presence list so the joining client sees everyone immediately
    push(socket, "presence_state", WorldHostWeb.Presence.list(socket))

    # Late-join cell replay from NATS JetStream
    cells = JamConsumer.recent_cells(room_id, 200)
    unless Enum.empty?(cells) do
      push(socket, "snapshot", %{cells: cells, room_id: room_id})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:nats_cell, cell}, socket) do
    # Cell arrived from NATS consumer (published by another node or replay)
    # Only push if it wasn't authored by this socket's guest
    if Map.get(cell, "author") != socket.assigns.handle do
      push(socket, "cell", cell)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}
end

```
