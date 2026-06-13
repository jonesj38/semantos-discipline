---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host_web/user_socket.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.315062+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host_web/user_socket.ex

```ex
defmodule WorldHostWeb.UserSocket do
  @moduledoc """
  WebSocket entry point for the World Host.

  ## D-V3 — Verifier Sidecar integration

  `connect/3` is the boundary at which World Host enforces K2: every
  inbound WebSocket presents a BRC-100 SignedBundle wrapping a BRC-52
  certificate; the Verifier Sidecar (over loopback HTTP per the D-V2
  per-node topology) verifies signature, cert authenticity, and
  identity binding before the socket is accepted.

  Wire-level params (D-A2 honours these on the client side):

    - `cert`           — BRC-52 certificate, JSON-serialised (the
                         `x-brc52-certificate` field).
    - `signed_bundle`  — full BRC-100 SignedBundle headers + payload,
                         JSON-serialised (the §12.1 envelope).

  On successful verification:

    - `socket.assigns.bca`     — the BCA derived from the verified
                                 cert's subjectPublicKey (returned by
                                 the sidecar).
    - `socket.assigns.cert_id` — the verified cert_id.
    - `socket.assigns.identity_key` — the verified 33-byte compressed
                                       pubkey hex.

  On failure: returns `{:error, %{code:, message:}}`, refusing the
  socket per Phoenix UserSocket conventions.

  ## Spec source

    - `docs/spec/protocol-v0.5.md` §4.3 (BCA derivation), §9.5
      (Verifier Sidecar), §12.1 (SignedBundle envelope).
    - `runtime/verifier-sidecar/README.md` — D-V2 deployment guide
      whose `/healthz` + `/verify` contract this module consumes.

  ## Canonical terms

    - Verifier Sidecar (glossary id: `verifier-sidecar`).
    - SignedBundle     (glossary id: `signed-bundle`).
    - BCA              (glossary id: `bca`).
    - cert_id          (glossary id: `cert-id`).

  ## K invariant

  K2 — boundary verification before any state mutation.

  ## Pre-D-V3 behaviour

  D-V3 enforces verification at `connect/3`. The avatar/entity
  ownership semantics in `world_channel.ex` continue to use a
  controller string sourced from the verified `cert_id`; the
  pre-D-V3 random-identifier path is no longer reachable from this
  module (the older variable name still appears in `world_channel.ex`
  and `entity.ex` for cross-cell wire compatibility — that rename
  lands with D-A1).
  """

  use Phoenix.Socket

  channel("world:*", WorldHostWeb.WorldChannel)

  @impl true
  def connect(params, socket, _connect_info) do
    with {:ok, envelope} <- parse_signed_bundle(params),
         {:ok, cap_token} <- parse_cap_token(params),
         %{ok: true} = result <- WorldHost.VerifierClient.verify(envelope, cap_token) do
      socket =
        socket
        |> assign(:cert_id, Map.fetch!(result, :cert_id))
        |> assign(:bca, Map.get(result, :bca))
        |> assign(:identity_key, envelope["x-brc100-identitykey"])

      {:ok, socket}
    else
      {:error, %{code: code, message: message}} ->
        {:error, %{code: code, message: message}}

      %{ok: false, code: code, message: message} ->
        {:error, %{code: code, message: message}}
    end
  end

  @impl true
  def id(socket), do: "socket:#{socket.assigns.cert_id}"

  # ── Param parsing ──────────────────────────────────────────────────

  # The `signed_bundle` param is the full §12.1 envelope serialised as
  # JSON. We DO NOT strip any field — the sidecar checks every header.
  defp parse_signed_bundle(params) do
    case Map.get(params, "signed_bundle") do
      nil ->
        {:error,
         %{
           code: "envelope_missing",
           message: "connect requires a `signed_bundle` JSON param (BRC-100 envelope, §12.1)"
         }}

      bundle when is_map(bundle) ->
        {:ok, bundle}

      bundle when is_binary(bundle) ->
        case Jason.decode(bundle) do
          {:ok, decoded} when is_map(decoded) ->
            {:ok, decoded}

          _ ->
            {:error,
             %{
               code: "envelope_malformed",
               message: "`signed_bundle` is not valid JSON"
             }}
        end

      _ ->
        {:error,
         %{
           code: "envelope_malformed",
           message: "`signed_bundle` must be a JSON object or JSON-encoded string"
         }}
    end
  end

  # `cap_token` is optional. When present, the sidecar runs Phase 3
  # SPV checks; when absent, it skips Phase 3.
  defp parse_cap_token(params) do
    case Map.get(params, "cap_token") do
      nil ->
        {:ok, nil}

      cap when is_map(cap) ->
        {:ok, cap}

      cap when is_binary(cap) ->
        case Jason.decode(cap) do
          {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
          _ -> {:ok, nil}
        end

      _ ->
        {:ok, nil}
    end
  end
end

```
