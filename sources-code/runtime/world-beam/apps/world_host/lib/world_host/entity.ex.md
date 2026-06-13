---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/entity.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.319089+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/entity.ex

```ex
defmodule WorldHost.Entity do
  @moduledoc """
  One GenServer per `WorldEntity`. Holds spatial state + owner + hash chain.
  Substructural ops (DUP/DROP) are dispatched through the region's Wasmex
  kernel; MOVE and other non-substructural ops are applied directly in Elixir
  for POC speed.
  """

  use GenServer

  alias WorldHost.Linearity
  require Logger

  @type id :: String.t()

  defstruct [
    :id,
    :region_id,
    :linearity,
    :position,
    :orientation,
    :velocity,
    :controller,
    :color,
    :prev_state_hash,
    :state_hash,
    version: 0
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via(opts[:id]))
  end

  def via(id), do: {:via, Registry, {WorldHost.EntityRegistry, id}}

  def snapshot(id), do: GenServer.call(via(id), :snapshot)

  def apply_action(id, action), do: GenServer.call(via(id), {:apply_action, action})

  @impl true
  def init(opts) do
    state = %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      region_id: Keyword.fetch!(opts, :region_id),
      linearity: Keyword.get(opts, :linearity, :linear),
      position: Keyword.get(opts, :position, {0.0, 0.0, 0.0}),
      orientation: Keyword.get(opts, :orientation, {0.0, 0.0, 0.0, 1.0}),
      velocity: {0.0, 0.0, 0.0},
      controller: Keyword.get(opts, :controller, nil),
      color: Keyword.get(opts, :color, nil),
      prev_state_hash: <<0::256>>,
      state_hash: compute_initial_hash(opts),
      version: 0
    }

    Logger.metadata(entity_id: state.id, region_id: state.region_id)
    {:ok, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, to_delta(state), state}
  end

  def handle_call({:apply_action, action}, _from, state) do
    op = Map.get(action, "op") |> parse_op()
    # D-A1: the action's authorisation field is `cert_id`, sourced from
    # the verified cert_id on the socket (set by `WorldHostWeb.UserSocket.connect/3`
    # via the Verifier Sidecar — D-V3). The pre-D-V3 random-identifier
    # wire key has been removed: cert_id is now the only valid path.
    # Per `docs/spec/protocol-v0.5.md` §4.2 (BRC-52 cert format) and
    # §9.5 (Verifier Sidecar). K2 — boundary verification.
    cert_id = Map.get(action, "cert_id")

    with :ok <- owner_check(state, cert_id),
         :ok <- authoritative_check(state, op) do
      new_state = apply_op(state, op, action)
      delta = to_delta(new_state)
      {:reply, {:ok, delta}, new_state}
    else
      {:not_authoritative, detail} ->
        {:reply,
         {:error,
          %{
            reason: "not_authoritative",
            detail: detail,
            action_id: Map.get(action, "action_id")
          }}, state}

      {:violation, reason, source} ->
        {:reply,
         {:error,
          %{
            reason: "linearity_violation",
            detail: reason,
            action_id: Map.get(action, "action_id"),
            source: source
          }}, state}
    end
  end

  defp owner_check(%{controller: nil}, _cert_id), do: :ok
  defp owner_check(%{controller: c}, c) when is_binary(c), do: :ok

  defp owner_check(%{controller: owner}, other),
    do: {:not_authoritative, "entity controlled by #{owner}, action from #{inspect(other)}"}

  defp authoritative_check(state, op) when op in [:dup, :drop] do
    case WorldHost.CellEngine.check_substructural_op(state.region_id, state.linearity, op) do
      {:ok, :accepted} ->
        :ok

      {:error, {:linearity_violation, reason, code}} ->
        {:violation, "#{reason} (kernel rc=#{code})", "cell-engine"}

      {:error, {:kernel_error, code, msg}} ->
        {:violation, "kernel_error code=#{code} msg=#{msg}", "cell-engine"}
    end
  end

  defp authoritative_check(state, op) do
    case Linearity.check(state.linearity, op) do
      :ok -> :ok
      {:violation, reason} -> {:violation, reason, "elixir-prep"}
    end
  end

  defp parse_op("move"), do: :move
  defp parse_op("dup"), do: :dup
  defp parse_op("drop"), do: :drop
  defp parse_op(_), do: :unknown

  defp apply_op(state, :move, action) do
    args = Map.get(action, "args", %{})
    {dx, dy, dz} = read_vec3(args["delta"])
    {x, y, z} = state.position
    new_pos = {x + dx, y + dy, z + dz}
    advance(%{state | position: new_pos})
  end

  defp apply_op(state, :drop, _action) do
    advance(%{state | state_hash: <<0::256>>})
  end

  defp apply_op(state, _other, _action), do: advance(state)

  defp advance(state) do
    %{
      state
      | prev_state_hash: state.state_hash,
        state_hash: :crypto.hash(:sha256, :erlang.term_to_binary(state)),
        version: state.version + 1
    }
  end

  defp to_delta(state) do
    %{
      entity_id: state.id,
      spatial: %{
        position: Tuple.to_list(state.position),
        orientation: Tuple.to_list(state.orientation),
        velocity: Tuple.to_list(state.velocity)
      },
      linearity: Linearity.to_int(state.linearity),
      controller: state.controller,
      color: state.color,
      prev_hash: Base.encode16(state.prev_state_hash, case: :lower),
      state_hash: Base.encode16(state.state_hash, case: :lower),
      version: state.version
    }
  end

  defp read_vec3([x, y, z]) when is_number(x) and is_number(y) and is_number(z),
    do: {x * 1.0, y * 1.0, z * 1.0}

  defp read_vec3(_), do: {0.0, 0.0, 0.0}

  defp compute_initial_hash(opts) do
    :crypto.hash(:sha256, :erlang.term_to_binary(opts))
  end
end

```
