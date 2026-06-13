---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/cell_relay/lib/cell_relay/clock.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.331224+00:00
---

# runtime/world-beam/apps/cell_relay/lib/cell_relay/clock.ex

```ex
defmodule CellRelay.Clock do
  @moduledoc """
  Per-room beat-clock GenServer.

  Maintains an authoritative beat grid anchored to `origin_ms` so the
  beat schedule never drifts — each next-beat deadline is computed as
  `origin_ms + beat_index * beat_interval_ms`, not relative to when the
  previous beat handler fired.

  Clients sync to this clock via the NTP-style ping/pong in
  `CellRelay.WSHandler`. The Clock itself only knows about rooms; it
  does not touch WebSocket pids directly. Beat messages are pushed
  through `CellRelay.Room.broadcast_beat/2`.

  Lifecycle:
    * Started (idempotent) by `CellRelay.Clock.set_bpm/3` when a client
      sends `{type: "set_bpm", ...}`.
    * Stopped by `stop/1` (e.g. on last client disconnect — optional).
    * BPM can be changed live; the grid reanchors from that moment.
  """

  use GenServer
  require Logger

  # ── public API ────────────────────────────────────────────────

  @doc """
  Start (or update) the clock for `room_id`. Idempotent.
  Returns `:ok`.
  """
  def set_bpm(room_id, bpm, beats_per_bar \\ 4) do
    bpm = clamp_bpm(bpm)
    case Registry.lookup(CellRelay.ClockRegistry, room_id) do
      [{pid, _}] ->
        GenServer.cast(pid, {:set_bpm, bpm, beats_per_bar})

      [] ->
        spec = {__MODULE__, {room_id, bpm, beats_per_bar}}
        case DynamicSupervisor.start_child(CellRelay.ClockSupervisor, spec) do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
          err -> err
        end
    end
    :ok
  end

  @doc "Stop the clock for `room_id`. No-op if not running."
  def stop(room_id) do
    case Registry.lookup(CellRelay.ClockRegistry, room_id) do
      [{pid, _}] -> GenServer.stop(pid, :normal)
      [] -> :ok
    end
  end

  @doc "Current state snapshot (for the discovery endpoint)."
  def info(room_id) do
    case Registry.lookup(CellRelay.ClockRegistry, room_id) do
      [{pid, _}] -> GenServer.call(pid, :info)
      [] -> nil
    end
  end

  def start_link({room_id, bpm, beats_per_bar}) do
    GenServer.start_link(__MODULE__, {room_id, bpm, beats_per_bar},
      name: via(room_id)
    )
  end

  # ── GenServer callbacks ───────────────────────────────────────

  @impl true
  def init({room_id, bpm, beats_per_bar}) do
    now = mono_ms()
    state = %{
      room_id: room_id,
      bpm: bpm,
      beats_per_bar: beats_per_bar,
      beat_index: 0,
      origin_ms: now,
      timer: nil
    }
    Logger.info("clock room=#{room_id} bpm=#{bpm} #{beats_per_bar}/4")
    {:ok, schedule_next(state)}
  end

  @impl true
  def handle_call(:info, _from, state) do
    {:reply,
     %{
       bpm: state.bpm,
       beats_per_bar: state.beats_per_bar,
       beat: beat_number(state),
       bar: bar_number(state),
       origin_ms: state.origin_ms
     }, state}
  end

  @impl true
  def handle_cast({:set_bpm, bpm, beats_per_bar}, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    now = mono_ms()
    state = %{state |
      bpm: bpm,
      beats_per_bar: beats_per_bar,
      beat_index: 0,
      origin_ms: now,
      timer: nil
    }
    Logger.info("clock room=#{state.room_id} bpm updated → #{bpm}")
    {:noreply, schedule_next(state)}
  end

  @impl true
  def handle_info(:beat, state) do
    beat = beat_number(state)
    bar = bar_number(state)
    server_time = System.system_time(:millisecond)

    CellRelay.Room.broadcast_beat(state.room_id, %{
      "type" => "beat",
      "bpm" => state.bpm,
      "beat" => beat,
      "bar" => bar,
      "beats_per_bar" => state.beats_per_bar,
      "server_time" => server_time
    })

    state = %{state | beat_index: state.beat_index + 1}
    {:noreply, schedule_next(state)}
  end

  def handle_info(_, state), do: {:noreply, state}

  # ── helpers ───────────────────────────────────────────────────

  # Beat number within bar (1-based).
  defp beat_number(state) do
    rem(state.beat_index, state.beats_per_bar) + 1
  end

  # Bar number (1-based, increments every beats_per_bar beats).
  defp bar_number(state) do
    div(state.beat_index, state.beats_per_bar) + 1
  end

  # Schedule next beat at the absolute grid point, not relative to now.
  # This prevents cumulative drift if process scheduling is late.
  defp schedule_next(state) do
    interval = beat_interval_ms(state.bpm)
    next_deadline = state.origin_ms + (state.beat_index + 1) * interval
    delay = max(0, next_deadline - mono_ms())
    timer = Process.send_after(self(), :beat, delay)
    %{state | timer: timer}
  end

  defp beat_interval_ms(bpm), do: round(60_000 / bpm)

  # monotonic milliseconds — immune to system clock adjustments
  defp mono_ms, do: System.monotonic_time(:millisecond)

  defp via(room_id), do: {:via, Registry, {CellRelay.ClockRegistry, room_id}}

  defp clamp_bpm(bpm) when bpm < 20, do: 20
  defp clamp_bpm(bpm) when bpm > 300, do: 300
  defp clamp_bpm(bpm), do: bpm
end

```
