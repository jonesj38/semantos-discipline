---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/cell_relay/lib/cell_relay/endpoint.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.330920+00:00
---

# runtime/world-beam/apps/cell_relay/lib/cell_relay/endpoint.ex

```ex
defmodule CellRelay.Endpoint do
  @moduledoc """
  Plug pipeline for the HTTP side of the BEAM region:

    * `GET /health`  → all rooms with cell + client counts
    * `GET /rooms`   → list of rooms with subscribers (discovery)
    * `OPTIONS *`    → CORS preflight

  WebSocket upgrades on `/` are handled by `CellRelay.WSHandler`, dispatched
  in `CellRelay.Application`. The HTTP responses send `access-control-*`
  headers so the browser jam-room (served on :5180) can poll
  cross-origin without proxying.
  """
  use Plug.Router

  plug :match
  plug :cors
  plug :dispatch

  defp cors(conn, _opts) do
    conn
    |> Plug.Conn.put_resp_header("access-control-allow-origin", "*")
    |> Plug.Conn.put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
    |> Plug.Conn.put_resp_header("access-control-allow-headers", "content-type")
  end

  options _ do
    send_resp(conn, 204, "")
  end

  get "/health" do
    rooms =
      Registry.select(CellRelay.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
      |> Enum.map(fn id ->
        try do
          CellRelay.Room.stats(id)
        catch
          :exit, _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    send_json(conn, %{rooms: rooms})
  end

  get "/rooms" do
    list =
      Registry.select(CellRelay.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
      |> Enum.map(fn id ->
        try do
          CellRelay.Room.stats(id)
        catch
          :exit, _ -> nil
        end
      end)
      |> Enum.reject(&(is_nil(&1) or &1.clients == 0))

    send_json(conn, list)
  end

  match _ do
    send_resp(conn, 200, "semantos cell-relay-beam — connect via WebSocket\n")
  end

  defp send_json(conn, body) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end
end

```
