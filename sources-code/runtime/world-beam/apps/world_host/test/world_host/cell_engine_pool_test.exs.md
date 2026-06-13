---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/test/world_host/cell_engine_pool_test.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.326814+00:00
---

# runtime/world-beam/apps/world_host/test/world_host/cell_engine_pool_test.exs

```exs
defmodule WorldHost.CellEnginePoolTest do
  @moduledoc "Two regions have independent engines + isolated host-fn registries."
  use ExUnit.Case, async: false

  alias WorldHost.{CellEngine, Region, RegionSupervisor}

  test "each region has its own distinct CellEngine pid" do
    {:ok, _} = RegionSupervisor.start_region("pool-A")
    {:ok, _} = RegionSupervisor.start_region("pool-B")

    assert [{pid_a, _}] = Registry.lookup(WorldHost.CellEngineRegistry, "pool-A")
    assert [{pid_b, _}] = Registry.lookup(WorldHost.CellEngineRegistry, "pool-B")
    assert is_pid(pid_a)
    assert is_pid(pid_b)
    assert pid_a != pid_b
  end

  test "host functions registered in region A are invisible in region B" do
    {:ok, _} = RegionSupervisor.start_region("iso-A")
    {:ok, _} = RegionSupervisor.start_region("iso-B")

    :ok = CellEngine.register_host_fn("iso-A", "mine", fn -> 1 end)

    assert {:ok, :accepted} =
             CellEngine.execute_named_host_call("iso-A", "mine")

    assert {:error, :unknown_host_function} =
             CellEngine.execute_named_host_call("iso-B", "mine")
  end

  test "substructural enforcement is per-region" do
    {:ok, _} = RegionSupervisor.start_region("sub-A")
    {:ok, _} = RegionSupervisor.start_region("sub-B")

    assert {:error, {:linearity_violation, "cannot_duplicate_linear", 22}} =
             CellEngine.check_substructural_op("sub-A", :linear, :dup)

    assert {:error, {:linearity_violation, "cannot_duplicate_linear", 22}} =
             CellEngine.check_substructural_op("sub-B", :linear, :dup)
  end

  test "Region.apply_action on a cube routes DUP through its own engine" do
    {:ok, _} = RegionSupervisor.start_region("act-A")
    {:ok, _} = Region.spawn_entity("act-A", id: "cube-q", linearity: :linear)

    assert {:error, %{reason: "linearity_violation", source: "cell-engine"}} =
             Region.apply_action("act-A", %{
               "entity_id" => "cube-q",
               "op" => "dup",
               "action_id" => "a"
             })
  end
end

```
