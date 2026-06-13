---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/cell_relay/lib/cell_relay/application.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.330006+00:00
---

# runtime/world-beam/apps/cell_relay/lib/cell_relay/application.ex

```ex
defmodule CellRelay.Application do
  @moduledoc """
  OTP supervision tree for the cell-relay BEAM runtime.

  Per-room state lives in a `CellRelay.Room` GenServer, addressable via
  `CellRelay.Registry`. The HTTP/WebSocket front-end is a Cowboy
  listener bound on port `:port` (default 5178), drop-in compatible
  with the Bun dev variant (`apps/demo-collab-versioning/server.ts`)
  so existing clients don't need to change.

  Topology:

      CellRelay.Application
      ├── CellRelay.Registry         (room_id → Room pid)
      ├── CellRelay.ClockRegistry    (room_id → Clock pid)
      ├── CellRelay.RoomSupervisor   (DynamicSupervisor of CellRelay.Room)
      ├── CellRelay.ClockSupervisor  (DynamicSupervisor of CellRelay.Clock)
      └── Plug.Cowboy listener       (CellRelay.Endpoint + CellRelay.WSHandler)
  """
  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:cell_relay, :port, 5178)

    children = [
      {Registry, keys: :unique, name: CellRelay.Registry},
      {Registry, keys: :unique, name: CellRelay.ClockRegistry},
      {DynamicSupervisor, name: CellRelay.RoomSupervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: CellRelay.ClockSupervisor, strategy: :one_for_one},
      {Plug.Cowboy,
       scheme: :http,
       plug: CellRelay.Endpoint,
       options: [
         port: port,
         dispatch: dispatch()
       ]}
    ]

    IO.puts("cell-relay-beam listening on :#{port}")
    IO.puts("  rooms persisted at: #{Application.get_env(:cell_relay, :data_dir)}/<roomId>.jsonl")

    Supervisor.start_link(children, strategy: :one_for_one, name: CellRelay.Supervisor)
  end

  # Cowboy dispatch: route the root path to the WebSocket handler
  # (clients connect with a bare `ws://host:5178/?room=...&as=...`)
  # and everything else to the Plug pipeline.
  defp dispatch do
    [
      {:_,
       [
         {"/", CellRelay.WSHandler, []},
         {:_, Plug.Cowboy.Handler, {CellRelay.Endpoint, []}}
       ]}
    ]
  end
end

```
