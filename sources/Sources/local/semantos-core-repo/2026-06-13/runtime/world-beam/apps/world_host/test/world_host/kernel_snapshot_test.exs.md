---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/test/world_host/kernel_snapshot_test.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.327404+00:00
---

# runtime/world-beam/apps/world_host/test/world_host/kernel_snapshot_test.exs

```exs
defmodule WorldHost.KernelSnapshotTest do
  @moduledoc """
  Verifies the `kernel_snapshot_state` / `kernel_restore_state` exports in
  core/cell-engine/src/main.zig. Will fail with "function not found" until
  the WASM is rebuilt with those exports (and until the pre-existing Zig
  0.15.2 compatibility issues in host.zig / executor.zig / plexus.zig are
  resolved so the build succeeds).
  """
  use ExUnit.Case, async: false

  alias WorldHost.{CellEngine, RegionSupervisor}

  @rid "snap-r1"

  setup_all do
    {:ok, _} = ensure_region(@rid)
    :ok
  end

  test "kernel_snapshot_state returns a non-zero WASM pointer" do
    wasmex = CellEngine.get_wasmex(@rid)
    {:ok, [ptr]} = Wasmex.call_function(wasmex, :kernel_snapshot_state, [])
    assert is_integer(ptr)
    assert ptr > 0
  end

  test "snapshot blob has [magic|version|length] header" do
    wasmex = CellEngine.get_wasmex(@rid)
    {:ok, mem} = Wasmex.memory(wasmex)
    {:ok, store} = Wasmex.store(wasmex)

    {:ok, [ptr]} = Wasmex.call_function(wasmex, :kernel_snapshot_state, [])
    header = Wasmex.Memory.read_binary(store, mem, ptr, 12)

    <<magic::little-32, version::little-32, length::little-32>> = header
    assert magic == 0x4E534543
    assert version == 1
    assert length > 1_000_000
    assert length < 3_000_000
  end

  test "kernel_restore_state with a just-captured blob returns 0" do
    wasmex = CellEngine.get_wasmex(@rid)
    {:ok, [ptr]} = Wasmex.call_function(wasmex, :kernel_snapshot_state, [])
    {:ok, [rc]} = Wasmex.call_function(wasmex, :kernel_restore_state, [ptr])
    assert rc == 0
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
