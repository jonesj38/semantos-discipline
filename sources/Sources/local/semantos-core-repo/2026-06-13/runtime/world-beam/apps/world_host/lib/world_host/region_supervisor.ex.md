---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/region_supervisor.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.320029+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/region_supervisor.ex

```ex
defmodule WorldHost.RegionSupervisor do
  @moduledoc """
  Top-level supervisor for regions, entities, cell engines, and the tick scheduler.
  """

  use Supervisor

  def start_link(init_arg), do: Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    children = [
      {Registry, keys: :unique, name: WorldHost.RegionRegistry},
      {Registry, keys: :unique, name: WorldHost.EntityRegistry},
      {Registry, keys: :unique, name: WorldHost.CellEngineRegistry},
      {DynamicSupervisor, name: WorldHost.EntitySupervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: WorldHost.CellEngineDynSupervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: WorldHost.RegionDynSupervisor, strategy: :one_for_one},
      WorldHost.Tick
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  def start_region(id) do
    with {:ok, _engine_pid} <- start_cell_engine(id),
         {:ok, region_pid} <-
           DynamicSupervisor.start_child(
             WorldHost.RegionDynSupervisor,
             {WorldHost.Region, id: id}
           ) do
      {:ok, region_pid}
    end
  end

  defp start_cell_engine(region_id) do
    case DynamicSupervisor.start_child(
           WorldHost.CellEngineDynSupervisor,
           {WorldHost.CellEngine, region_id: region_id}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      err -> err
    end
  end
end

```
