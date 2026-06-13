---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/test/world_host/region_test.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.327113+00:00
---

# runtime/world-beam/apps/world_host/test/world_host/region_test.exs

```exs
defmodule WorldHost.RegionTest do
  use ExUnit.Case, async: false

  alias WorldHost.{Region, Entity, Linearity, RegionSupervisor}

  test "region spawns and lists entities" do
    {:ok, _pid} = start("r-test")

    assert {:ok, "cube-x"} =
             Region.spawn_entity("r-test",
               id: "cube-x",
               linearity: :linear,
               position: {1.0, 0.0, 0.0}
             )

    assert "cube-x" in Region.list_entities("r-test")

    snap = Entity.snapshot("cube-x")
    assert snap.spatial.position == [1.0, 0.0, 0.0]
    assert snap.linearity == Linearity.to_int(:linear)
    assert snap.version == 0
  end

  test "move action advances position + version + hash chain" do
    {:ok, _} = start("r-move")

    {:ok, _} =
      Region.spawn_entity("r-move",
        id: "cube-m",
        linearity: :linear,
        position: {0.0, 0.0, 0.0}
      )

    Phoenix.PubSub.subscribe(WorldHost.PubSub, Region.topic("r-move"))

    {:ok, delta} =
      Region.apply_action("r-move", %{
        "entity_id" => "cube-m",
        "op" => "move",
        "action_id" => "a1",
        "args" => %{"delta" => [1.0, 0.0, 0.0]}
      })

    assert delta.spatial.position == [1.0, 0.0, 0.0]
    assert delta.version == 1
    assert delta.prev_hash != delta.state_hash

    assert_receive {:world_frame, %{kind: "entity_action_result", outcome: %{ok: true}}}
  end

  test "DUP on LINEAR cube is rejected by the kernel" do
    {:ok, _} = start("r-lin")
    {:ok, _} = Region.spawn_entity("r-lin", id: "cube-l", linearity: :linear)

    Phoenix.PubSub.subscribe(WorldHost.PubSub, Region.topic("r-lin"))

    assert {:error, %{reason: "linearity_violation", source: "cell-engine"}} =
             Region.apply_action("r-lin", %{
               "entity_id" => "cube-l",
               "op" => "dup",
               "action_id" => "a2"
             })

    assert_receive {:world_frame, %{kind: "entity_action_result", outcome: %{ok: false}}}
  end

  test "DUP on RELEVANT cube is allowed by the kernel" do
    {:ok, _} = start("r-rel")
    {:ok, _} = Region.spawn_entity("r-rel", id: "cube-r", linearity: :relevant)

    assert {:ok, _delta} =
             Region.apply_action("r-rel", %{
               "entity_id" => "cube-r",
               "op" => "dup",
               "action_id" => "a3"
             })
  end

  test "tick advances tick_seq and computes region state hash" do
    {:ok, _} = start("r-tick")
    {:ok, _} = Region.spawn_entity("r-tick", id: "cube-t", linearity: :linear)

    Phoenix.PubSub.subscribe(WorldHost.PubSub, Region.topic("r-tick"))

    Region.advance_tick("r-tick")

    assert_receive {:world_frame, %{kind: "tick_delta", tick: tick, deltas: deltas}}
    assert tick.tick_seq == 1
    assert length(deltas) == 1
    assert byte_size(Base.decode16!(tick.state_hash, case: :lower)) == 32
  end

  defp start(id) do
    case RegionSupervisor.start_region(id) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      err -> err
    end
  end
end

```
