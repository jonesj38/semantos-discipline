---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host_web/jam_socket.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.315679+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host_web/jam_socket.ex

```ex
defmodule WorldHostWeb.JamSocket do
  @moduledoc """
  Unauthenticated Phoenix WebSocket for the public jam room.

  Unlike `UserSocket` (which enforces BRC-100 cert auth at K2),
  the jam socket accepts any guest with just a `handle` param.

  Mounted at `/jam/websocket` in `Endpoint`.

  Socket assigns set on connect:
    - `:handle`  — display name (e.g. "guest-a3f2c1")
    - `:guest_id` — server-assigned UUID (prevents spoofing handles)
  """

  use Phoenix.Socket

  channel("jam:*", WorldHostWeb.JamChannel)

  @impl true
  def connect(params, socket, _connect_info) do
    handle =
      case Map.get(params, "handle") do
        h when is_binary(h) and byte_size(h) > 0 -> String.slice(h, 0, 32)
        _ -> "guest-#{:crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)}"
      end

    guest_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

    socket =
      socket
      |> assign(:handle, handle)
      |> assign(:guest_id, guest_id)

    {:ok, socket}
  end

  @impl true
  def id(socket), do: "jam_socket:#{socket.assigns.guest_id}"
end

```
