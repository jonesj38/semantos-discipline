---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host_web/router.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.315968+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host_web/router.ex

```ex
defmodule WorldHostWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  # API routes declared first so they're matched before the SPA wildcard
  scope "/api", WorldHostWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
    get("/regions/:id/snapshot", RegionController, :snapshot)
  end

  scope "/", WorldHostWeb do
    pipe_through(:browser)
    # SPA catch-all — serves priv/static/index.html for every browser route
    get("/", PageController, :root)
    get("/*path", PageController, :root)
  end
end

```
