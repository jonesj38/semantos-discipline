---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/test/world_host/cell_engine_test.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.325909+00:00
---

# runtime/world-beam/apps/world_host/test/world_host/cell_engine_test.exs

```exs
defmodule WorldHost.CellEngineTest do
  @moduledoc "K1 gate enforcement via the real kernel, per-region."
  use ExUnit.Case, async: false

  alias WorldHost.{CellEngine, RegionSupervisor}

  @rid "celltest-r1"

  setup_all do
    {:ok, _} = ensure_region(@rid)
    :ok
  end

  test "LINEAR DUP → rc 22 (cannot_duplicate_linear)" do
    assert {:error, {:linearity_violation, "cannot_duplicate_linear", 22}} =
             CellEngine.check_substructural_op(@rid, :linear, :dup)
  end

  test "LINEAR DROP → rc 23 (cannot_discard_linear)" do
    assert {:error, {:linearity_violation, "cannot_discard_linear", 23}} =
             CellEngine.check_substructural_op(@rid, :linear, :drop)
  end

  test "AFFINE DUP → rc 24 (cannot_duplicate_affine)" do
    assert {:error, {:linearity_violation, "cannot_duplicate_affine", 24}} =
             CellEngine.check_substructural_op(@rid, :affine, :dup)
  end

  test "AFFINE DROP → rc 0 (accepted)" do
    assert {:ok, :accepted} = CellEngine.check_substructural_op(@rid, :affine, :drop)
  end

  test "RELEVANT DUP → rc 0 (accepted)" do
    assert {:ok, :accepted} = CellEngine.check_substructural_op(@rid, :relevant, :dup)
  end

  test "RELEVANT DROP → rc 25 (cannot_discard_relevant)" do
    assert {:error, {:linearity_violation, "cannot_discard_relevant", 25}} =
             CellEngine.check_substructural_op(@rid, :relevant, :drop)
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
