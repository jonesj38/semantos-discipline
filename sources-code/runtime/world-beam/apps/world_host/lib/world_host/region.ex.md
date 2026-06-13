---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/region.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.318473+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/region.ex

```ex
defmodule WorldHost.Region do
  @moduledoc """
  Authoritative shard. One Region = one multicast topic = one supervisor
  owning its entities.
  """

  use GenServer

  alias WorldHost.Entity
  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: via(opts[:id]))

  def via(id), do: {:via, Registry, {WorldHost.RegionRegistry, id}}

  def topic(id), do: "world:region:" <> id

  def spawn_entity(region_id, opts) do
    GenServer.call(via(region_id), {:spawn_entity, opts})
  end

  def list_entities(region_id), do: GenServer.call(via(region_id), :list_entities)

  def apply_action(region_id, action) do
    GenServer.call(via(region_id), {:apply_action, action})
  end

  def advance_tick(region_id), do: GenServer.cast(via(region_id), :advance_tick)

  def despawn_entity(region_id, entity_id) do
    GenServer.call(via(region_id), {:despawn_entity, entity_id})
  end

  def snapshot(region_id), do: GenServer.call(via(region_id), :snapshot)

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    Logger.metadata(region_id: id)

    state = %{
      id: id,
      tick_seq: 0,
      prev_state_hash: <<0::256>>,
      state_hash: <<0::256>>,
      entities: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:spawn_entity, opts}, _from, state) do
    entity_id = Keyword.get(opts, :id) || new_entity_id(state.id)
    opts = Keyword.merge(opts, id: entity_id, region_id: state.id)

    case DynamicSupervisor.start_child(
           WorldHost.EntitySupervisor,
           {Entity, opts}
         ) do
      {:ok, _pid} ->
        new_state = %{state | entities: state.entities ++ [entity_id]}
        Logger.info("entity spawned: #{entity_id}")
        broadcast_spawn(state.id, entity_id)
        {:reply, {:ok, entity_id}, new_state}

      err ->
        {:reply, err, state}
    end
  end

  def handle_call(:list_entities, _from, state), do: {:reply, state.entities, state}

  def handle_call({:despawn_entity, entity_id}, _from, state) do
    if entity_id in state.entities do
      case Registry.lookup(WorldHost.EntityRegistry, entity_id) do
        [{pid, _}] -> Process.exit(pid, :shutdown)
        _ -> :ok
      end

      new_state = %{state | entities: List.delete(state.entities, entity_id)}
      broadcast_despawn(state.id, entity_id, "owner_disconnect")
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:snapshot, _from, state) do
    snapshot = %{
      region_id: state.id,
      tick_seq: state.tick_seq,
      state_hash: hex(state.state_hash),
      entities: Enum.map(state.entities, &Entity.snapshot/1)
    }

    {:reply, snapshot, state}
  end

  def handle_call({:apply_action, action}, _from, state) do
    entity_id = Map.get(action, "entity_id")

    result =
      if entity_id in state.entities do
        Entity.apply_action(entity_id, action)
      else
        {:error, %{reason: "entity_not_found", detail: entity_id}}
      end

    broadcast_action_result(state.id, action, result)
    {:reply, result, state}
  end

  @impl true
  def handle_cast(:advance_tick, state) do
    deltas = Enum.map(state.entities, &Entity.snapshot/1)

    region_hash =
      deltas
      |> Enum.map(fn d -> d.state_hash end)
      |> Enum.join("|")
      |> then(&:crypto.hash(:sha256, &1))

    new_state = %{
      state
      | tick_seq: state.tick_seq + 1,
        prev_state_hash: state.state_hash,
        state_hash: region_hash
    }

    broadcast_tick_delta(new_state, deltas)

    {:noreply, new_state}
  end

  # Sign once at the broadcast site and fan the same envelope out to all
  # subscribers. The client's verifyInboundEnvelope only checks the
  # ECDSA — no nonce cache, no timestamp window — so a shared envelope
  # is safe across the PubSub fanout.
  defp broadcast_frame(region_id, kind, payload) do
    envelope = WorldHost.SignedBundle.build(payload)
    Phoenix.PubSub.broadcast(WorldHost.PubSub, topic(region_id), {:world_frame, kind, envelope})
  end

  defp broadcast_tick_delta(state, deltas) do
    payload = %{
      kind: "tick_delta",
      region_id: state.id,
      tick: %{
        region_id: state.id,
        tick_seq: state.tick_seq,
        prev_state_hash: hex(state.prev_state_hash),
        state_hash: hex(state.state_hash),
        wall_clock_hint: System.system_time(:millisecond)
      },
      deltas: deltas
    }

    broadcast_frame(state.id, "tick_delta", payload)
  end

  defp broadcast_spawn(region_id, entity_id) do
    snapshot = Entity.snapshot(entity_id)

    payload = %{
      kind: "entity_spawn",
      region_id: region_id,
      entity: snapshot
    }

    broadcast_frame(region_id, "entity_spawn", payload)
  end

  defp broadcast_despawn(region_id, entity_id, reason) do
    payload = %{
      kind: "entity_despawn",
      region_id: region_id,
      entity_id: entity_id,
      reason: reason
    }

    broadcast_frame(region_id, "entity_despawn", payload)
  end

  defp broadcast_action_result(region_id, action, {:ok, _delta}) do
    payload = %{
      kind: "entity_action_result",
      region_id: region_id,
      action_id: Map.get(action, "action_id"),
      outcome: %{ok: true}
    }

    broadcast_frame(region_id, "entity_action_result", payload)
  end

  defp broadcast_action_result(region_id, action, {:error, detail}) do
    payload = %{
      kind: "entity_action_result",
      region_id: region_id,
      action_id: Map.get(action, "action_id"),
      outcome: Map.merge(%{ok: false}, detail)
    }

    broadcast_frame(region_id, "entity_action_result", payload)
  end

  defp new_entity_id(region_id) do
    rand = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    "#{region_id}-ent-#{rand}"
  end

  defp hex(bin), do: Base.encode16(bin, case: :lower)
end

```
