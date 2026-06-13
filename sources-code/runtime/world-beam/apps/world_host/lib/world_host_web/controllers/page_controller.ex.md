---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host_web/controllers/page_controller.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.322796+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host_web/controllers/page_controller.ex

```ex
defmodule WorldHostWeb.PageController do
  use Phoenix.Controller, formats: [:html]
  import Plug.Conn

  @doc """
  Serves the Svelte jam-room SPA for all browser routes.
  Static assets (JS, CSS) are intercepted earlier by Plug.Static;
  everything else falls through to this catch-all which returns index.html.
  Path is resolved at runtime so it works correctly in Mix releases.
  """
  def root(conn, _params) do
    index = Application.app_dir(:world_host, "priv/static/index.html")
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, index)
  end
end

```
