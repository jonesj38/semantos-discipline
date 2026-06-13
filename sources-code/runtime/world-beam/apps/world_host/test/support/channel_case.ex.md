---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/test/support/channel_case.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.328956+00:00
---

# runtime/world-beam/apps/world_host/test/support/channel_case.ex

```ex
defmodule WorldHostWeb.ChannelCase do
  @moduledoc """
  Test case template for `Phoenix.Channel` tests.

  Imports `Phoenix.ChannelTest` and aliases the host app's endpoint so
  individual tests can `connect/3`, `subscribe_and_join/3`, and assert
  on `push`/`broadcast` traffic without rebuilding the boilerplate.

  Channel tests run with `async: false` because they share the
  application-level supervision tree (`WorldHost.PubSub`, the registries
  under `WorldHost.RegionSupervisor`, etc.). Two tests racing to start
  or stop the same `region-XYZ` would interfere.

  ## D-V3 / D-A1 — connect helpers

  Every connect requires a `signed_bundle` param shaped like a §12.1
  envelope. D-A1's mock (`WorldHost.VerifierClient.Mock`) verifies the
  bundle's BRC-100 signature, BRC-52 cert authenticity, and identity
  binding locally using `:crypto` — so test envelopes must be **really
  signed** by a keypair the test owns.

  Two helpers:

    * `mock_connect_params/1` — hash a string seed into a deterministic
      keypair, mint a real BRC-52 cert + BRC-100 SignedBundle, and
      return them in a `signed_bundle` param. The cert's `certId` is
      the *real* SHA-256-of-canonical-preimage value (deterministic
      per-seed because the keypair is deterministic per-seed).

    * `mock_join_params/1` — convenience for join params that need a
      cap_token. The cap_token is a syntactic-only object whose
      accept/reject behaviour is driven by the
      `:verifier_mock_cap_token` process-dict hook.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import WorldHostWeb.ChannelCase

      @endpoint WorldHostWeb.Endpoint
    end
  end

  alias WorldHost.Test.SignedBundleFixture

  @doc """
  Build a connect-time params map: a `signed_bundle` containing a real
  BRC-52 cert + BRC-100-signed envelope, where the keypair is
  derived deterministically from `seed`.

  Deterministic-from-seed means two calls with the same seed produce
  the same `cert_id`, which keeps tests that compare cert_ids stable.
  The keypair is **real** — the bundle's signature is a genuine
  secp256k1 ECDSA signature over the canonical preimage.
  """
  def mock_connect_params(seed) when is_binary(seed) do
    %{bundle: bundle} = build_fixture(seed)
    %{"signed_bundle" => bundle}
  end

  @doc """
  Build a join-time params map carrying a `cap_token`. The token's
  payload is a syntactic stub; whether `WorldHost.VerifierClient.Mock`
  accepts or rejects it is controlled by the `:verifier_mock_cap_token`
  process-dict hook (default `:accept`).
  """
  def mock_join_params(seed \\ "default-cap") when is_binary(seed) do
    %{
      "cap_token" => %{
        "txId" => :crypto.hash(:sha256, "cap-tx:" <> seed) |> Base.encode16(case: :lower),
        "vout" => 0
      }
    }
  end

  @doc """
  Internal: build a deterministic-per-seed fixture (keys, cert, bundle).

  Tests that need both the bundle and the cert subject (e.g. to assert
  a particular cert_id) can call this helper directly:

      %{bundle: bundle, cert: cert, keys: keys} = build_fixture("alice")
  """
  def build_fixture(seed) when is_binary(seed) do
    keys = deterministic_keys(seed)
    cert = SignedBundleFixture.build_cert(keys, keys, type: "plexus.identity.test", fields: %{"seed" => seed})
    bundle = SignedBundleFixture.build_envelope(keys, cert)
    %{bundle: bundle, cert: cert, keys: keys}
  end

  # Derive a deterministic-but-real secp256k1 keypair from a seed string.
  # `:crypto.generate_key/3` accepts an explicit private scalar — we
  # SHA-256 the seed to get 32 bytes that are statistically guaranteed
  # to be a valid scalar (probability of collision with the curve order
  # is 2⁻¹²⁸-ish).
  defp deterministic_keys(seed) do
    private_key = :crypto.hash(:sha256, "mock-keypair:" <> seed)
    {public_key, ^private_key} = :crypto.generate_key(:ecdh, :secp256k1, private_key)

    %{
      private_key: private_key,
      public_key: public_key,
      public_key_hex: compress(public_key) |> Base.encode16(case: :lower)
    }
  end

  defp compress(<<4, x::binary-size(32), y::binary-size(32)>>) do
    prefix = if :binary.last(y) |> rem(2) == 0, do: <<2>>, else: <<3>>
    prefix <> x
  end

  defp compress(<<prefix, _::binary-size(32)>> = bin) when prefix in [2, 3], do: bin
end

```
