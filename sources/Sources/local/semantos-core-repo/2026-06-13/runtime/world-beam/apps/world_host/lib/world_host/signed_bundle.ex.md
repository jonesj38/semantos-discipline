---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/signed_bundle.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.319693+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/signed_bundle.ex

```ex
defmodule WorldHost.SignedBundle do
  @moduledoc """
  Build BRC-100 §12.1 SignedBundle envelopes for outbound frames.

  The TS counterpart is `apps/world-client/src/socket.ts:buildSignedBundle`.
  The canonical preimage MUST be byte-identical to that function so the
  client's `verifyInboundEnvelope` accepts our envelopes.

  Signing key + cert come from `WorldHost.HostIdentity` (per-boot
  ephemeral). Signing is `~1ms` per envelope; for tick fan-out we sign
  ONCE in `WorldHost.Region.broadcast_*` and the same envelope ships
  to every subscriber via PubSub.

  ## Wire shape (matches TS RawSignedBundle)

      %{
        "x-brc100-identitykey" => <hex 33B>,
        "x-brc100-nonce" => <hex 32B>,
        "x-brc100-timestamp" => <ms since epoch, integer>,
        "x-brc100-signature" => <DER hex>,
        "x-brc52-certificate" => <JSON string>,
        "payload" => <opaque>
      }

  ## K invariant

  K2 — every server→client frame is signed under the host's identity,
  so the client can verify origin before applying state mutations.
  """

  alias WorldHost.HostIdentity

  @doc """
  Build a signed envelope wrapping `payload`.

  Generates a fresh 32-byte nonce and current millisecond timestamp.
  The same payload signed twice yields different envelopes (different
  nonce + timestamp + non-deterministic ECDSA k).
  """
  @spec build(term()) :: %{required(String.t()) => term()}
  def build(payload) do
    identity = HostIdentity.get()
    nonce = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    timestamp = System.system_time(:millisecond)

    preimage =
      brc100_canonical_preimage(
        identity.public_key_hex,
        nonce,
        timestamp,
        payload
      )

    # Match @bsv/sdk's signing convention: PrivateKey.sign(digestHex, "hex")
    # internally does SHA-256 of the message bytes, so passing it
    # `sha256(preimage).toHex()` yields a SIGNATURE OVER `sha256(sha256(preimage))`
    # (Bitcoin's Hash256 / double-SHA256 pattern). The matching verifier
    # path on the JS side expects this double-hash. We reproduce it here:
    # pre-hash the preimage once and pass to `:crypto.sign(:ecdsa, :sha256, ...)`,
    # which will hash again before the EC operation.
    digest1 = :crypto.hash(:sha256, preimage)
    der = :crypto.sign(:ecdsa, :sha256, digest1, [identity.private_key, :secp256k1])
    signature_hex = Base.encode16(der, case: :lower)

    %{
      "x-brc100-identitykey" => identity.public_key_hex,
      "x-brc100-nonce" => nonce,
      "x-brc100-timestamp" => timestamp,
      "x-brc100-signature" => signature_hex,
      "x-brc52-certificate" => Jason.encode!(identity.cert),
      "payload" => payload
    }
  end

  # Mirror of socket.ts:buildBrc100Preimage (and verifier.ts:brc100CanonicalPreimage).
  # Object: {payload, x-brc100-identitykey, x-brc100-nonce, x-brc100-timestamp}.
  # Sorted keys at every nesting level, compact JSON, UTF-8.
  defp brc100_canonical_preimage(identity_key_hex, nonce_hex, timestamp, payload) do
    canonical_json(%{
      "payload" => payload,
      "x-brc100-identitykey" => identity_key_hex,
      "x-brc100-nonce" => nonce_hex,
      "x-brc100-timestamp" => timestamp
    })
  end

  # Custom canonical JSON encoder.
  #
  # We CANNOT just `value |> deep_sort_to_map() |> Jason.encode!()` —
  # `Map.new(sorted_keylist)` does not reliably preserve sort order
  # in BEAM's small-map iteration (especially for atom keys, where
  # Erlang term order on atoms is allocation-id, not name). So we
  # walk the structure ourselves, sort keys explicitly, and emit JSON
  # bytes directly via the sorted keylist.
  #
  # JS-compat rules baked in:
  #   - All map keys serialise as strings (atom -> Atom.to_string).
  #   - Map keys sorted lexicographically by their string form.
  #   - Whole-number floats -> integers (since JSON.stringify(0.0) is "0"
  #     in JS — see the JS-compatibility regression test).
  @doc false
  # Exposed for test/debugging only — not part of the public API.
  def canonical_json(value), do: IO.iodata_to_binary(encode(value))

  defp encode(nil), do: "null"
  defp encode(true), do: "true"
  defp encode(false), do: "false"

  defp encode(value) when is_binary(value), do: Jason.encode!(value)
  defp encode(value) when is_atom(value), do: Jason.encode!(Atom.to_string(value))
  defp encode(value) when is_integer(value), do: Integer.to_string(value)

  defp encode(value) when is_float(value) do
    truncated = trunc(value)
    if value == truncated * 1.0,
      do: Integer.to_string(truncated),
      else: Jason.encode!(value)
  end

  defp encode(value) when is_list(value) do
    [?[, value |> Enum.map(&encode/1) |> Enum.intersperse(?,), ?]]
  end

  defp encode(value) when is_map(value) do
    entries =
      value
      |> Enum.map(fn {k, v} -> {key_to_string(k), v} end)
      |> Enum.sort_by(fn {k, _v} -> k end)
      |> Enum.map(fn {k, v} -> [Jason.encode!(k), ?:, encode(v)] end)
      |> Enum.intersperse(?,)

    [?{, entries, ?}]
  end

  defp key_to_string(k) when is_binary(k), do: k
  defp key_to_string(k) when is_atom(k), do: Atom.to_string(k)
end

```
