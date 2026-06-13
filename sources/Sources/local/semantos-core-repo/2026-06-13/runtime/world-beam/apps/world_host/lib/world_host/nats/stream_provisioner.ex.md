---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/nats/stream_provisioner.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.324458+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/nats/stream_provisioner.ex

```ex
defmodule WorldHost.Nats.StreamProvisioner do
  @moduledoc """
  One-shot GenServer that ensures the JetStream streams exist at boot.

  Streams created:
    - `jam`  subjects: `jam.>`  — committed jam-room cells (retention: limits, max_age: 30d)

  The stream create is idempotent (NATS returns the existing config when the
  stream already exists with compatible settings).
  """

  use GenServer
  require Logger

  @jam_stream "jam"
  @jam_subjects ["jam.>"]
  # 30 days in nanoseconds (NATS uses nanoseconds for max_age)
  @thirty_days_ns 30 * 24 * 60 * 60 * 1_000_000_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Gnat.ConnectionSupervisor establishes the connection asynchronously.
    # Defer provisioning with a small delay so the Gnat process is alive.
    Process.send_after(self(), :provision, 2_000)
    {:ok, %{attempts: 0}}
  end

  @impl true
  def handle_info(:provision, %{attempts: attempts} = state) do
    case Process.whereis(WorldHost.Nats.Conn) do
      nil when attempts < 10 ->
        # Gnat not ready yet — retry
        Process.send_after(self(), :provision, 1_000)
        {:noreply, %{state | attempts: attempts + 1}}

      nil ->
        Logger.error("NATS connection never became available after #{attempts} attempts")
        {:noreply, state}

      _pid ->
        ensure_stream(@jam_stream, @jam_subjects, @thirty_days_ns)
        {:noreply, state}
    end
  end

  defp ensure_stream(name, subjects, max_age_ns) do
    # NATS $JS.API.STREAM.CREATE takes the StreamConfig directly (not wrapped in "config")
    config = %{
      "name" => name,
      "subjects" => subjects,
      "retention" => "limits",
      "max_age" => max_age_ns,
      "storage" => "file",
      "num_replicas" => 1,
    }

    msg = Jason.encode!(config)

    case Gnat.request(WorldHost.Nats.Conn, "$JS.API.STREAM.CREATE.#{name}", msg, receive_timeout: 5_000) do
      {:ok, %{body: body}} ->
        case Jason.decode!(body) do
          %{"error" => err} ->
            Logger.warning("NATS stream #{name}: #{inspect(err)}")
          _ ->
            Logger.info("NATS stream '#{name}' provisioned (subjects: #{inspect(subjects)})")
        end

      {:error, reason} ->
        Logger.warning("NATS stream provisioning failed for '#{name}': #{inspect(reason)}")
    end
  end
end

```
