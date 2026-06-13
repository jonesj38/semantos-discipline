---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/test/world_host/signed_bundle_test.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.327698+00:00
---

# runtime/world-beam/apps/world_host/test/world_host/signed_bundle_test.exs

```exs
defmodule WorldHost.SignedBundleTest do
  @moduledoc """
  Tests for `WorldHost.SignedBundle` — the host-side BRC-100 §12.1
  envelope builder.

  Coverage:

  1. Wire shape — every required header is present, types are correct.
  2. Round-trip — the built signature verifies against the embedded
     identitykey using the same canonical preimage (i.e. server can
     verify its own envelope, and so can the client).
  3. Per-call uniqueness — nonce + timestamp + signature differ across
     two builds of the same payload.
  4. Cert embedding — the embedded x-brc52-certificate is the host's
     self-signed cert and round-trips through Jason decode.

  The TS counterpart is `apps/world-client/src/socket-signing.test.ts`.
  """

  use ExUnit.Case, async: false

  alias WorldHost.{HostIdentity, SignedBundle}

  setup do
    # Each test runs against a freshly generated host identity to keep
    # nonce/key reasoning local to the test.
    HostIdentity.reset!()
    :ok
  end

  describe "build/1 wire shape" do
    test "returns all five §12.1 headers + payload" do
      env = SignedBundle.build(%{"hello" => "world"})

      assert is_binary(env["x-brc100-identitykey"])
      assert is_binary(env["x-brc100-nonce"])
      assert is_integer(env["x-brc100-timestamp"])
      assert is_binary(env["x-brc100-signature"])
      assert is_binary(env["x-brc52-certificate"])
      assert env["payload"] == %{"hello" => "world"}
    end

    test "identitykey is 33 bytes (compressed secp256k1) hex-encoded" do
      env = SignedBundle.build(%{})
      key_bytes = Base.decode16!(env["x-brc100-identitykey"], case: :lower)
      assert byte_size(key_bytes) == 33
      assert <<prefix::8, _rest::binary-size(32)>> = key_bytes
      assert prefix in [0x02, 0x03]
    end

    test "nonce is 32 bytes hex-encoded" do
      env = SignedBundle.build(%{})
      nonce_bytes = Base.decode16!(env["x-brc100-nonce"], case: :lower)
      assert byte_size(nonce_bytes) == 32
    end

    test "timestamp is within ~1s of now" do
      now = System.system_time(:millisecond)
      env = SignedBundle.build(%{})
      assert abs(env["x-brc100-timestamp"] - now) < 1_000
    end
  end

  describe "round-trip verification" do
    test "the built signature verifies against the embedded identitykey" do
      payload = %{"kind" => "tick_delta", "tick_seq" => 42}
      env = SignedBundle.build(payload)

      preimage = canonical_brc100_preimage(env)
      # Double-hash to match @bsv/sdk's signing convention (see
      # SignedBundle.build for the rationale).
      digest1 = :crypto.hash(:sha256, preimage)

      identity_key_bytes = Base.decode16!(env["x-brc100-identitykey"], case: :lower)
      signature_bytes = Base.decode16!(env["x-brc100-signature"], case: :lower)

      # Pass digest1 (without {:digest, ...}) so :crypto.verify hashes it
      # once internally — yielding sha256(sha256(preimage)) which is what
      # the signature was computed over.
      assert :crypto.verify(
               :ecdsa,
               :sha256,
               digest1,
               signature_bytes,
               [identity_key_bytes, :secp256k1]
             )
    end

    test "tampering with the payload breaks verification" do
      env = SignedBundle.build(%{"x" => 1})
      tampered = Map.put(env, "payload", %{"x" => 2})

      preimage = canonical_brc100_preimage(tampered)
      digest = :crypto.hash(:sha256, preimage)

      identity_key_bytes = Base.decode16!(env["x-brc100-identitykey"], case: :lower)
      signature_bytes = Base.decode16!(env["x-brc100-signature"], case: :lower)

      refute :crypto.verify(
               :ecdsa,
               :sha256,
               {:digest, digest},
               signature_bytes,
               [identity_key_bytes, :secp256k1]
             )
    end
  end

  describe "per-call uniqueness" do
    test "two builds of the same payload yield different nonces and signatures" do
      payload = %{"same" => true}
      a = SignedBundle.build(payload)
      b = SignedBundle.build(payload)

      assert a["x-brc100-identitykey"] == b["x-brc100-identitykey"]
      assert a["x-brc100-nonce"] != b["x-brc100-nonce"]
      assert a["x-brc100-signature"] != b["x-brc100-signature"]
    end
  end

  describe "JS-compatibility (float normalisation)" do
    # JS has no float/int distinction — `JSON.stringify(0.0)` is `"0"`,
    # but Elixir's Jason encodes `0.0` as `"0.0"`. World deltas carry
    # `position: [0.0, 0.0, 0.0]`, so without normalisation our signing
    # preimage diverges from what the client computes after JSON
    # round-trip, every frame fails verification, and strict mode
    # silently drops them all.

    test "envelope with whole-number floats verifies (the regression)" do
      payload = %{
        "spatial" => %{
          "position" => [0.0, 0.0, 0.0],
          "orientation" => [0.0, 0.0, 0.0, 1.0]
        }
      }

      env = SignedBundle.build(payload)

      # Simulate the client: JSON round-trip the wire payload, then
      # rebuild the canonical preimage from the parsed value (which is
      # what `verifyInboundEnvelope` does on the JS side — JSON.parse
      # then JSON.stringify with sorted keys).
      wire_json = Jason.encode!(env)
      received = Jason.decode!(wire_json)
      client_payload = received["payload"]

      preimage =
        %{
          "payload" => client_payload,
          "x-brc100-identitykey" => env["x-brc100-identitykey"],
          "x-brc100-nonce" => env["x-brc100-nonce"],
          "x-brc100-timestamp" => env["x-brc100-timestamp"]
        }
        |> deep_sort()
        |> Jason.encode!()

      digest1 = :crypto.hash(:sha256, preimage)
      identity_key_bytes = Base.decode16!(env["x-brc100-identitykey"], case: :lower)
      signature_bytes = Base.decode16!(env["x-brc100-signature"], case: :lower)

      assert :crypto.verify(
               :ecdsa,
               :sha256,
               digest1,
               signature_bytes,
               [identity_key_bytes, :secp256k1]
             )
    end

    test "fractional floats are preserved (not truncated)" do
      payload = %{"x" => 0.5, "y" => 1.25}
      env = SignedBundle.build(payload)

      # Round-trip and verify — fractional values must survive.
      wire_json = Jason.encode!(env)
      received = Jason.decode!(wire_json)
      assert received["payload"] == %{"x" => 0.5, "y" => 1.25}

      preimage =
        %{
          "payload" => received["payload"],
          "x-brc100-identitykey" => env["x-brc100-identitykey"],
          "x-brc100-nonce" => env["x-brc100-nonce"],
          "x-brc100-timestamp" => env["x-brc100-timestamp"]
        }
        |> deep_sort()
        |> Jason.encode!()

      digest1 = :crypto.hash(:sha256, preimage)
      identity_key_bytes = Base.decode16!(env["x-brc100-identitykey"], case: :lower)
      signature_bytes = Base.decode16!(env["x-brc100-signature"], case: :lower)

      assert :crypto.verify(
               :ecdsa,
               :sha256,
               digest1,
               signature_bytes,
               [identity_key_bytes, :secp256k1]
             )
    end
  end

  describe "embedded cert" do
    test "x-brc52-certificate decodes to the host's self-signed cert" do
      env = SignedBundle.build(%{})
      cert = Jason.decode!(env["x-brc52-certificate"])

      assert cert["subjectPublicKey"] == env["x-brc100-identitykey"]
      assert cert["certifierPublicKey"] == cert["subjectPublicKey"]
      assert cert["type"] == "world-host"
      assert is_binary(cert["certId"])
      assert is_binary(cert["signature"])
      assert is_binary(cert["serialNumber"])
      assert cert["fields"] == %{}
    end

    test "embedded cert's certId matches recomputed certId (BRC-52)" do
      env = SignedBundle.build(%{})
      cert = Jason.decode!(env["x-brc52-certificate"])

      cert_for_id =
        cert
        |> Map.delete("certId")
        |> Map.delete("signature")

      assert cert["certId"] == WorldHost.Identity.compute_cert_id(cert_for_id)
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────

  # Reconstruct the canonical preimage from an envelope to verify its
  # signature. Mirrors socket.ts:buildBrc100Preimage and
  # SignedBundle.brc100_canonical_preimage exactly.
  defp canonical_brc100_preimage(env) do
    %{
      "payload" => env["payload"],
      "x-brc100-identitykey" => env["x-brc100-identitykey"],
      "x-brc100-nonce" => env["x-brc100-nonce"],
      "x-brc100-timestamp" => env["x-brc100-timestamp"]
    }
    |> deep_sort()
    |> Jason.encode!()
  end

  defp deep_sort(value) when is_map(value) do
    value
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.map(fn {k, v} -> {k, deep_sort(v)} end)
    |> Map.new()
  end

  defp deep_sort(value) when is_list(value), do: Enum.map(value, &deep_sort/1)

  # Mirror JS: whole-number floats serialise as integers.
  defp deep_sort(value) when is_float(value) do
    truncated = trunc(value)
    if value == truncated * 1.0, do: truncated, else: value
  end

  defp deep_sort(value), do: value
end

```
