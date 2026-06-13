---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/test/support/signed_bundle_fixture.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.328646+00:00
---

# runtime/world-beam/apps/world_host/test/support/signed_bundle_fixture.ex

```ex
defmodule WorldHost.Test.SignedBundleFixture do
  @moduledoc """
  D-A1 — Real ECDSA-signed BRC-52 cert + BRC-100 SignedBundle fixtures
  for World Host tests.

  D-V3's mock (`WorldHost.VerifierClient.Mock`) accepted any envelope by
  reading the cert's `certId` field as the verified identity. That was
  fine for connect-boundary contract tests, but it didn't exercise the
  signature / cert authenticity / identity binding logic the real
  Verifier Sidecar enforces, so a regression that broke any of those
  upstream paths would slip through.

  D-A1 replaces the mock's deterministic-from-cert-string fixture with
  real ECDSA-signed bundles where **the test owns the keypair**. This
  module is the helper that builds them, mirroring D-V1's TS fixture
  builders in `runtime/verifier-sidecar/src/__tests__/verifier-sidecar.test.ts`.

  ## Algorithms

    - secp256k1 ECDSA (`:crypto` curve `:secp256k1`).
    - Compressed pubkey serialisation (33 bytes: `0x02|0x03 || x`).
    - DER-encoded signatures (matches `@bsv/sdk` `Signature.toDER()`).
    - SHA-256 hashing.

  Byte-format compatibility:

    - Cert preimage canonicalisation matches
      `WorldHost.Identity.canonical_cert_preimage/1` (the D-A0b mirror
      of `core/plexus-contracts/src/identity.ts`), so the cert_id this
      module produces is byte-identical to the TS / Zig pipelines.

    - SignedBundle preimage matches
      `runtime/verifier-sidecar/src/verifier.ts` `brc100CanonicalPreimage`:
      sorted-key compact JSON over identitykey + nonce + timestamp +
      payload, UTF-8 encoded.

  ## Usage

      keys = SignedBundleFixture.generate_keys()
      cert = SignedBundleFixture.build_cert(keys, "plexus.identity.root")
      bundle = SignedBundleFixture.build_envelope(keys, cert, %{"action" => "move"})

  The returned `bundle` is a string-keyed map shaped like a §12.1
  envelope, ready to pass to
  `WorldHost.VerifierClient.verify(bundle, cap_token)` or to drop
  into a Phoenix-channel `connect/3` `signed_bundle` param.

  ## Spec source

    - `docs/spec/protocol-v0.5.md` §4.2 (BRC-52 cert format)
    - `docs/spec/protocol-v0.5.md` §12.1 (SignedBundle envelope)

  ## Canonical terms

    - cert_id (glossary id: `cert-id`).
    - SignedBundle (glossary id: `signed-bundle`).
    - BRC-100 / BRC-52 (per glossary).

  ## K invariant

  K2 — boundary verification before state mutation. This module's
  output exercises the same signature paths the production Verifier
  Sidecar checks.
  """

  alias WorldHost.Identity

  @typedoc """
  An ECDSA keypair on secp256k1, both as the raw OTP-private form
  (32 bytes) and the compressed pubkey hex (33 bytes → 66 chars).
  """
  @type keypair :: %{
          private_key: binary(),
          public_key: binary(),
          public_key_hex: String.t()
        }

  @doc """
  Generate a fresh secp256k1 keypair.

  The returned `private_key` is the raw 32-byte big-endian scalar; the
  `public_key` is the uncompressed-or-compressed binary as OTP returns
  it; `public_key_hex` is the compressed form (33 bytes hex), matching
  the `subjectPublicKey` field in BRC-52 certs.
  """
  @spec generate_keys() :: keypair()
  def generate_keys do
    {public_key, private_key} = :crypto.generate_key(:ecdh, :secp256k1)

    %{
      private_key: private_key,
      public_key: public_key,
      public_key_hex: compress_public_key(public_key) |> Base.encode16(case: :lower)
    }
  end

  @doc """
  Build a BRC-52 cert. `subject_keys` is the cert subject's keypair;
  `certifier_keys` is the issuer's keypair (for self-signed root certs,
  pass the same keypair as both arguments).

  The resulting cert satisfies:

    - `certId == SHA-256(canonical_preimage)` per §4.2.
    - `signature` is the certifier's ECDSA signature over the canonical
      preimage including certId (matches D-V1's `BrcVerifier`
      issuer-sig check).
    - `subjectPublicKey == compressed_hex(subject_keys.public_key)`.
  """
  @spec build_cert(keypair(), keypair(), keyword()) :: map()
  def build_cert(subject_keys, certifier_keys, opts \\ []) do
    type = Keyword.get(opts, :type, "plexus.identity.root")
    fields = Keyword.get(opts, :fields, %{})
    serial_number = Keyword.get(opts, :serial_number, default_serial(subject_keys, certifier_keys, type))

    subject_pk = subject_keys.public_key_hex
    certifier_pk = certifier_keys.public_key_hex

    # Build the preimage map and compute cert_id via the canonical
    # function (byte-identical to TS / Zig).
    preimage_cert = %{
      "certifierPublicKey" => certifier_pk,
      "fields" => fields,
      "serialNumber" => serial_number,
      "subjectPublicKey" => subject_pk,
      "type" => type
    }

    cert_id = Identity.compute_cert_id(preimage_cert)

    # Issuer signs the canonical preimage *including* certId — mirrors
    # `brc52IssuerSignaturePreimage` in verifier.ts.
    issuer_preimage = %{
      "certId" => cert_id,
      "certifierPublicKey" => certifier_pk,
      "fields" => fields,
      "serialNumber" => serial_number,
      "subjectPublicKey" => subject_pk,
      "type" => type
    }

    issuer_preimage_bytes = canonical_json(issuer_preimage)
    digest = :crypto.hash(:sha256, issuer_preimage_bytes)
    signature = sign_digest(digest, certifier_keys.private_key)

    %{
      "certId" => cert_id,
      "subjectPublicKey" => subject_pk,
      "certifierPublicKey" => certifier_pk,
      "type" => type,
      "serialNumber" => serial_number,
      "fields" => fields,
      "signature" => Base.encode16(signature, case: :lower)
    }
  end

  @doc """
  Build a BRC-100 SignedBundle envelope around the supplied payload,
  signed by `signer_keys` and carrying `cert` as the
  `x-brc52-certificate`.

  Per §12.1 the canonical preimage is identitykey + nonce + timestamp +
  payload (sorted-key JSON, UTF-8). The signature is DER-encoded ECDSA
  over SHA-256(preimage), matching the verifier sidecar's
  `brc100CanonicalPreimage` exactly.
  """
  @spec build_envelope(keypair(), map(), term(), keyword()) :: map()
  def build_envelope(signer_keys, cert, payload \\ %{"kind" => "world_host_connect"}, opts \\ []) do
    nonce = Keyword.get(opts, :nonce, fresh_nonce())
    timestamp = Keyword.get(opts, :timestamp, System.system_time(:millisecond))
    identity_key_hex = signer_keys.public_key_hex

    preimage_obj = %{
      "x-brc100-identitykey" => identity_key_hex,
      "x-brc100-nonce" => nonce,
      "x-brc100-timestamp" => timestamp,
      "payload" => payload
    }

    preimage_bytes = canonical_json(preimage_obj)
    digest = :crypto.hash(:sha256, preimage_bytes)
    signature = sign_digest(digest, signer_keys.private_key)

    %{
      "x-brc100-identitykey" => identity_key_hex,
      "x-brc100-nonce" => nonce,
      "x-brc100-timestamp" => timestamp,
      "x-brc100-signature" => Base.encode16(signature, case: :lower),
      "x-brc52-certificate" => Jason.encode!(cert),
      "payload" => payload
    }
  end

  @doc """
  Convenience: build a complete fixture (subject keys + cert +
  envelope), suitable for dropping into a `connect/3` test:

      %{bundle: bundle, cert: cert, keys: keys} = SignedBundleFixture.fresh()
      connect(UserSocket, %{"signed_bundle" => bundle})

  Use `fresh/1` with a `:seed_label` to make the fields tied to a
  per-test label without losing the real-crypto property.
  """
  @spec fresh(keyword()) :: %{
          bundle: map(),
          cert: map(),
          keys: keypair()
        }
  def fresh(opts \\ []) do
    seed_label = Keyword.get(opts, :seed_label, "default")
    keys = generate_keys()
    cert = build_cert(keys, keys, type: "plexus.identity.root", fields: %{"label" => seed_label})
    bundle = build_envelope(keys, cert)
    %{bundle: bundle, cert: cert, keys: keys}
  end

  # ── Verification (used by VerifierClient.Mock) ──────────────────────────────

  @doc """
  Verify a SignedBundle locally — same logic the production Verifier
  Sidecar runs, minus the SPV phase.

  Returns the same shape as `WorldHost.VerifierClient.verify/2`:

    - `%{ok: true, cert_id: <hex>, bca: <hex>}` on success.
    - `%{ok: false, code: <atom_string>, message: <string>}` on failure.

  Used by `WorldHost.VerifierClient.Mock` so tests exercise real ECDSA
  paths without round-tripping to the sidecar process. Behaviour
  matches `runtime/verifier-sidecar/src/verifier.ts` Phase 1 + Phase 2;
  Phase 3 (cap_token SPV) is honoured via a pluggable test hook so
  individual tests can drive accept/reject paths without booting an SPV
  provider.
  """
  @spec verify_locally(map(), map() | nil) :: map()
  def verify_locally(envelope, cap_token \\ nil) do
    with {:ok, cert} <- check_signature_and_parse_cert(envelope),
         :ok <- check_cert_id(cert),
         :ok <- check_issuer_signature(cert),
         :ok <- check_identity_binding(envelope, cert),
         :ok <- check_cap_token(cap_token) do
      %{
        ok: true,
        cert_id: Map.fetch!(cert, "certId"),
        bca: derive_mock_bca(Map.fetch!(cert, "subjectPublicKey"))
      }
    else
      {:error, code, message} ->
        %{ok: false, code: code, message: message}
    end
  end

  # ── Private helpers — canonicalisation ──────────────────────────────────────

  # Deep-sorted, compact JSON. Mirrors `canonicalJson` in
  # runtime/verifier-sidecar/src/__tests__/verifier-sidecar.test.ts
  # and the `deep_sort_map` path in `WorldHost.Identity`.
  @spec canonical_json(term()) :: binary()
  defp canonical_json(value), do: Jason.encode!(deep_sort(value))

  defp deep_sort(value) when is_map(value) do
    value
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map(fn {k, v} -> {k, deep_sort(v)} end)
    |> Map.new()
  end

  defp deep_sort(value) when is_list(value), do: Enum.map(value, &deep_sort/1)
  defp deep_sort(value), do: value

  # ── Private helpers — crypto ────────────────────────────────────────────────

  # Sign a 32-byte digest with secp256k1 ECDSA, returning DER bytes.
  # `:crypto.sign(:ecdsa, :sha256, digest, key)` would re-hash; we want
  # the digest to be the message, so we use `{:digest, digest}` form.
  defp sign_digest(digest, private_key) when byte_size(digest) == 32 do
    :crypto.sign(:ecdsa, :sha256, {:digest, digest}, [private_key, :secp256k1])
  end

  # Verify a DER-encoded ECDSA signature over a 32-byte digest using a
  # compressed-or-uncompressed pubkey binary.
  defp verify_signature(digest, signature, public_key) when byte_size(digest) == 32 do
    :crypto.verify(:ecdsa, :sha256, {:digest, digest}, signature, [public_key, :secp256k1])
  end

  # Compress a public key. OTP's `:crypto.generate_key(:ecdh, :secp256k1)`
  # returns the uncompressed `04 || X || Y` form (65 bytes); compression
  # picks the parity prefix `02` (Y even) or `03` (Y odd).
  defp compress_public_key(<<4, x::binary-size(32), y::binary-size(32)>>) do
    prefix = if :binary.last(y) |> rem(2) == 0, do: <<2>>, else: <<3>>
    prefix <> x
  end

  # Already compressed — pass through.
  defp compress_public_key(<<prefix, _rest::binary-size(32)>> = bin) when prefix in [2, 3], do: bin

  # ── Private helpers — verification phases ───────────────────────────────────

  # Phase 1: BRC-100 signature + cert parse.
  defp check_signature_and_parse_cert(envelope) do
    with %{
           "x-brc100-identitykey" => identity_key_hex,
           "x-brc100-nonce" => _nonce,
           "x-brc100-timestamp" => _timestamp,
           "x-brc100-signature" => signature_hex,
           "x-brc52-certificate" => cert_json,
           "payload" => _payload
         } <- envelope,
         {:ok, identity_key_bytes} <- decode_hex(identity_key_hex, "brc100_bad_encoding"),
         {:ok, signature_bytes} <- decode_hex(signature_hex, "brc100_bad_encoding"),
         {:ok, cert} <- parse_cert(cert_json) do
      preimage_obj = %{
        "x-brc100-identitykey" => envelope["x-brc100-identitykey"],
        "x-brc100-nonce" => envelope["x-brc100-nonce"],
        "x-brc100-timestamp" => envelope["x-brc100-timestamp"],
        "payload" => envelope["payload"]
      }

      digest = :crypto.hash(:sha256, canonical_json(preimage_obj))

      if verify_signature(digest, signature_bytes, identity_key_bytes) do
        {:ok, cert}
      else
        {:error, "brc100_invalid_signature", "BRC-100 ECDSA signature verification failed"}
      end
    else
      %{} ->
        {:error, "brc100_missing_field",
         "BRC-100 envelope is missing required headers (identitykey, nonce, timestamp, signature, certificate)"}

      {:error, _code, _msg} = err ->
        err
    end
  end

  defp parse_cert(cert_json) when is_binary(cert_json) do
    case Jason.decode(cert_json) do
      {:ok, cert} when is_map(cert) -> {:ok, cert}
      _ -> {:error, "brc52_malformed_cert", "x-brc52-certificate is not valid JSON"}
    end
  end

  defp parse_cert(_), do: {:error, "brc52_malformed_cert", "x-brc52-certificate must be a JSON string"}

  # Phase 2a: cert_id == SHA-256(canonical preimage).
  defp check_cert_id(cert) do
    case Map.fetch(cert, "certId") do
      {:ok, stored_id} ->
        computed = Identity.compute_cert_id(cert)

        if stored_id == computed do
          :ok
        else
          {:error, "brc52_cert_id_mismatch",
           "BRC-52 cert_id mismatch: stored=#{String.slice(stored_id, 0, 16)}… computed=#{String.slice(computed, 0, 16)}…"}
        end

      :error ->
        {:error, "brc52_malformed_cert", "BRC-52 cert missing certId"}
    end
  end

  # Phase 2b: issuer signature over cert preimage including certId.
  defp check_issuer_signature(cert) do
    with {:ok, sig_hex} <- Map.fetch(cert, "signature") |> ok_or_missing("signature"),
         {:ok, certifier_hex} <-
           Map.fetch(cert, "certifierPublicKey") |> ok_or_missing("certifierPublicKey"),
         {:ok, sig_bytes} <- decode_hex(sig_hex, "brc52_issuer_signature_invalid"),
         {:ok, certifier_bytes} <- decode_hex(certifier_hex, "brc52_issuer_signature_invalid") do
      issuer_preimage =
        cert
        |> Map.take([
          "certId",
          "certifierPublicKey",
          "fields",
          "serialNumber",
          "subjectPublicKey",
          "type"
        ])

      digest = :crypto.hash(:sha256, canonical_json(issuer_preimage))

      if verify_signature(digest, sig_bytes, certifier_bytes) do
        :ok
      else
        {:error, "brc52_issuer_signature_invalid",
         "BRC-52 cert issuer signature verification failed"}
      end
    end
  end

  defp ok_or_missing({:ok, _} = ok, _field), do: ok
  defp ok_or_missing(:error, field), do: {:error, "brc52_malformed_cert", "missing #{field}"}

  # Phase 2c: identity binding — envelope identitykey == cert.subjectPublicKey.
  defp check_identity_binding(envelope, cert) do
    identity_key_hex = Map.get(envelope, "x-brc100-identitykey", "")
    subject_hex = Map.get(cert, "subjectPublicKey", "")

    if identity_key_hex == subject_hex and identity_key_hex != "" do
      :ok
    else
      {:error, "brc52_identity_binding_mismatch",
       "x-brc100-identitykey does not match certificate.subjectPublicKey (K2 binding check failed)"}
    end
  end

  # Phase 3: capability UTXO check. The mock honours a process-dict hook
  # so a test can flip the cap_token outcome without booting an SPV provider.
  defp check_cap_token(nil), do: :ok

  defp check_cap_token(_cap) do
    case Process.get(:verifier_mock_cap_token, :accept) do
      :accept -> :ok
      :reject -> {:error, "capability_utxo_spent", "capability UTXO is spent or SPV proof invalid"}
      {:reject, code, message} -> {:error, code, message}
    end
  end

  defp decode_hex(hex, code) when is_binary(hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, code, "value is not valid hex"}
    end
  end

  defp decode_hex(_, code), do: {:error, code, "value is not a hex string"}

  # ── Private helpers — fixture defaults ──────────────────────────────────────

  defp default_serial(subject_keys, certifier_keys, type) do
    seed = "#{subject_keys.public_key_hex}:#{certifier_keys.public_key_hex}:#{type}"
    :crypto.hash(:sha256, seed) |> Base.encode16(case: :lower)
  end

  defp fresh_nonce do
    :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
  end

  # 16-byte BCA derived from the cert's subjectPublicKey. Matches the
  # shape D-V3's `WorldHost.VerifierClient.Http` returns (hex string).
  # Not the production BCA algorithm — the mock's job is to be
  # deterministic and structurally compatible, not to reimplement
  # core/cell-engine/src/bca.zig.
  defp derive_mock_bca(subject_pk_hex) do
    :crypto.hash(:sha256, "mock-bca:" <> subject_pk_hex)
    |> binary_part(0, 16)
    |> Base.encode16(case: :lower)
  end
end

```
