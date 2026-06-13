---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/identity.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.319393+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/identity.ex

```ex
defmodule WorldHost.Identity do
  @moduledoc """
  BRC-52 certificate types and canonical cert_id computation — Elixir mirror.

  This module is the Elixir counterpart of
  `core/plexus-contracts/src/identity.ts` (D-A0b deliverable, Phase 1a).

  It provides:

  - `t:brc52_cert/0` — the canonical BRC-52 certificate struct
    matching `Brc52Cert` in the TS contracts package.
  - `t:signed_bundle/0` — the SignedBundle<T> envelope struct matching
    `SignedBundle` in the TS contracts package (§12.1).
  - `canonical_cert_preimage/1` — deterministic preimage bytes; output
    is byte-identical to the TS `canonicalCertPreimage` function.
  - `compute_cert_id/1` — SHA-256(preimage), hex-encoded; byte-identical
    to the TS `computeCertId` function.

  ## Canonical preimage algorithm

  Per `docs/spec/protocol-v0.5.md` §4.2:

      cert_id = SHA-256(canonical_preimage)

  where the canonical preimage is a deterministic UTF-8 JSON serialisation
  of the cert fields **excluding** `signature` and `cert_id` (cert_id is the
  SHA-256 output — it cannot be part of its own input).

  The five fields included in the preimage, always in this sorted order:

      {
        "certifierPublicKey": "...",
        "fields":             { ... (keys sorted) ... },
        "serialNumber":       "...",
        "subjectPublicKey":   "...",
        "type":               "..."
      }

  All nested object keys are also sorted (deep sort). This matches the
  deep-sort approach in the TS verifier (`runtime/verifier-sidecar/src/verifier.ts`)
  and the TS canonical function in `core/plexus-contracts/src/identity.ts`.

  ## Cross-language conformance

  The 100-vector conformance suite lives at:
  `core/plexus-contracts/tests/vectors/cert_id_vectors.json`

  The Elixir test at `runtime/world-beam/apps/world_host/test/world_host/identity_test.exs`
  loads the SAME vectors file and asserts byte-identical output.

  ## D-V3 compatibility

  This module does NOT replace `WorldHost.VerifierClient` or
  `WorldHost.VerifierClient.Http`. Those modules dispatch to the TS
  Verifier Sidecar over loopback HTTP; the sidecar owns cert verification.
  This module provides canonical Elixir *types* for cert data that flows
  through Elixir after the sidecar has verified it (e.g. `socket.assigns.cert_id`).

  The `compute_cert_id/1` function is provided so Elixir-side code can
  re-derive a cert_id from field data (e.g. in tests and diagnostics)
  without going through the sidecar.

  ## Spec sources

  - `docs/spec/protocol-v0.5.md` §4.2 (BRC-52 cert format)
  - `docs/spec/protocol-v0.5.md` §4.4 (identity DAG)
  - `docs/spec/protocol-v0.5.md` §12.1 (SignedBundle envelope)
  - `docs/canon/glossary.yml` — ids: brc-52, cert-id, signed-bundle

  ## Canon discipline

  Aliases per `docs/canon/glossary.yml`:
  - cert_id (snake_case) — wire form; `certId` is the TS camelCase alias
  - BRC-52 cert — canonical (not "certificate" alone in Elixir contexts)
  - SignedBundle — PascalCase canonical for the type name
  """

  # ── BRC-52 certificate struct ───────────────────────────────────────────────

  @typedoc """
  BRC-52 certificate — the unit of identity in the Plexus DAG.

  Mirrors `Brc52Cert` in `core/plexus-contracts/src/identity.ts`.

  The `cert_id` field is `SHA-256(canonical_preimage)`. See
  `compute_cert_id/1` for the canonical derivation.

  Wire field names use camelCase in JSON (matching the TS convention);
  the struct uses snake_case for the Elixir keys. The JSON encoder must
  map `cert_id` → `"certId"`, `subject_public_key` → `"subjectPublicKey"`, etc.
  when serialising for the wire.
  """
  @type brc52_cert :: %{
          required(:cert_id) => String.t(),
          required(:subject_public_key) => String.t(),
          required(:certifier_public_key) => String.t(),
          required(:type) => String.t(),
          required(:serial_number) => String.t(),
          required(:fields) => %{optional(String.t()) => String.t()},
          required(:signature) => String.t()
        }

  @typedoc """
  SignedBundle envelope — mandatory wrapper for every cross-process or
  cross-node message (§12.1).

  Mirrors `SignedBundle<T>` in `core/plexus-contracts/src/identity.ts`.
  The `payload` field is opaque; its type is determined by the vertical.

  D-V3 convention: `signed_bundle` arrives as a JSON-decoded map in
  `WorldHostWeb.UserSocket.connect/3` params. The map keys remain as
  strings (matching HTTP header names) because Phoenix socket params are
  string-keyed maps.
  """
  @type signed_bundle :: %{
          required(String.t()) => term()
        }

  @typedoc """
  Verification header set (BRC-100 + BRC-52) as carried in a SignedBundle.

  All keys are string (matching HTTP/WebSocket param convention):
  - `"x-brc100-identitykey"` — 33-byte compressed pubkey, hex-encoded
  - `"x-brc100-nonce"` — 32-byte anti-replay nonce, hex-encoded
  - `"x-brc100-timestamp"` — milliseconds since epoch (integer or string)
  - `"x-brc100-signature"` — DER ECDSA signature, hex-encoded
  - `"x-brc52-certificate"` — JSON-serialised `brc52_cert`
  """
  @type verification_headers :: %{String.t() => term()}

  # ── Canonical preimage ──────────────────────────────────────────────────────

  @doc """
  Produce the canonical BRC-52 cert_id preimage bytes.

  Per `docs/spec/protocol-v0.5.md` §4.2, the preimage is the
  deterministic UTF-8 JSON of the five cert fields (all *except*
  `cert_id` and `signature`), with all object keys sorted at every
  nesting level (deep sort).

  The five fields in canonical sorted order:
  `certifierPublicKey`, `fields`, `serialNumber`, `subjectPublicKey`, `type`.

  Output is a binary (iodata-compatible). Pass to `:crypto.hash(:sha256, ...)`
  to obtain the cert_id.

  This function produces **byte-identical** output to the TS function
  `canonicalCertPreimage` in `core/plexus-contracts/src/identity.ts`.

  ## Preimage algorithm

  1. Build a map with the five preimage fields, using the camelCase wire-format
     key names (to match the TS JSON output).
  2. Sort all map keys at every nesting level (deep sort).
  3. Encode to compact JSON (no whitespace, no trailing newline).
  4. Return the UTF-8 binary.

  ## No uniqueness sources in preimage

  The preimage is 100% deterministic from the five cert fields.
  No timestamps, nonces, or process-level state appear here.

  ## Parameters

  The `cert` argument is a map with **either** TS camelCase keys
  (`"certifierPublicKey"`) or the five expected keys directly. The function
  accepts both forms:

    - TS wire form (camelCase string keys) — used when decoding JSON
    - Internal preimage form — plain map with the five fields

  In practice, callers almost always pass the TS wire-format map returned
  by `Jason.decode!/1` on the `x-brc52-certificate` JSON.
  """
  @spec canonical_cert_preimage(%{
          required(String.t()) => term()
        }) :: binary()
  def canonical_cert_preimage(cert) when is_map(cert) do
    preimage_map = %{
      "certifierPublicKey" => fetch_cert_field!(cert, "certifierPublicKey"),
      "fields" => fetch_cert_field!(cert, "fields"),
      "serialNumber" => fetch_cert_field!(cert, "serialNumber"),
      "subjectPublicKey" => fetch_cert_field!(cert, "subjectPublicKey"),
      "type" => fetch_cert_field!(cert, "type")
    }

    sorted = deep_sort_map(preimage_map)
    Jason.encode!(sorted)
  end

  @doc """
  Compute the BRC-52 cert_id for a certificate.

  cert_id = lowercase hex(SHA-256(canonical_cert_preimage(cert)))

  Returns a 64-character lowercase hex string (32 bytes).

  Uses `:crypto.hash(:sha256, ...)` from OTP — no new runtime deps.

  This function produces **byte-identical** output to the TS function
  `computeCertId` in `core/plexus-contracts/src/identity.ts`.

  ## Cross-language conformance

  Verified against 100 deterministic vectors in
  `core/plexus-contracts/tests/vectors/cert_id_vectors.json`.
  """
  @spec compute_cert_id(%{required(String.t()) => term()}) :: String.t()
  def compute_cert_id(cert) when is_map(cert) do
    preimage = canonical_cert_preimage(cert)
    :crypto.hash(:sha256, preimage) |> Base.encode16(case: :lower)
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  # Deep-sort a map (and any nested maps) by string key.
  # Arrays are left in their original order.
  # Mirrors the `deepSortObject` function in identity.ts.
  @spec deep_sort_map(term()) :: term()
  defp deep_sort_map(value) when is_map(value) do
    value
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.map(fn {k, v} -> {k, deep_sort_map(v)} end)
    |> Map.new()
  end

  defp deep_sort_map(value) when is_list(value) do
    Enum.map(value, &deep_sort_map/1)
  end

  defp deep_sort_map(value), do: value

  # Extract a field from the cert map, accepting camelCase string key.
  # Raises KeyError with a clear message on missing fields.
  @spec fetch_cert_field!(%{required(String.t()) => term()}, String.t()) :: term()
  defp fetch_cert_field!(cert, key) do
    case Map.fetch(cert, key) do
      {:ok, value} -> value
      :error -> raise KeyError, key: key, term: cert
    end
  end
end

```
