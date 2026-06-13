---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/linearity.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.317495+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/linearity.ex

```ex
defmodule WorldHost.Linearity do
  @moduledoc """
  Substructural type enum mirroring `core/cell-engine/src/linearity.zig`.
  The canonical enforcement lives in the Zig K1 gate via `WorldHost.CellEngine`;
  this module remains only as a cheap pre-check for non-substructural ops.
  """

  @type t :: :linear | :affine | :relevant | :unrestricted

  def from_int(0), do: :linear
  def from_int(1), do: :affine
  def from_int(2), do: :relevant
  def from_int(_), do: :unrestricted

  def to_int(:linear), do: 0
  def to_int(:affine), do: 1
  def to_int(:relevant), do: 2
  def to_int(:unrestricted), do: 3

  def check(:linear, :dup), do: {:violation, "LINEAR cell cannot be duplicated"}
  def check(:linear, :drop), do: {:violation, "LINEAR cell cannot be dropped"}
  def check(:affine, :dup), do: {:violation, "AFFINE cell cannot be duplicated"}
  def check(:relevant, :drop), do: {:violation, "RELEVANT cell cannot be dropped"}
  def check(_lin, _op), do: :ok
end

```
