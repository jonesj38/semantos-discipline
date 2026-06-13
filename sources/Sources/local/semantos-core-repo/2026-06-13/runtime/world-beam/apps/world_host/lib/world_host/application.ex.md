---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/application.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.318176+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/application.ex

```ex
defmodule WorldHost.Application do
  @moduledoc false
  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    # `:inets` (for `:httpc`) and `:ssl` are required by
    # `WorldHost.VerifierClient.Http` to reach the per-node Verifier
    # Sidecar (D-V3) over loopback HTTP. Started here rather than
    # listed in `extra_applications` so we can tolerate `:already_started`
    # cleanly under hot-reload and umbrella supervision.
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    # D-A1 — boot ordering. Wait for the Verifier Sidecar's `/healthz`
    # to return 200 before the Phoenix Endpoint starts accepting
    # sockets. Without this, the first round of WebSocket connects on a
    # cold-started node fail with `verifier_unreachable` because the
    # sidecar process hasn't bound its port yet.
    #
    # Docker Compose still gives ordering via `depends_on`; this gate
    # is for the non-Docker dev path (`mix phx.server` against a
    # `bun run` sidecar).
    #
    # Skipping the gate is supported for tests and offline boots via
    # `config :world_host, :wait_for_sidecar, false`.
    case maybe_wait_for_sidecar() do
      :ok ->
        start_supervisor()

      {:error, :timeout} ->
        Logger.error(
          "verifier sidecar /healthz never returned 200 — refusing to boot. " <>
            "Confirm the sidecar is running (per-node default 127.0.0.1:8787) " <>
            "or set `config :world_host, :wait_for_sidecar, false` for offline boot."
        )

        {:error, :verifier_sidecar_unavailable}
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    WorldHostWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_wait_for_sidecar do
    if Application.get_env(:world_host, :wait_for_sidecar, true) do
      WorldHost.SidecarHealthcheck.wait_for_ready()
    else
      :ok
    end
  end

  defp start_supervisor do
    # Prime the per-boot host identity (ephemeral secp256k1 key +
    # self-signed BRC-52 cert). Eagerly generated at boot so the first
    # outbound frame doesn't pay the keygen cost and so any :crypto
    # config issues surface here, not on the hot path.
    _ = WorldHost.HostIdentity.get()

    nats_enabled = Application.get_env(:world_host, :nats_enabled, true)

    children =
      [
        {Phoenix.PubSub, name: WorldHost.PubSub},
        WorldHostWeb.Presence,
        WorldHost.RegionSupervisor,
        WorldHostWeb.Endpoint,
        {Task, fn -> WorldHost.Bootstrap.start_demo_region() end},
      ] ++
        if nats_enabled do
          [WorldHost.Nats.Supervisor]
        else
          []
        end

    opts = [strategy: :one_for_one, name: WorldHost.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("world_host started (protocol v#{WorldHost.protocol_version()})")
        {:ok, pid}

      err ->
        err
    end
  end
end

```
