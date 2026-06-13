---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host_web/controllers/region_controller.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.322492+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host_web/controllers/region_controller.ex

```ex
defmodule WorldHostWeb.RegionController do
  use Phoenix.Controller, formats: [:json]

  def snapshot(conn, %{"id" => region_id}) do
    try do
      snap = WorldHost.Region.snapshot(region_id)
      json(conn, snap)
    catch
      :exit, _ ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "region_not_found", region_id: region_id})
    end
  end
end

```
