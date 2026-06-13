---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/sidecar_healthcheck.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.321500+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/sidecar_healthcheck.ex

```ex
defmodule WorldHost.SidecarHealthcheck do
  @moduledoc """
  D-A1 — Boot-ordering helper that waits for the Verifier Sidecar's
  `/healthz` endpoint to return 200 before the Phoenix Endpoint starts
  accepting WebSocket sockets.

  ## Why

  D-V3 wired connect/3 to the sidecar over loopback HTTP. If the
  sidecar isn't up yet, every connect fails closed with
  `verifier_unreachable`, which makes a freshly-booted node look broken
  to clients. Docker Compose handles ordering via `depends_on`; the
  non-Docker dev path (`mix phx.server` against a `bun run` sidecar)
  has no such ordering primitive, so this module fills the gap.

  ## Behaviour

  `wait_for_ready/1` polls the configured URL with exponential backoff:

    * Initial interval 100ms; doubled each attempt up to 1_000ms.
    * Total timeout configurable, default 30 000ms.
    * Returns `:ok` on first 200 response.
    * Returns `{:error, :timeout}` if the timeout elapses without
      ever seeing a 200; the caller decides whether to abort boot.

  The HTTP client is pluggable via `config :world_host, :sidecar_http_client, ...`
  so tests inject a deterministic mock instead of opening sockets.

  ## Configuration

      # config/config.exs (production default)
      config :world_host,
        verifier_sidecar_url: "http://127.0.0.1:8787",
        sidecar_healthcheck_timeout_ms: 30_000

      # config/test.exs
      config :world_host, :sidecar_http_client, WorldHost.SidecarHealthcheck.MockClient

  ## Spec source

    - `docs/spec/protocol-v0.5.md` §9.5 (Verifier Sidecar)
    - `runtime/verifier-sidecar/README.md` (`/healthz` contract)
  """

  require Logger

  @default_timeout_ms 30_000
  @initial_interval_ms 100
  @max_interval_ms 1_000

  @typedoc """
  HTTP client behaviour: a single function that takes a URL and returns
  `{:ok, status, body}` or `{:error, reason}`. Production uses
  `:httpc`; tests inject a mock.
  """
  @type http_client :: module()

  @callback get(String.t()) ::
              {:ok, non_neg_integer(), binary()} | {:error, term()}

  @doc """
  Block until the sidecar `/healthz` returns 200, or `timeout_ms`
  elapses. Polls with exponential backoff capped at 1_000ms between
  attempts.

  Options:

    * `:url` — absolute `/healthz` URL. Defaults to
      `Application.get_env(:world_host, :verifier_sidecar_url)` ++
      `"/healthz"`, falling back to `http://127.0.0.1:8787/healthz`.

    * `:timeout_ms` — total wait budget. Defaults to
      `Application.get_env(:world_host, :sidecar_healthcheck_timeout_ms, 30_000)`.

    * `:client` — module implementing `c:get/1`. Defaults to
      `Application.get_env(:world_host, :sidecar_http_client, WorldHost.SidecarHealthcheck.HttpcClient)`.

    * `:now` — `&System.monotonic_time/1`-style 0-arg fn returning
      milliseconds; lets tests freeze time.

  ## Returns

    - `:ok` — sidecar healthy (`/healthz` returned 200).
    - `{:error, :timeout}` — `timeout_ms` elapsed without a 200.
  """
  @spec wait_for_ready(keyword()) :: :ok | {:error, :timeout}
  def wait_for_ready(opts \\ []) do
    url = Keyword.get(opts, :url, default_url())
    timeout_ms = Keyword.get(opts, :timeout_ms, default_timeout_ms())
    client = Keyword.get(opts, :client, default_client())
    now_fn = Keyword.get(opts, :now, fn -> System.monotonic_time(:millisecond) end)
    sleep_fn = Keyword.get(opts, :sleep, &Process.sleep/1)

    deadline = now_fn.() + timeout_ms

    poll_loop(url, client, now_fn, sleep_fn, deadline, @initial_interval_ms, 0)
  end

  @doc """
  Default URL — concatenation of `:verifier_sidecar_url` and `/healthz`.
  Falls back to the D-V2 default `http://127.0.0.1:8787/healthz`.
  """
  @spec default_url() :: String.t()
  def default_url do
    base = Application.get_env(:world_host, :verifier_sidecar_url, "http://127.0.0.1:8787")
    base <> "/healthz"
  end

  @doc """
  Default timeout — `:sidecar_healthcheck_timeout_ms` or 30_000ms.
  """
  @spec default_timeout_ms() :: non_neg_integer()
  def default_timeout_ms do
    Application.get_env(:world_host, :sidecar_healthcheck_timeout_ms, @default_timeout_ms)
  end

  @doc """
  Default HTTP client — `:sidecar_http_client` or the production
  `:httpc`-based implementation.
  """
  @spec default_client() :: http_client()
  def default_client do
    Application.get_env(:world_host, :sidecar_http_client, __MODULE__.HttpcClient)
  end

  # ── Polling loop ─────────────────────────────────────────────────────────────

  defp poll_loop(url, client, now_fn, sleep_fn, deadline, interval_ms, attempt) do
    case client.get(url) do
      {:ok, 200, _body} ->
        Logger.info(
          "verifier sidecar /healthz returned 200 at #{url} (after #{attempt + 1} attempt(s))"
        )

        :ok

      {:ok, status, _body} ->
        Logger.debug(
          "verifier sidecar /healthz at #{url} returned status #{status}; retrying"
        )

        backoff(url, client, now_fn, sleep_fn, deadline, interval_ms, attempt)

      {:error, reason} ->
        Logger.debug(
          "verifier sidecar /healthz at #{url} unreachable: #{inspect(reason)}; retrying"
        )

        backoff(url, client, now_fn, sleep_fn, deadline, interval_ms, attempt)
    end
  end

  defp backoff(url, client, now_fn, sleep_fn, deadline, interval_ms, attempt) do
    now = now_fn.()
    remaining = deadline - now

    if remaining <= 0 do
      Logger.error(
        "verifier sidecar /healthz at #{url} did not return 200 within #{default_timeout_ms()}ms (#{attempt + 1} attempt(s))"
      )

      {:error, :timeout}
    else
      sleep_for = min(interval_ms, remaining)
      sleep_fn.(sleep_for)

      next_interval = min(interval_ms * 2, @max_interval_ms)
      poll_loop(url, client, now_fn, sleep_fn, deadline, next_interval, attempt + 1)
    end
  end

  # ── Production HTTP client ───────────────────────────────────────────────────

  defmodule HttpcClient do
    @moduledoc """
    Production HTTP client for the sidecar healthcheck. Uses OTP's
    `:httpc` (no new dep), matching `WorldHost.VerifierClient.Http`.
    """

    @behaviour WorldHost.SidecarHealthcheck

    @impl true
    def get(url) do
      url_charlist = String.to_charlist(url)

      http_options = [{:timeout, 1_000}, {:connect_timeout, 500}]
      options = [{:body_format, :binary}]

      case :httpc.request(:get, {url_charlist, []}, http_options, options) do
        {:ok, {{_, status, _}, _headers, body}} -> {:ok, status, body}
        {:error, reason} -> {:error, reason}
      end
    end
  end
end

```
