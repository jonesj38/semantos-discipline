---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/cell_relay/mix.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.313576+00:00
---

# runtime/world-beam/apps/cell_relay/mix.exs

```exs
defmodule CellRelay.MixProject do
  use Mix.Project

  def project do
    [
      app: :cell_relay,
      version: "0.6.0",
      elixir: "~> 1.16",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {CellRelay.Application, []},
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"}
    ]
  end
end

```
