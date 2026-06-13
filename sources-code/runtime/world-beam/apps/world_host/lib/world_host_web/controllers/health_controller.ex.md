---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host_web/controllers/health_controller.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.322190+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host_web/controllers/health_controller.ex

```ex
defmodule WorldHostWeb.HealthController do
  use Phoenix.Controller, formats: [:json]

  def show(conn, _params) do
    regions =
      Registry.select(WorldHost.RegionRegistry, [
        {{:"$1", :_, :_}, [], [:"$1"]}
      ])

    json(conn, %{
      ok: true,
      protocol_version: WorldHost.protocol_version(),
      tick_rate_hz: Application.get_env(:world_host, :tick_rate_hz),
      regions: regions
    })
  end
end

```
