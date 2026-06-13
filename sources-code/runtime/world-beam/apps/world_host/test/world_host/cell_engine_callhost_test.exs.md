---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/test/world_host/cell_engine_callhost_test.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.326218+00:00
---

# runtime/world-beam/apps/world_host/test/world_host/cell_engine_callhost_test.exs

```exs
defmodule WorldHost.CellEngineCallHostTest do
  @moduledoc "OP_CALLHOST end-to-end: name read from WASM memory, runtime dispatch."
  use ExUnit.Case, async: false

  alias WorldHost.{CellEngine, RegionSupervisor}

  @rid "callhost-r1"

  setup_all do
    {:ok, _} = ensure_region(@rid)
    :ok
  end

  setup do
    :ok = CellEngine.clear_host_functions(@rid)
    :ok
  end

  test "dispatches to a registered host function by name" do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    :ok =
      CellEngine.register_host_fn(@rid, "inc", fn ->
        Agent.update(agent, fn xs -> [:called | xs] end)
        1
      end)

    assert {:ok, :accepted} = CellEngine.execute_named_host_call(@rid, "inc")
    assert Agent.get(agent, & &1) == [:called]
  end

  test "unknown function name returns unknown_host_function error" do
    assert {:error, :unknown_host_function} =
             CellEngine.execute_named_host_call(@rid, "xq-not-a-real-function-zzz")
  end

  test "multiple registered functions dispatch independently" do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    :ok =
      CellEngine.register_host_fn(@rid, "alpha", fn ->
        Agent.update(agent, fn xs -> [:alpha | xs] end)
        1
      end)

    :ok =
      CellEngine.register_host_fn(@rid, "beta", fn ->
        Agent.update(agent, fn xs -> [:beta | xs] end)
        1
      end)

    assert {:ok, :accepted} = CellEngine.execute_named_host_call(@rid, "beta")
    assert {:ok, :accepted} = CellEngine.execute_named_host_call(@rid, "alpha")
    assert {:ok, :accepted} = CellEngine.execute_named_host_call(@rid, "beta")

    assert Agent.get(agent, & &1) == [:beta, :alpha, :beta]
  end

  defp ensure_region(id) do
    case RegionSupervisor.start_region(id) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      err -> err
    end
  end
end

```
