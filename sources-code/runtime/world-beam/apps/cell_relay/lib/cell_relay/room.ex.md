---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/cell_relay/lib/cell_relay/room.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.330319+00:00
---

# runtime/world-beam/apps/cell_relay/lib/cell_relay/room.ex

```ex
defmodule CellRelay.Room do
  @moduledoc """
  GenServer for a single cell-relay room. Originally used to host
  `apps/world-apps/jam-room/` jam sessions; the relay is generic — every room
  in the cell DAG (jam sessions, release.kernel.* rooms, future helm
  sessions, etc.) is just another instance of this GenServer.

  State:
    * `:id` — room identifier (sanitised)
    * `:cells` — list of cell maps in arrival order
    * `:by_hash` — MapSet of stateHashHex for O(1) dedupe
    * `:subs` — MapSet of subscriber WS pids

  Persistence: appends every cell as a JSON line to
  `<data_dir>/<roomId>.jsonl`. On `start_link` it replays the file so
  cells survive node restarts. The format matches the Bun relay byte-
  for-byte so the same data dir can be shared during migration.

  Process discipline:
    * Subscribers monitor the room (and the room monitors them) so a
      crashed WS pid is GC'd from `:subs` automatically.
    * Each room is a leaf in the supervision tree; if it crashes the
      DynamicSupervisor restarts it and the JSONL log is replayed —
      no in-memory state is lost.
  """
  use GenServer
  require Logger

  # WorldHost.Nats.JamPublisher is only present in the `world` release (not `relay`).
  # The Code.ensure_loaded? guard below handles this at runtime; suppress compile warning.
  @compile {:no_warn_undefined, WorldHost.Nats.JamPublisher}

  # ── public API ────────────────────────────────────────────────

  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: via(room_id))
  end

  @doc "Start a room (or return existing pid). Idempotent + race-safe."
  def ensure_started(room_id) do
    case Registry.lookup(CellRelay.Registry, room_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(CellRelay.RoomSupervisor, {__MODULE__, room_id}) do
          {:ok, pid} -> {:ok, pid}
          # Two concurrent connections to a fresh room race here; the
          # loser gets `:already_started` and that's fine — both want
          # the same singleton.
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end
    end
  end

  @doc "Subscribe `pid` (with identity) to live broadcasts. Returns
  `{cells, presence}` where presence is the list of currently joined
  identities — so clients can render a peer roster on connect even
  before anyone has authored a cell."
  def subscribe(room_id, pid, identity) do
    GenServer.call(via(room_id), {:subscribe, pid, identity})
  end

  @doc "Unsubscribe `pid` (idempotent)."
  def unsubscribe(room_id, pid) do
    GenServer.cast(via(room_id), {:unsubscribe, pid})
  end

  @doc "List of identities currently subscribed to this room."
  def presence(room_id) do
    GenServer.call(via(room_id), :presence)
  end

  @doc "Broadcast a transient `live` payload (e.g. step trigger) to other
  subs. NOT persisted — the relay just relays. Used for note-on /
  step-fire events that need to travel quickly without DAG overhead."
  def live(room_id, payload, author_identity, author_pid) do
    GenServer.cast(via(room_id), {:live, payload, author_identity, author_pid})
  end

  @doc "Append a cell from `author_identity` and broadcast to other subs."
  def commit(room_id, cell, author_identity, author_pid) do
    GenServer.cast(via(room_id), {:commit, cell, author_identity, author_pid})
  end

  @doc "Wipe room state + persisted log. Notifies all subs."
  def reset(room_id) do
    GenServer.cast(via(room_id), :reset)
  end

  @doc "Broadcast a beat tick from the room Clock to all subs. Not persisted."
  def broadcast_beat(room_id, beat_map) do
    GenServer.cast(via(room_id), {:broadcast_beat, beat_map})
  end

  @doc "Snapshot for the discovery endpoint: `%{id, clients, cells}`."
  def stats(room_id) do
    GenServer.call(via(room_id), :stats)
  end

  defp via(room_id), do: {:via, Registry, {CellRelay.Registry, room_id}}

  # ── GenServer callbacks ───────────────────────────────────────

  @impl true
  def init(room_id) do
    Process.flag(:trap_exit, true)
    state = %{
      id: room_id,
      cells: [],
      by_hash: MapSet.new(),
      subs: MapSet.new(),
      monitors: %{},
      # pid → identity (lets us broadcast a presence roster).
      identities: %{}
    }
    state = replay_log(state)
    if length(state.cells) > 0 do
      Logger.info("room=#{room_id} replayed #{length(state.cells)} cells")
    end
    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, pid, identity}, _from, state) do
    ref = Process.monitor(pid)
    state = %{state |
      subs: MapSet.put(state.subs, pid),
      monitors: Map.put(state.monitors, pid, ref),
      identities: Map.put(state.identities, pid, identity)
    }
    presence = Map.values(state.identities) |> Enum.uniq()

    # Tell everyone else "X joined" so their UIs update immediately.
    msg = Jason.encode_to_iodata!(%{
      "type" => "presence",
      "identities" => presence,
      "joined" => identity
    })
    for sub <- state.subs, sub != pid, do: send(sub, {:cell_relay_broadcast, msg})

    {:reply, {:ok, state.cells, presence}, state}
  end

  def handle_call(:stats, _from, state) do
    {:reply,
      %{
        id: state.id,
        clients: MapSet.size(state.subs),
        cells: length(state.cells),
        identities: Map.values(state.identities) |> Enum.uniq()
      },
      state}
  end

  def handle_call(:presence, _from, state) do
    {:reply, Map.values(state.identities) |> Enum.uniq(), state}
  end

  @impl true
  def handle_cast({:unsubscribe, pid}, state) do
    {:noreply, drop_sub(state, pid)}
  end

  def handle_cast({:live, payload, author, author_pid}, state) do
    msg = Jason.encode_to_iodata!(%{
      "type" => "live",
      "payload" => payload,
      "from" => %{"identity" => author}
    })
    for sub <- state.subs, sub != author_pid do
      send(sub, {:cell_relay_broadcast, msg})
    end
    {:noreply, state}
  end

  def handle_cast({:commit, cell, author, author_pid}, state) do
    hash = cell["stateHashHex"]
    cond do
      is_nil(hash) ->
        {:noreply, state}

      MapSet.member?(state.by_hash, hash) ->
        {:noreply, state}

      true ->
        # Tag the cell with author identity so other clients can bucket
        # it into per-peer DAGs (used by the 4-channel mixer).
        tagged = Map.put(cell, "author", author)
        persist_cell(state.id, tagged)

        # Publish to NATS JetStream when world_host is co-deployed in the
        # same BEAM node (`world` release). Guarded so the relay-only Docker
        # image (`relay` release) keeps working without world_host.
        if Code.ensure_loaded?(WorldHost.Nats.JamPublisher) do
          WorldHost.Nats.JamPublisher.publish(state.id, tagged)
        end

        msg = Jason.encode_to_iodata!(%{
          "type" => "commit",
          "cell" => tagged,
          "from" => %{"identity" => author}
        })

        for sub <- state.subs, sub != author_pid do
          send(sub, {:cell_relay_broadcast, msg})
        end

        Logger.debug("room=#{state.id} ← #{author} #{cell["patch"]["op"]} #{String.slice(hash, 0, 10)}")

        {:noreply, %{state |
          cells: state.cells ++ [tagged],
          by_hash: MapSet.put(state.by_hash, hash)
        }}
    end
  end

  def handle_cast({:broadcast_beat, beat_map}, state) do
    msg = Jason.encode_to_iodata!(beat_map)
    for sub <- state.subs, do: send(sub, {:cell_relay_broadcast, msg})
    {:noreply, state}
  end

  def handle_cast(:reset, state) do
    truncate_log(state.id)
    msg = Jason.encode_to_iodata!(%{"type" => "reset"})
    for sub <- state.subs, do: send(sub, {:cell_relay_broadcast, msg})
    {:noreply, %{state | cells: [], by_hash: MapSet.new()}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, drop_sub(state, pid)}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp drop_sub(state, pid) do
    case Map.fetch(state.monitors, pid) do
      {:ok, ref} -> Process.demonitor(ref, [:flush])
      :error -> :ok
    end
    left = state.identities[pid]
    state = %{state |
      subs: MapSet.delete(state.subs, pid),
      monitors: Map.delete(state.monitors, pid),
      identities: Map.delete(state.identities, pid)
    }
    presence = Map.values(state.identities) |> Enum.uniq()
    msg = Jason.encode_to_iodata!(%{
      "type" => "presence",
      "identities" => presence,
      "left" => left
    })
    for sub <- state.subs, do: send(sub, {:cell_relay_broadcast, msg})
    state
  end

  # ── persistence ───────────────────────────────────────────────

  defp data_dir, do: Application.get_env(:cell_relay, :data_dir, "data")

  defp log_path(room_id) do
    safe = String.replace(room_id, ~r/[^a-zA-Z0-9_-]/, "_") |> String.slice(0, 64)
    safe = if safe == "", do: "lobby", else: safe
    Path.join(data_dir(), "#{safe}.jsonl")
  end

  defp replay_log(state) do
    path = log_path(state.id)
    File.mkdir_p!(data_dir())
    case File.read(path) do
      {:ok, text} ->
        cells =
          text
          |> String.split("\n", trim: true)
          |> Enum.map(&safe_decode/1)
          |> Enum.reject(&is_nil/1)

        Enum.reduce(cells, state, fn cell, acc ->
          h = cell["stateHashHex"]
          if h && !MapSet.member?(acc.by_hash, h) do
            %{acc | cells: acc.cells ++ [cell], by_hash: MapSet.put(acc.by_hash, h)}
          else
            acc
          end
        end)

      {:error, :enoent} ->
        state

      {:error, reason} ->
        Logger.warning("room=#{state.id} replay failed: #{inspect(reason)}")
        state
    end
  end

  defp safe_decode(line) do
    case Jason.decode(line) do
      {:ok, m} -> m
      _ -> nil
    end
  end

  defp persist_cell(room_id, cell) do
    File.mkdir_p!(data_dir())
    iodata = [Jason.encode_to_iodata!(cell), "\n"]
    File.write!(log_path(room_id), iodata, [:append])
  end

  defp truncate_log(room_id), do: File.write!(log_path(room_id), "")
end

```
