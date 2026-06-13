---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/cell_relay/lib/cell_relay/ws_handler.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.330626+00:00
---

# runtime/world-beam/apps/cell_relay/lib/cell_relay/ws_handler.ex

```ex
defmodule CellRelay.WSHandler do
  @moduledoc """
  Cowboy WebSocket handler. One process per client connection.

  Wire protocol matches the Bun relay so the browser jam-room
  (`apps/world-apps/jam-room/src/core/sync.ts`) connects unchanged:

      client → server `{type: 'commit', cell}`
      client → server `{type: 'reset'}`
      server → client `{type: 'snapshot', cells, your: {id, identity, room}}`
      server → client `{type: 'commit', cell, from: {identity}}`
      server → client `{type: 'reset'}`

  Each handler picks `?room=…` and `?as=…` off the upgrade URL,
  registers itself with the matching `CellRelay.Room` GenServer, and forwards
  broadcasts via the `{:cell_relay_broadcast, iodata}` info message.
  """
  @behaviour :cowboy_websocket

  require Logger

  @impl true
  def init(req, _state) do
    qs = :cowboy_req.parse_qs(req)
    room_q = (proplists_get(qs, "room") || "lobby") |> sanitise()
    identity = proplists_get(qs, "as") || "observer"
    id = random_id()

    {:cowboy_websocket, req,
     %{room: room_q, identity: identity, id: id, joined: false}}
  end

  @impl true
  def websocket_init(state) do
    {:ok, _pid} = CellRelay.Room.ensure_started(state.room)
    {:ok, cells, presence} = CellRelay.Room.subscribe(state.room, self(), state.identity)

    snapshot =
      Jason.encode_to_iodata!(%{
        "type" => "snapshot",
        "cells" => cells,
        "presence" => presence,
        "your" => %{"id" => state.id, "identity" => state.identity, "room" => state.room}
      })

    Logger.info(
      "+ #{state.identity}@#{state.room} (#{state.id})  cells=#{length(cells)}  presence=#{length(presence)}"
    )

    {[{:text, snapshot}], %{state | joined: true}}
  end

  @impl true
  def websocket_handle({:text, payload}, state) do
    case Jason.decode(payload) do
      {:ok, %{"type" => "commit", "cell" => cell}} ->
        CellRelay.Room.commit(state.room, cell, state.identity, self())
        {[], state}

      {:ok, %{"type" => "live", "payload" => payload}} ->
        CellRelay.Room.live(state.room, payload, state.identity, self())
        {[], state}

      {:ok, %{"type" => "reset"}} ->
        CellRelay.Room.reset(state.room)
        Logger.info("  #{state.identity}@#{state.room} → RESET")
        {[], state}

      # ── clock sync ──────────────────────────────────────────────────────────
      # Immediate pong with server timestamp — no Room involvement.
      # Client measures RTT as (recv_time - client_time) and estimates
      # one-way latency as RTT/2.
      {:ok, %{"type" => "clock_ping", "seq" => seq, "client_time" => client_time}} ->
        pong = Jason.encode_to_iodata!(%{
          "type" => "clock_pong",
          "seq" => seq,
          "client_time" => client_time,
          "server_time" => System.system_time(:millisecond)
        })
        {[{:text, pong}], state}

      # Start (or update) the room beat clock. Broadcasts beat messages to
      # all subs so every connected client stays on the same grid.
      {:ok, %{"type" => "set_bpm", "bpm" => bpm} = msg} ->
        beats_per_bar = Map.get(msg, "beats_per_bar", 4)
        CellRelay.Clock.set_bpm(state.room, bpm, beats_per_bar)
        Logger.info("  #{state.identity}@#{state.room} → set_bpm #{bpm}")
        {[], state}

      # A client's manual nudge offset — relay to peers so they can show it
      # in their UI ("Todd is nudged +12 ms"). Not persisted.
      {:ok, %{"type" => "clock_nudge", "nudge_ms" => nudge_ms}} ->
        CellRelay.Room.live(
          state.room,
          %{"type" => "clock_nudge", "identity" => state.identity, "nudge_ms" => nudge_ms},
          state.identity,
          self()
        )
        {[], state}

      _ ->
        {[], state}
    end
  end

  def websocket_handle(_, state), do: {[], state}

  @impl true
  def websocket_info({:cell_relay_broadcast, iodata}, state) do
    {[{:text, iodata}], state}
  end

  def websocket_info(_, state), do: {[], state}

  @impl true
  def terminate(_reason, _req, %{room: room, joined: true} = state) do
    CellRelay.Room.unsubscribe(room, self())
    Logger.info("- #{state.identity}@#{room} (#{state.id})")
    :ok
  end

  def terminate(_reason, _req, _state), do: :ok

  # ── helpers ───────────────────────────────────────────────────

  defp proplists_get(qs, key) do
    case List.keyfind(qs, key, 0) do
      {_, v} -> v
      _ -> nil
    end
  end

  defp sanitise(s) do
    s
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")
    |> String.slice(0, 64)
    |> case do
      "" -> "lobby"
      x -> x
    end
  end

  defp random_id do
    :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
  end
end

```
