---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host_web/presence.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.317159+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host_web/presence.ex

```ex
defmodule WorldHostWeb.Presence do
  @moduledoc """
  Phoenix Presence for jam-room guest tracking.

  Tracks connected guests per `jam:<room_id>` topic.
  Metadata shape: `%{handle: string, joined_at: unix_ms}`.

  Used by `JamChannel.join/3` to broadcast `presence_state` and
  `presence_diff` events so clients can render the peer rail.
  """

  use Phoenix.Presence,
    otp_app: :world_host,
    pubsub_server: WorldHost.PubSub
end

```
