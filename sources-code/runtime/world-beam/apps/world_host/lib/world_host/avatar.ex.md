---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/avatar.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.321215+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/avatar.ex

```ex
defmodule WorldHost.Avatar do
  @moduledoc """
  Avatar lifecycle: spawn a LINEAR cube owned by a session on channel join,
  despawn it on disconnect. Ownership is enforced in
  `WorldHost.Entity.handle_call({:apply_action, ...})` via the session_id
  field on the action.
  """

  alias WorldHost.Region

  def entity_id_for(region_id, session_id) do
    "#{region_id}-avatar-#{session_id}"
  end

  def spawn_for_session(region_id, session_id) do
    entity_id = entity_id_for(region_id, session_id)

    opts = [
      id: entity_id,
      linearity: :linear,
      controller: session_id,
      position: starting_position(session_id),
      color: starting_color(session_id)
    ]

    case Region.spawn_entity(region_id, opts) do
      {:ok, ^entity_id} -> {:ok, entity_id}
      {:ok, other_id} -> {:ok, other_id}
      {:error, {:already_started, _pid}} -> {:ok, entity_id}
      err -> err
    end
  end

  def despawn_for_session(region_id, session_id) do
    entity_id = entity_id_for(region_id, session_id)
    Region.despawn_entity(region_id, entity_id)
  end

  defp starting_position(session_id) do
    <<a, b, _rest::binary>> = :crypto.hash(:sha256, session_id)
    x = (a - 128) / 25.6
    z = (b - 128) / 25.6
    {x, 0.5, z}
  end

  # 12-colour palette indexed by the first byte of the session-id hash.
  # Deliberately distinct from LINEAR's default 0x2cb2a5 (teal) so seeded
  # NPC cubes stay visually separable from avatars.
  defp starting_color(session_id) do
    <<h, _::binary>> = :crypto.hash(:sha256, session_id)

    case rem(h, 12) do
      0 -> 0xE74C3C
      1 -> 0xF39C12
      2 -> 0xF1C40F
      3 -> 0x9CCC65
      4 -> 0x3498DB
      5 -> 0x9B59B6
      6 -> 0xE91E63
      7 -> 0xFF6F61
      8 -> 0xFFE66D
      9 -> 0xC44569
      10 -> 0xFB923C
      11 -> 0x6366F1
    end
  end
end

```
