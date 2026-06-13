---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/test/support/verifier_client_mock.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.329265+00:00
---

# runtime/world-beam/apps/world_host/test/support/verifier_client_mock.ex

```ex
defmodule WorldHost.VerifierClient.Mock do
  @moduledoc """
  Test double for `WorldHost.VerifierClient`.

  Intercepts the call that `WorldHostWeb.UserSocket.connect/3` and
  `WorldHostWeb.WorldChannel.join/3` make to the Verifier Sidecar so the
  identity / capability boundary contract can be tested without booting
  a real sidecar process.

  ## D-A1 — real ECDSA-signed bundles

  D-V3's mock accepted any well-shaped envelope by reading the cert's
  `certId` field and returning it verbatim. That was fine for connect
  contract tests but didn't exercise the signature / cert authenticity
  / identity binding pipeline. D-A1 replaces that path with **local
  verification** through `WorldHost.Test.SignedBundleFixture.verify_locally/2`,
  which mirrors the production `BrcVerifier` Phase 1 + Phase 2 logic
  using OTP `:crypto`. The test owns the keypair via
  `SignedBundleFixture.generate_keys/0`; tampering the signature, cert,
  or identity key produces the same `code` the production sidecar would
  return.

  ## Modes

  Three modes, selected via `Process.put(:verifier_mock_mode, ...)`:

    * `:verify` (default) — run real ECDSA verification locally on
      every envelope. The test owns the keypair (via
      `SignedBundleFixture`); a tampered envelope is rejected exactly
      as the production sidecar would reject it.

    * `:accept` — historical fixture path that accepts any envelope
      and derives `cert_id` from the cert JSON's `certId` field. Kept
      so pre-D-A1 tests (channel-resilience, etc.) that don't need
      real-crypto round trips can keep using `mock_connect_params/1`
      from `WorldHostWeb.ChannelCase` without minting fresh keys.

    * `:reject` — return a structured error. The error shape is
      controlled by `Process.put({:verifier_mock, :error}, ...)`.

  ## Capability-token outcome

  D-A1's `:verify` path also routes the cap_token through the local
  verifier. To drive accept/reject paths without an SPV provider, set
  the application env (process-dict won't propagate to a channel's
  GenServer process):

      Application.put_env(:world_host, :verifier_mock_cap_token, :accept)   # default
      Application.put_env(:world_host, :verifier_mock_cap_token, :reject)
      Application.put_env(:world_host, :verifier_mock_cap_token, {:reject, "custom_code", "msg"})

  ## Configuration

  Set in `runtime/world-beam/config/test.exs`:

      config :world_host, :verifier_client, WorldHost.VerifierClient.Mock
  """

  @behaviour WorldHost.VerifierClient

  alias WorldHost.Test.SignedBundleFixture

  @impl WorldHost.VerifierClient
  def verify(envelope, cap_token \\ nil) do
    case Process.get(:verifier_mock_mode, :verify) do
      :reject ->
        Process.get(
          {:verifier_mock, :error},
          %{
            ok: false,
            code: "brc100_invalid_signature",
            message: "mock-default rejection"
          }
        )

      :verify ->
        SignedBundleFixture.verify_locally(envelope, cap_token)

      :accept ->
        legacy_accept(envelope)
    end
  end

  @impl WorldHost.VerifierClient
  def verify_cap_token(cert_id, cap_token) do
    # Channel-join cap_token check. The principal is already
    # authenticated (cert_id was set on the socket at connect/3); the
    # job here is to authorise the cap_token specifically.
    #
    # Honours the same `:verifier_mock_cap_token` process-dict hook
    # SignedBundleFixture uses internally, so tests have one knob for
    # cap_token outcomes regardless of which call site reaches the mock.
    cap_outcome = Application.get_env(:world_host, :verifier_mock_cap_token, :accept)

    case {Process.get(:verifier_mock_mode, :verify), cap_outcome} do
      {:reject, _} ->
        Process.get(
          {:verifier_mock, :error},
          %{ok: false, code: "brc100_invalid_signature", message: "mock-default rejection"}
        )

      {_, :reject} ->
        %{
          ok: false,
          code: "capability_utxo_spent",
          message: "capability UTXO is spent or SPV proof invalid"
        }

      {_, {:reject, code, message}} ->
        %{ok: false, code: code, message: message}

      {_, :accept} when is_binary(cert_id) and is_map(cap_token) ->
        %{ok: true, cert_id: cert_id}
    end
  end

  # Legacy fixture path — kept for tests that don't need real-crypto
  # round trips. Reads cert_id straight from the envelope's cert JSON.
  defp legacy_accept(envelope) do
    cert_json = Map.get(envelope, "x-brc52-certificate", "{}")

    cert_id =
      case Jason.decode(cert_json) do
        {:ok, %{"certId" => id}} when is_binary(id) -> id
        _ -> "mock-cert-id"
      end

    bca = mock_bca(cert_id)
    %{ok: true, cert_id: cert_id, bca: bca}
  end

  defp mock_bca(cert_id) do
    :crypto.hash(:sha256, "mock-bca:" <> cert_id)
    |> binary_part(0, 16)
    |> Base.encode16(case: :lower)
  end
end

```
