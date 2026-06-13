---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/host_identity.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.318770+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/host_identity.ex

```ex
defmodule WorldHost.HostIdentity do
  @moduledoc """
  Per-boot ephemeral signing identity for the World Host.

  On first call, generates a fresh secp256k1 keypair and a self-signed
  BRC-52 cert (host is its own certifier). The keypair + cert are
  cached in `:persistent_term` for the lifetime of the BEAM node — no
  GenServer overhead on the hot signing path.

  This is the dev-grade host identity. The proper path (Plexus-issued
  host cert, persisted across reboots) is tracked separately under the
  wallet/credentials track.

  ## Returned shape

      %{
        private_key: <<32 bytes>>,
        public_key_hex: "02..." | "03...",   # 33B compressed
        cert: %{
          "certId" => ...,
          "subjectPublicKey" => ...,
          "certifierPublicKey" => ...,        # same as subject (self-signed)
          "type" => "world-host",
          "serialNumber" => ...,
          "fields" => %{},
          "signature" => ...
        }
      }

  Cert fields use camelCase string keys to match the wire format the
  client + verifier sidecar expect (per `runtime/verifier-sidecar/src/types.ts`).

  ## K invariant

  K2 — every server→client frame is BRC-100 signed under this key, so
  the client can prove the frame originated at this host.
  """

  alias WorldHost.Identity

  @persistent_key {__MODULE__, :identity}

  @doc """
  Return the cached host identity, generating it on first call.
  """
  @spec get() :: %{
          private_key: binary(),
          public_key_hex: String.t(),
          cert: %{required(String.t()) => term()}
        }
  def get do
    case :persistent_term.get(@persistent_key, :missing) do
      :missing ->
        identity = generate()
        :persistent_term.put(@persistent_key, identity)
        identity

      identity ->
        identity
    end
  end

  @doc """
  Force-regenerate the host identity. Test-only — production never
  rotates a per-boot ephemeral key.
  """
  @spec reset!() :: :ok
  def reset! do
    :persistent_term.erase(@persistent_key)
    :ok
  end

  # ── Generation ──────────────────────────────────────────────────────

  defp generate do
    {pubkey_uncompressed, privkey} = :crypto.generate_key(:ecdh, :secp256k1)
    pubkey_hex = pubkey_uncompressed |> compress_pubkey() |> Base.encode16(case: :lower)
    serial_number = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

    cert = self_sign_cert(pubkey_hex, serial_number, privkey)

    %{
      private_key: privkey,
      public_key_hex: pubkey_hex,
      cert: cert
    }
  end

  # secp256k1 SEC compression: <<0x04, x::32, y::32>> → <<0x02|0x03, x::32>>.
  # 0x02 if y is even, 0x03 if y is odd.
  defp compress_pubkey(<<4, x::binary-size(32), y::binary-size(32)>>) do
    last_byte = :binary.last(y)
    prefix = if rem(last_byte, 2) == 0, do: 0x02, else: 0x03
    <<prefix, x::binary>>
  end

  defp self_sign_cert(pubkey_hex, serial_number, privkey) do
    # cert_id = SHA-256(canonical preimage over 5 fields, no certId, no signature).
    cert_no_id_or_sig = %{
      "certifierPublicKey" => pubkey_hex,
      "fields" => %{},
      "serialNumber" => serial_number,
      "subjectPublicKey" => pubkey_hex,
      "type" => "world-host"
    }

    cert_id = Identity.compute_cert_id(cert_no_id_or_sig)

    # Issuer signature: signed over the same 5 fields PLUS certId
    # (matches verifier.ts:brc52IssuerSignaturePreimage).
    issuer_preimage_obj = Map.put(cert_no_id_or_sig, "certId", cert_id)
    issuer_preimage = canonical_json(issuer_preimage_obj)
    signature_hex = sign_ecdsa(issuer_preimage, privkey)

    cert_no_id_or_sig
    |> Map.put("certId", cert_id)
    |> Map.put("signature", signature_hex)
  end

  defp canonical_json(obj) do
    obj
    |> deep_sort()
    |> Jason.encode!()
  end

  # Mirror WorldHost.Identity.deep_sort_map (private). Sort keys at every
  # nesting level. Small maps (<32 keys) preserve insertion order in BEAM,
  # so Map.new of a sorted list iterates in sorted order — Jason then
  # encodes in that order.
  defp deep_sort(value) when is_map(value) do
    value
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.map(fn {k, v} -> {k, deep_sort(v)} end)
    |> Map.new()
  end

  defp deep_sort(value) when is_list(value) do
    Enum.map(value, &deep_sort/1)
  end

  defp deep_sort(value), do: value

  # Sign with @bsv/sdk's "double-hash" convention so the produced cert
  # passes BRC-52 issuer-signature verification on the JS side.
  # PrivateKey.sign(digestHex, "hex") in @bsv/sdk internally SHA-256s the
  # decoded digest, so we pre-hash here and let `:crypto.sign(:ecdsa, :sha256, ...)`
  # hash again — matching final SHA-256(SHA-256(message)) signing target.
  defp sign_ecdsa(message, privkey) do
    digest1 = :crypto.hash(:sha256, message)
    der = :crypto.sign(:ecdsa, :sha256, digest1, [privkey, :secp256k1])
    Base.encode16(der, case: :lower)
  end
end

```
