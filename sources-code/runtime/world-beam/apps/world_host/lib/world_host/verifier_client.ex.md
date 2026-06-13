---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/verifier_client.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.320912+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/verifier_client.ex

```ex
defmodule WorldHost.VerifierClient do
  @moduledoc """
  Behaviour for the BRC-100 / BRC-52 verifier sidecar (D-V3).

  D-V1 shipped the TS reference implementation as
  `@semantos/verifier-sidecar`; D-V2 codified per-node sidecar topology
  (port 8787, `GET /healthz`); D-V3 brings the HTTP server entry-point
  to `runtime/verifier-sidecar/src/server.ts` AND wires it into World
  Host's `connect/3`.

  This Elixir module is World Host's outbound boundary. It performs:

      POST http://127.0.0.1:8787/verify
      Content-Type: application/json
      { "envelope": <RawSignedBundle JSON>, "capToken": <CapTokenRef JSON | null> }

  on the verifier sidecar and returns the structured response.

  ## Spec source

    - `docs/spec/protocol-v0.5.md` §9.5 (Verifier Sidecar)
    - `docs/spec/protocol-v0.5.md` §12.1 (SignedBundle envelope)
    - `runtime/verifier-sidecar/README.md` (D-V2 deployment guide)

  ## Canonical term

  Verifier Sidecar (per `docs/canon/glossary.yml` id: `verifier-sidecar`).

  ## K invariant

  K2 — any state-changing transition requires successful identity
  verification. World Host's `connect/3` is the boundary at which K2's
  assumption is enforced for the world-host adapter (per Unification
  Roadmap §5 D-V3).

  ## Test seam

  `runtime/world-beam/apps/world_host/test/world_host_web/user_socket_test.exs` swaps in a
  Mock implementation via the `:world_host` application config:

      config :world_host, :verifier_client, WorldHost.VerifierClient.Mock

  Production (default) uses `WorldHost.VerifierClient.Http`.
  """

  @typedoc """
  The raw BRC-100 SignedBundle envelope as it arrives at the connect
  boundary. Shape mirrors `RawSignedBundle` in
  `runtime/verifier-sidecar/src/types.ts` and §12.1.
  """
  @type envelope :: %{required(String.t()) => term()}

  @typedoc """
  Optional capability token reference. Shape mirrors
  `CapabilityTokenRef` in the TS sidecar.
  """
  @type cap_token :: %{required(String.t()) => term()} | nil

  @typedoc """
  Successful verification — the sidecar verified BRC-100 signature,
  BRC-52 cert authenticity, and identity binding (K2). The `bca` is
  derived from the cert's subjectPublicKey (see
  `runtime/verifier-sidecar/src/bca.ts`); World Host assigns it to
  `socket.assigns.bca`.
  """
  @type ok_result :: %{
          required(:ok) => true,
          required(:cert_id) => String.t(),
          optional(:bca) => String.t()
        }

  @typedoc """
  Verification failure — either the sidecar returned `ok: false` (a
  protocol-level rejection like `brc100_invalid_signature`) or a
  transport-level error (sidecar unreachable, malformed response).
  Both branches refuse the connection.
  """
  @type error_result :: %{
          required(:ok) => false,
          required(:code) => String.t(),
          required(:message) => String.t()
        }

  @type result :: ok_result() | error_result()

  @callback verify(envelope(), cap_token()) :: result()

  @doc """
  D-A1 — verify a capability token for an already-authenticated
  principal. Used at the channel-join boundary, where the BRC-100
  envelope was already validated at connect/3 and only the cap_token
  needs Phase-3 authorisation.

  Default implementation (provided here, overridable per-impl) builds
  a synthetic single-field envelope carrying the verified cert_id and
  identitykey, then dispatches to `verify/2` so existing
  implementations keep working unchanged. The Mock overrides this for
  precise control over the join contract; the Http impl falls back to
  the default and lets the sidecar's `/verify` decide.
  """
  @callback verify_cap_token(cert_id :: String.t(), cap_token()) :: result()

  @optional_callbacks verify_cap_token: 2

  @doc """
  Verify an envelope via the configured sidecar client.

  Resolves the implementation at call-site so tests can swap it via
  Application config without recompilation.
  """
  @spec verify(envelope(), cap_token()) :: result()
  def verify(envelope, cap_token \\ nil) do
    impl = Application.get_env(:world_host, :verifier_client, WorldHost.VerifierClient.Http)
    impl.verify(envelope, cap_token)
  end

  @doc """
  D-A1 — verify a cap_token at the channel-join boundary.
  """
  @spec verify_cap_token(String.t(), cap_token()) :: result()
  def verify_cap_token(cert_id, cap_token) do
    impl = Application.get_env(:world_host, :verifier_client, WorldHost.VerifierClient.Http)

    if function_exported?(impl, :verify_cap_token, 2) do
      impl.verify_cap_token(cert_id, cap_token)
    else
      # Default: synthesise a single-field envelope and dispatch to
      # `verify/2`. Implementations that don't need the optional callback
      # get this for free.
      envelope = %{"cert_id" => cert_id}
      impl.verify(envelope, cap_token)
    end
  end

  @doc """
  Sidecar URL — defaults to `http://127.0.0.1:8787` per D-V2 README.
  Override via the `:verifier_sidecar_url` app env, e.g. for an
  edge-gateway deployment.
  """
  @spec sidecar_url() :: String.t()
  def sidecar_url do
    Application.get_env(:world_host, :verifier_sidecar_url, "http://127.0.0.1:8787")
  end
end

```
