---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/test/world_host/avatar_test.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.327999+00:00
---

# runtime/world-beam/apps/world_host/test/world_host/avatar_test.exs

```exs
defmodule WorldHost.AvatarTest do
  @moduledoc """
  Per-session avatar lifecycle + ownership-gated actions.

  D-A1 — the action's authorisation wire key is `cert_id` (sourced from
  the verified cert_id on the socket; see
  `WorldHostWeb.UserSocket.connect/3` via the Verifier Sidecar). The
  pre-D-V3 random-identifier wire key is removed.
  """
  use ExUnit.Case, async: false

  alias WorldHost.{Avatar, Entity, Region, RegionSupervisor}

  test "spawn_for_session creates a LINEAR avatar owned by the session" do
    {:ok, _} = ensure_region("av-r1")

    {:ok, entity_id} = Avatar.spawn_for_session("av-r1", "sess-alpha")

    assert entity_id == Avatar.entity_id_for("av-r1", "sess-alpha")
    assert entity_id in Region.list_entities("av-r1")

    snap = Entity.snapshot(entity_id)
    assert snap.linearity == WorldHost.Linearity.to_int(:linear)
    assert snap.controller == "sess-alpha"
  end

  test "despawn_for_session removes the avatar" do
    {:ok, _} = ensure_region("av-r2")

    {:ok, entity_id} = Avatar.spawn_for_session("av-r2", "sess-beta")
    :ok = Avatar.despawn_for_session("av-r2", "sess-beta")

    refute entity_id in Region.list_entities("av-r2")
  end

  test "action from non-owner cert_id is rejected with not_authoritative" do
    {:ok, _} = ensure_region("av-r3")
    {:ok, entity_id} = Avatar.spawn_for_session("av-r3", "owner-sess")

    result =
      Region.apply_action("av-r3", %{
        "entity_id" => entity_id,
        "op" => "move",
        "args" => %{"delta" => [1, 0, 0]},
        "action_id" => "x",
        "cert_id" => "intruder-sess"
      })

    assert {:error, %{reason: "not_authoritative"}} = result
  end

  test "action from the owner cert_id is accepted" do
    {:ok, _} = ensure_region("av-r4")
    {:ok, entity_id} = Avatar.spawn_for_session("av-r4", "owner-sess")

    pre = Entity.snapshot(entity_id)
    [pre_x, pre_y, pre_z] = pre.spatial.position

    {:ok, delta} =
      Region.apply_action("av-r4", %{
        "entity_id" => entity_id,
        "op" => "move",
        "args" => %{"delta" => [1, 0, 0]},
        "action_id" => "x",
        "cert_id" => "owner-sess"
      })

    [post_x, post_y, post_z] = delta.spatial.position
    assert_in_delta post_x, pre_x + 1.0, 1.0e-9
    assert_in_delta post_y, pre_y, 1.0e-9
    assert_in_delta post_z, pre_z, 1.0e-9
  end

  test "non-avatar entity (no controller) accepts actions from any cert_id" do
    {:ok, _} = ensure_region("av-r5")
    {:ok, _} = Region.spawn_entity("av-r5", id: "npc-cube", linearity: :linear)

    result =
      Region.apply_action("av-r5", %{
        "entity_id" => "npc-cube",
        "op" => "move",
        "args" => %{"delta" => [1, 0, 0]},
        "action_id" => "x",
        "cert_id" => "any-sess"
      })

    assert {:ok, _} = result
  end

  defp ensure_region(id) do
    case RegionSupervisor.start_region(id) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      err -> err
    end
  end
end

```
