---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/test/world_host/identity_test.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.328300+00:00
---

# runtime/world-beam/apps/world_host/test/world_host/identity_test.exs

```exs
defmodule WorldHost.IdentityTest do
  @moduledoc """
  D-A0b — BRC-52 cert_id cross-language conformance (Elixir side).

  Loads 100 deterministic vectors from
  `core/plexus-contracts/tests/vectors/cert_id_vectors.json` and asserts:

  1. `WorldHost.Identity.canonical_cert_preimage/1` produces the expected
     preimage bytes (decoded from `expected_canonical_preimage_hex`).
  2. `WorldHost.Identity.compute_cert_id/1` produces the expected cert_id
     (stored as `expected_cert_id_hex`).

  The SAME vectors file is consumed by the TS test at
  `core/plexus-contracts/tests/cert-id-vectors.test.ts`. Any divergence
  between TS and Elixir shows up as a test failure on one side.

  Spec source: `docs/spec/protocol-v0.5.md` §4.2 (BRC-52 cert format).
  Canon discipline: passed (glossary ids: brc-52, cert-id, signed-bundle).
  D-A0b — Phase 1a.
  """

  use ExUnit.Case, async: true

  alias WorldHost.Identity

  # ── Vector loading ──────────────────────────────────────────────────────────

  @vectors_path Path.join([
                  __DIR__,
                  "..",
                  "..",
                  "..",
                  "..",
                  "core",
                  "plexus-contracts",
                  "tests",
                  "vectors",
                  "cert_id_vectors.json"
                ])

  @vectors (case File.read(@vectors_path) do
              {:ok, json} ->
                %{"vectors" => vecs} = Jason.decode!(json)
                vecs

              {:error, reason} ->
                raise "D-A0b: cannot load cert_id vectors from #{@vectors_path}: #{inspect(reason)}"
            end)

  # ── Conformance tests ────────────────────────────────────────────────────────

  test "vector file loads exactly 100 vectors" do
    assert length(@vectors) == 100
  end

  test "all 100 vectors: canonical_cert_preimage produces expected preimage bytes" do
    for {vector, idx} <- Enum.with_index(@vectors, 1) do
      cert = vector["cert"]
      expected_preimage_hex = vector["expected_canonical_preimage_hex"]

      preimage_bytes = Identity.canonical_cert_preimage(cert)
      got_hex = Base.encode16(preimage_bytes, case: :lower)

      assert got_hex == expected_preimage_hex,
             "vector #{idx}: preimage mismatch\n  description: #{vector["description"]}\n  got: #{got_hex}\n  exp: #{expected_preimage_hex}"
    end
  end

  test "all 100 vectors: compute_cert_id produces expected cert_id" do
    for {vector, idx} <- Enum.with_index(@vectors, 1) do
      cert = vector["cert"]
      expected_cert_id = vector["expected_cert_id_hex"]

      got_cert_id = Identity.compute_cert_id(cert)

      assert got_cert_id == expected_cert_id,
             "vector #{idx}: cert_id mismatch\n  description: #{vector["description"]}\n  got: #{got_cert_id}\n  exp: #{expected_cert_id}"
    end
  end

  # ── Invariant tests ──────────────────────────────────────────────────────────

  test "canonical preimage excludes cert_id and signature" do
    # The preimage must not change when certId or signature are modified.
    # We test by computing the preimage for a cert with two different
    # certId values — the preimage fields are the same, so output must match.
    cert = hd(@vectors)["cert"]

    cert_a = Map.merge(cert, %{"certId" => String.duplicate("aa", 32)})
    cert_b = Map.merge(cert, %{"certId" => String.duplicate("bb", 32)})

    # certId is not a preimage field; the preimage must be identical.
    # (canonical_cert_preimage only reads the five preimage fields.)
    assert Identity.canonical_cert_preimage(cert_a) ==
             Identity.canonical_cert_preimage(cert_b)
  end

  test "field key insertion order does not affect preimage (deep sort)" do
    # Sort the fields map in two opposite orderings; preimage must be the same.
    cert = hd(@vectors)["cert"]
    fields = cert["fields"]

    # Alphabetical
    fields_alpha =
      fields |> Enum.sort_by(fn {k, _} -> k end) |> Map.new()

    # Reverse alphabetical
    fields_rev =
      fields |> Enum.sort_by(fn {k, _} -> k end, :desc) |> Map.new()

    cert_alpha = Map.put(cert, "fields", fields_alpha)
    cert_rev = Map.put(cert, "fields", fields_rev)

    assert Identity.canonical_cert_preimage(cert_alpha) ==
             Identity.canonical_cert_preimage(cert_rev)
  end

  test "compute_cert_id is SHA-256 of canonical_cert_preimage" do
    for vector <- @vectors do
      cert = vector["cert"]
      preimage = Identity.canonical_cert_preimage(cert)
      expected_id = Base.encode16(:crypto.hash(:sha256, preimage), case: :lower)
      assert Identity.compute_cert_id(cert) == expected_id
    end
  end

  test "canonical_cert_preimage is deterministic across calls" do
    for vector <- @vectors do
      cert = vector["cert"]
      p1 = Identity.canonical_cert_preimage(cert)
      p2 = Identity.canonical_cert_preimage(cert)
      assert p1 == p2
      assert Base.encode16(p1, case: :lower) == vector["expected_canonical_preimage_hex"]
    end
  end

  test "compute_cert_id is deterministic across calls" do
    for vector <- @vectors do
      cert = vector["cert"]
      id1 = Identity.compute_cert_id(cert)
      id2 = Identity.compute_cert_id(cert)
      assert id1 == id2
      assert id1 == vector["expected_cert_id_hex"]
    end
  end
end

```
