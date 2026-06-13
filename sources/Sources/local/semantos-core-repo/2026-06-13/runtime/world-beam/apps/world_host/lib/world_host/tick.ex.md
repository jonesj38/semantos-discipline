---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/tick.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.320625+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/tick.ex

```ex
defmodule WorldHost.Tick do
  @moduledoc "Soft-realtime tick scheduler. Fires every 1000/tick_rate_hz ms."

  use GenServer
  require Logger

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    rate = Application.get_env(:world_host, :tick_rate_hz, 20)
    period_ms = max(1, div(1000, rate))
    Logger.info("tick scheduler started: #{rate} Hz (#{period_ms} ms period)")
    {:ok, ref} = :timer.send_interval(period_ms, :tick)
    {:ok, %{rate: rate, period_ms: period_ms, timer: ref, ticks: 0}}
  end

  @impl true
  def handle_info(:tick, state) do
    Registry.select(WorldHost.RegionRegistry, [
      {{:"$1", :_, :_}, [], [:"$1"]}
    ])
    |> Enum.each(&WorldHost.Region.advance_tick/1)

    ticks = state.ticks + 1

    if rem(ticks, state.rate * 10) == 0 do
      Logger.debug("tick #{ticks} (10s)")
    end

    {:noreply, %{state | ticks: ticks}}
  end
end

```
