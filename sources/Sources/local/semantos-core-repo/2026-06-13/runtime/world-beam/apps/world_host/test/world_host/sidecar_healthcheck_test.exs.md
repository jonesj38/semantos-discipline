---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/test/world_host/sidecar_healthcheck_test.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.326520+00:00
---

# runtime/world-beam/apps/world_host/test/world_host/sidecar_healthcheck_test.exs

```exs
defmodule WorldHost.SidecarHealthcheckTest do
  @moduledoc """
  D-A1 — `WorldHost.SidecarHealthcheck` boot-ordering helper.

  Verifies the polling/timeout/exponential-backoff contract without
  opening real sockets: the HTTP client is mocked via the `:client`
  option, time is frozen via `:now` + `:sleep`, and the test asserts
  on the recorded sleep durations and call counts.

  Spec source: `docs/spec/protocol-v0.5.md` §9.5 (Verifier Sidecar);
               `runtime/verifier-sidecar/README.md` (`/healthz`).
  """

  use ExUnit.Case, async: true

  alias WorldHost.SidecarHealthcheck

  # ── Test client: feeds canned responses from a queue ─────────────────────────

  defmodule QueueClient do
    @behaviour WorldHost.SidecarHealthcheck

    def start(responses) do
      pid = self()
      Process.put({__MODULE__, pid}, responses)
      Process.put({__MODULE__, pid, :calls}, 0)
      :ok
    end

    def call_count do
      Process.get({__MODULE__, self(), :calls}, 0)
    end

    @impl true
    def get(_url) do
      pid = self()
      key = {__MODULE__, pid}
      [head | rest] = Process.get(key)
      Process.put(key, rest)
      Process.put({__MODULE__, pid, :calls}, Process.get({__MODULE__, pid, :calls}, 0) + 1)
      head
    end
  end

  # ── Mock clock + sleep that record into the process dict ────────────────────

  setup do
    Process.put(:fake_now_ms, 0)
    Process.put(:slept, [])
    :ok
  end

  defp now_fn do
    fn -> Process.get(:fake_now_ms, 0) end
  end

  defp sleep_fn do
    fn ms ->
      Process.put(:slept, Process.get(:slept, []) ++ [ms])
      Process.put(:fake_now_ms, Process.get(:fake_now_ms, 0) + ms)
      :ok
    end
  end

  # ── Tests ────────────────────────────────────────────────────────────────────

  test "returns :ok immediately when /healthz responds 200 on the first call" do
    QueueClient.start([{:ok, 200, "OK"}])

    assert :ok =
             SidecarHealthcheck.wait_for_ready(
               url: "http://test/healthz",
               client: QueueClient,
               timeout_ms: 5_000,
               now: now_fn(),
               sleep: sleep_fn()
             )

    assert QueueClient.call_count() == 1
    assert Process.get(:slept) == []
  end

  test "polls with exponential backoff until /healthz returns 200" do
    QueueClient.start([
      {:error, :econnrefused},
      {:error, :econnrefused},
      {:ok, 503, ""},
      {:ok, 200, "OK"}
    ])

    assert :ok =
             SidecarHealthcheck.wait_for_ready(
               url: "http://test/healthz",
               client: QueueClient,
               timeout_ms: 30_000,
               now: now_fn(),
               sleep: sleep_fn()
             )

    assert QueueClient.call_count() == 4

    # Backoff schedule: 100, 200, 400 — three sleeps before the 4th call
    # finally returns 200. Cap is 1_000ms; we don't reach it here.
    assert Process.get(:slept) == [100, 200, 400]
  end

  test "exponential backoff caps at 1_000ms between attempts" do
    # Five errors then 200: sleeps should be 100, 200, 400, 800, 1_000 (capped).
    QueueClient.start([
      {:error, :econnrefused},
      {:error, :econnrefused},
      {:error, :econnrefused},
      {:error, :econnrefused},
      {:error, :econnrefused},
      {:ok, 200, "OK"}
    ])

    assert :ok =
             SidecarHealthcheck.wait_for_ready(
               url: "http://test/healthz",
               client: QueueClient,
               timeout_ms: 30_000,
               now: now_fn(),
               sleep: sleep_fn()
             )

    assert Process.get(:slept) == [100, 200, 400, 800, 1_000]
    assert QueueClient.call_count() == 6
  end

  test "returns {:error, :timeout} when /healthz never responds 200" do
    # Always-error client; timeout after 1_000ms (well short of normal
    # 30s default).
    QueueClient.start(List.duplicate({:error, :econnrefused}, 100))

    assert {:error, :timeout} =
             SidecarHealthcheck.wait_for_ready(
               url: "http://test/healthz",
               client: QueueClient,
               timeout_ms: 1_000,
               now: now_fn(),
               sleep: sleep_fn()
             )

    # Sleeps should be capped at the remaining-time budget on the final
    # attempt. With the 100/200/400/300 schedule the total exactly
    # equals 1_000ms.
    total = Process.get(:slept) |> Enum.sum()
    assert total == 1_000
  end

  test "non-200 status from /healthz is treated as 'not ready' and retried" do
    QueueClient.start([
      {:ok, 503, "Service Unavailable"},
      {:ok, 200, "OK"}
    ])

    assert :ok =
             SidecarHealthcheck.wait_for_ready(
               url: "http://test/healthz",
               client: QueueClient,
               timeout_ms: 5_000,
               now: now_fn(),
               sleep: sleep_fn()
             )

    assert QueueClient.call_count() == 2
    assert Process.get(:slept) == [100]
  end

  test "default_url derives /healthz from :verifier_sidecar_url config" do
    prior = Application.get_env(:world_host, :verifier_sidecar_url)
    Application.put_env(:world_host, :verifier_sidecar_url, "http://example.test:9999")

    try do
      assert SidecarHealthcheck.default_url() == "http://example.test:9999/healthz"
    after
      if prior do
        Application.put_env(:world_host, :verifier_sidecar_url, prior)
      else
        Application.delete_env(:world_host, :verifier_sidecar_url)
      end
    end
  end

  test "default_url falls back to the D-V2 default port when unset" do
    prior = Application.get_env(:world_host, :verifier_sidecar_url)
    Application.delete_env(:world_host, :verifier_sidecar_url)

    try do
      assert SidecarHealthcheck.default_url() == "http://127.0.0.1:8787/healthz"
    after
      if prior, do: Application.put_env(:world_host, :verifier_sidecar_url, prior)
    end
  end
end

```
