---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host_web/error_json.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.316859+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host_web/error_json.ex

```ex
defmodule WorldHostWeb.ErrorJSON do
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end

```
