---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host_web.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.313972+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host_web.ex

```ex
defmodule WorldHostWeb do
  @moduledoc false

  def channel do
    quote do
      use Phoenix.Channel
      require Logger
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end

```
