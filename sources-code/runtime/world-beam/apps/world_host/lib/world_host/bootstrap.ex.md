---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/bootstrap.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.320333+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/bootstrap.ex

```ex
defmodule WorldHost.Bootstrap do
  @moduledoc "Boot-time demo setup — one region with N LINEAR cubes."

  require Logger

  def start_demo_region do
    if Application.get_env(:world_host, :bootstrap_demo_region, true) do
      do_start_demo_region()
    else
      :ok
    end
  end

  defp do_start_demo_region do
    Process.sleep(250)

    region_id = Application.get_env(:world_host, :demo_region_id, "region-0001")
    cube_count = Application.get_env(:world_host, :demo_cube_count, 3)

    case WorldHost.RegionSupervisor.start_region(region_id) do
      {:ok, _pid} ->
        Logger.info("demo region #{region_id} up")
        seed_cubes(region_id, cube_count)

      {:error, {:already_started, _pid}} ->
        Logger.info("demo region #{region_id} already running")

      err ->
        Logger.error("failed to start demo region: #{inspect(err)}")
    end
  end

  defp seed_cubes(region_id, n) do
    for i <- 1..n do
      {:ok, id} =
        WorldHost.Region.spawn_entity(region_id,
          id: "cube-#{i}",
          linearity: :linear,
          position: {:rand.uniform() * 10 - 5, 0.5, :rand.uniform() * 10 - 5}
        )

      Logger.info("seeded cube #{id}")
    end
  end
end

```
