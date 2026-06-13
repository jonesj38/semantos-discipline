---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host_web/endpoint.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.316563+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host_web/endpoint.ex

```ex
defmodule WorldHostWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :world_host

  socket("/socket", WorldHostWeb.UserSocket,
    websocket: [check_origin: false],
    longpoll: false
  )

  # Unauthenticated jam-room socket — guests connect here with just a handle param
  socket("/jam/websocket", WorldHostWeb.JamSocket,
    websocket: [check_origin: false],
    longpoll: false
  )

  plug(Plug.Static,
    at: "/",
    from: :world_host,
    gzip: true,
    only: ~w(assets favicon.ico robots.txt),
    cache_control_for_etags: "public, max-age=86400"
  )

  if code_reloading? do
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(WorldHostWeb.Router)
end

```
