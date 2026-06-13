---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/mix.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.031955+00:00
---

# runtime/world-beam/mix.exs

```exs
defmodule WorldBeam.MixProject do
  use Mix.Project

  @version "0.6.0"

  def project do
    [
      apps_path: "apps",
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      aliases: aliases()
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp releases do
    [
      # Full release: Phoenix world + cell relay in one BEAM node.
      # Deployed as a systemd service on the VPS (can reach NATS at 127.0.0.1:4222).
      world: [
        applications: [world_host: :permanent, cell_relay: :permanent],
        include_executables_for: [:unix],
        steps: [:assemble, :tar]
      ],
      # Lightweight relay-only release — no Phoenix, no world_host.
      # Used by the jam-room Docker image on the VPS.
      relay: [
        applications: [cell_relay: :permanent],
        include_executables_for: [:unix],
        steps: [:assemble, :tar]
      ]
    ]
  end

  defp aliases do
    [
      # Build the Zig cell-engine WASM and copy into world_host priv/.
      # Usage: mix wasm
      wasm: ["cmd --cd ../../core/cell-engine zig build", &copy_wasm/1],
      # Run all child app tests.
      test: ["cmd mix test --no-start"]
    ]
  end

  defp copy_wasm(_args) do
    src = Path.expand("../../core/cell-engine/zig-out/bin/cell-engine.wasm", __DIR__)
    dst = Path.expand("apps/world_host/priv/cell-engine.wasm", __DIR__)
    File.mkdir_p!(Path.dirname(dst))

    case File.copy(src, dst) do
      {:ok, bytes} ->
        Mix.shell().info("wasm: copied cell-engine.wasm (#{bytes} bytes) → apps/world_host/priv/")

      {:error, reason} ->
        Mix.raise("wasm: failed to copy #{src} → #{dst}: #{inspect(reason)}")
    end
  end
end

```
