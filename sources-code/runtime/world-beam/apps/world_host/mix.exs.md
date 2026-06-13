---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/mix.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.312849+00:00
---

# runtime/world-beam/apps/world_host/mix.exs

```exs
defmodule WorldHost.MixProject do
  use Mix.Project

  def project do
    [
      app: :world_host,
      version: "0.6.0",
      elixir: "~> 1.16",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      mod: {WorldHost.Application, []},
      extra_applications: [:logger, :crypto, :runtime_tools, :inets, :ssl]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:cell_relay, in_umbrella: true},
      {:phoenix, "~> 1.7"},
      {:phoenix_pubsub, "~> 2.1"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      {:wasmex, "~> 0.9"},
      # NATS JetStream client — used by WorldHost.Nats.* for event spine integration
      {:gnat, "~> 1.9"}
    ]
  end
end

```
