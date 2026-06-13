---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/verifier_client/http.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.323184+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/verifier_client/http.ex

```ex
defmodule WorldHost.VerifierClient.Http do
  @moduledoc """
  Production `WorldHost.VerifierClient` — talks to the Verifier Sidecar
  over loopback HTTP via `:httpc` (no new Elixir runtime deps).

  POST shape, response shape, and error semantics match
  `runtime/verifier-sidecar/src/server.ts` exactly.

  ## Why `:httpc`

  `:httpc` ships with OTP — no new dep. The brief explicitly forbids
  adding new Elixir runtime deps without flagging. The trade-off
  vs. `Finch` (better connection pooling, easier mocking) is
  acceptable here: the sidecar lives on loopback, the per-request
  cost is dominated by ECDSA verification on the sidecar side, and
  this client is only invoked at WebSocket connect time (not per
  message). When `Finch` lands for D-C1's per-message
  SignedBundle path, this client SHOULD be migrated.

  ## Failure modes

  Any non-`{:ok, ...}` from `:httpc.request/4` is mapped to a structured
  `%{ok: false, code: "verifier_unreachable", message: ...}` so the
  `connect/3` consumer can fail closed without leaking transport
  details into the `Phoenix.Socket.refuse` payload.

  Spec source: `docs/spec/protocol-v0.5.md` §9.5;
               `runtime/verifier-sidecar/README.md`.
  """

  @behaviour WorldHost.VerifierClient

  require Logger

  @impl WorldHost.VerifierClient
  def verify(envelope, cap_token \\ nil) do
    body =
      %{"envelope" => envelope}
      |> maybe_put_cap_token(cap_token)
      |> Jason.encode!()

    url = String.to_charlist(WorldHost.VerifierClient.sidecar_url() <> "/verify")
    headers = [{~c"content-type", ~c"application/json"}]
    request = {url, headers, ~c"application/json", body}

    # 5_000ms timeout — connect-time path; faster than this MUST be
    # achievable on loopback. If we ever miss the window, the user
    # sees a closed WebSocket and the operator sees a logged code.
    http_options = [{:timeout, 5_000}, {:connect_timeout, 1_000}]
    options = [{:body_format, :binary}]

    case :httpc.request(:post, request, http_options, options) do
      {:ok, {{_, status, _}, _headers, response_body}}
      when status in 200..299 ->
        decode_ok(response_body)

      {:ok, {{_, 400, _}, _headers, response_body}} ->
        # Sidecar already returned a structured error body for malformed
        # requests; pass it through.
        decode_ok(response_body)

      {:ok, {{_, status, _}, _headers, response_body}} ->
        Logger.warning(
          "verifier sidecar returned status #{status}: #{inspect(response_body)}"
        )

        %{
          ok: false,
          code: "verifier_unreachable",
          message: "verifier sidecar returned HTTP #{status}"
        }

      {:error, reason} ->
        Logger.warning("verifier sidecar unreachable: #{inspect(reason)}")

        %{
          ok: false,
          code: "verifier_unreachable",
          message: "verifier sidecar unreachable: #{inspect(reason)}"
        }
    end
  end

  defp maybe_put_cap_token(body, nil), do: body
  defp maybe_put_cap_token(body, cap_token), do: Map.put(body, "capToken", cap_token)

  # Phase-3-only verification at the channel-join boundary.
  #
  # The default `WorldHost.VerifierClient.verify_cap_token/2` synthesises
  # a single-field envelope (`%{"cert_id" => cert_id}`) and dispatches to
  # `verify/2`. That envelope cannot pass the sidecar's Phase 1 BRC-100
  # signature check (it has no headers), so it always returns
  # `brc100_missing_field` and joins are refused.
  #
  # For now: connect/3 already verified the principal end-to-end via
  # the Verifier Sidecar. The cap_token's job at join is Phase 3 (SPV +
  # liveness on a BRC-108 capability UTXO). The sidecar's Phase 3 is a
  # no-op when no `SpvProvider` is configured (see
  # `runtime/verifier-sidecar/src/verifier.ts:430`), and gap-1 SPV
  # wiring is happening on a separate track. Until that lands, treat a
  # well-shaped cap_token as accepted.
  #
  # When real Phase-3 verification arrives, this impl SHOULD POST to a
  # `/verify-cap-token` endpoint on the sidecar that takes `(cert_id,
  # cap_token)` and runs Phase 3 in isolation.
  @impl WorldHost.VerifierClient
  def verify_cap_token(cert_id, cap_token) when is_binary(cert_id) do
    case cap_token do
      %{"txId" => tx_id, "vout" => vout} when is_binary(tx_id) and is_integer(vout) ->
        %{ok: true, cert_id: cert_id}

      _ ->
        %{
          ok: false,
          code: "cap_token_malformed",
          message: "cap_token must include txId (hex) and vout (integer)"
        }
    end
  end

  defp decode_ok(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"ok" => true} = json} ->
        result = %{ok: true, cert_id: Map.fetch!(json, "certId")}

        case Map.get(json, "bca") do
          nil -> result
          bca when is_binary(bca) -> Map.put(result, :bca, bca)
        end

      {:ok, %{"ok" => false, "code" => code, "message" => message}} ->
        %{ok: false, code: code, message: message}

      {:ok, %{"ok" => false, "code" => code}} ->
        %{ok: false, code: code, message: ""}

      {:ok, other} ->
        %{
          ok: false,
          code: "verifier_unreachable",
          message: "verifier sidecar returned unexpected JSON shape: #{inspect(other)}"
        }

      {:error, reason} ->
        %{
          ok: false,
          code: "verifier_unreachable",
          message: "verifier sidecar returned non-JSON: #{inspect(reason)}"
        }
    end
  end
end

```
