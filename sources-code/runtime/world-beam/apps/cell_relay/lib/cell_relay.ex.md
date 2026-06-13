---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/cell_relay/lib/cell_relay.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.329657+00:00
---

# runtime/world-beam/apps/cell_relay/lib/cell_relay.ex

```ex
defmodule CellRelay do
  @moduledoc """
  cell-relay-beam — Elixir/OTP implementation of the cell-relay
  protocol (`@semantos/cell-relay`). One supervised GenServer per room,
  per-room JSONL persistence, WebSocket broadcast for live commits.

  Drop-in compatible with the Bun dev variant
  (`apps/demo-collab-versioning/server.ts`) — same wire protocol,
  same JSONL on-disk format, same port (`5178`). Originally written
  as `jam-beam` for the jam-room sovereign-node POC; renamed to
  reflect that the role is generic cell-stream relay, not jam-specific.

  Run with:

      mix deps.get
      mix run --no-halt

  The browser jam-room (`apps/world-apps/jam-room/`, served on `:5180`) connects
  unchanged. The release pipeline (`tools/release/`) reads/appends
  the same JSONL files for `release.kernel.*` rooms.
  """
end

```
