---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/test/world_host_web/world_channel_test.exs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.325244+00:00
---

# runtime/world-beam/apps/world_host/test/world_host_web/world_channel_test.exs

```exs
defmodule WorldHostWeb.WorldChannelTest do
  @moduledoc """
  Channel-level tests for `WorldHostWeb.WorldChannel`.

  Two clusters of behaviour:

    1. Channel-resilience (pre-D-A1, still relevant): `:after_join`
       runs against a region whose GenServer never started; channel
       must survive, push degraded payloads, and clean up on
       terminate without an exit chain.

    2. D-A1 — cert_id ownership at every action and cap_token
       authorisation at the channel-join boundary.

  The test config disables the demo bootstrap (`bootstrap_demo_region: false`
  in `config/test.exs`).

  Spec source: `docs/spec/protocol-v0.5.md` §4.2 (BRC-52 cert),
               §9.5 (Verifier Sidecar).
  K invariant: K2 — boundary verification before state mutation.
  """

  use WorldHostWeb.ChannelCase, async: false

  alias WorldHostWeb.{UserSocket, WorldChannel}

  @cert_seed "test-session-deadbeef"
  @missing_region "region-channel-resilience-missing"

  setup do
    # Default: real verification + accept the cap_token outcome.
    Process.put(:verifier_mock_mode, :verify)
    Application.put_env(:world_host, :verifier_mock_cap_token, :accept)
    Process.delete({:verifier_mock, :error})

    on_exit(fn ->
      Application.delete_env(:world_host, :verifier_mock_cap_token)
    end)

    # Sanity check: nothing else in the test suite should have started this
    # region. If it has, the test would silently pass for the wrong reason.
    refute Registry.lookup(WorldHost.RegionRegistry, @missing_region) != []
    :ok
  end

  describe "join + :after_join with a missing region" do
    test "channel survives, snapshot frame carries error, spawn_failed frame is pushed" do
      {:ok, socket} = connect(UserSocket, mock_connect_params(@cert_seed))

      {:ok, _reply, channel_socket} =
        subscribe_and_join(
          socket,
          WorldChannel,
          "world:region:" <> @missing_region,
          mock_join_params(@cert_seed)
        )

      assert_push("snapshot", %{error: "region_not_found"})
      assert_push("spawn_failed", %{reason: "region_not_available"})
      refute_push("you_are", _payload)

      assert Process.alive?(channel_socket.channel_pid)
      assert channel_socket.assigns.region_id == @missing_region
      assert channel_socket.assigns.avatar_entity_id == nil
    end

    test "terminate/2 does not crash when avatar_entity_id is nil" do
      Process.flag(:trap_exit, true)

      {:ok, socket} = connect(UserSocket, mock_connect_params(@cert_seed <> "-term"))

      {:ok, _reply, channel_socket} =
        subscribe_and_join(
          socket,
          WorldChannel,
          "world:region:" <> @missing_region,
          mock_join_params(@cert_seed <> "-term")
        )

      assert_push("snapshot", _)
      assert_push("spawn_failed", _)

      pid = channel_socket.channel_pid
      ref = Process.monitor(pid)

      assert :ok = close(channel_socket)

      assert_receive {:DOWN, ^ref, :process, ^pid, reason}, 1_000

      assert reason in [:shutdown, :normal, {:shutdown, :closed}],
             "expected a clean termination, got: #{inspect(reason)}"
    end
  end

  describe "join + :after_join with a live region" do
    setup do
      region_id = "region-channel-resilience-live-#{System.unique_integer([:positive])}"
      {:ok, _pid} = WorldHost.RegionSupervisor.start_region(region_id)

      on_exit(fn ->
        case Registry.lookup(WorldHost.RegionRegistry, region_id) do
          [{pid, _}] -> Process.exit(pid, :shutdown)
          _ -> :ok
        end
      end)

      %{region_id: region_id}
    end

    test "spawn succeeds, you_are pushed, avatar_entity_id assigned", %{region_id: region_id} do
      {:ok, socket} = connect(UserSocket, mock_connect_params(@cert_seed <> "-live"))

      {:ok, _reply, channel_socket} =
        subscribe_and_join(
          socket,
          WorldChannel,
          "world:region:" <> region_id,
          mock_join_params(@cert_seed <> "-live")
        )

      assert_push("snapshot", %{region_id: ^region_id})
      assert_push("you_are", %{entity_id: entity_id})
      refute_push("spawn_failed", _)

      :sys.get_state(channel_socket.channel_pid)
      assigns = :sys.get_state(channel_socket.channel_pid).assigns
      assert assigns.avatar_entity_id == entity_id
    end
  end

  # ── D-A1 — cap_token at channel join ──────────────────────────────────────

  describe "D-A1 join cap_token contract" do
    test "join without a cap_token is refused" do
      {:ok, socket} = connect(UserSocket, mock_connect_params("captest-missing"))

      assert {:error, %{reason: "unauthorised", code: "cap_token_missing"}} =
               subscribe_and_join(
                 socket,
                 WorldChannel,
                 "world:region:" <> @missing_region,
                 %{}
               )
    end

    test "join with a malformed cap_token (non-JSON string) is refused" do
      {:ok, socket} = connect(UserSocket, mock_connect_params("captest-malformed"))

      assert {:error, %{reason: "unauthorised", code: "cap_token_malformed"}} =
               subscribe_and_join(
                 socket,
                 WorldChannel,
                 "world:region:" <> @missing_region,
                 %{"cap_token" => "{ not json"}
               )
    end

    test "join with a cap_token the verifier rejects (UTXO spent) is refused" do
      Application.put_env(:world_host, :verifier_mock_cap_token, :reject)

      {:ok, socket} = connect(UserSocket, mock_connect_params("captest-spent"))

      assert {:error, %{reason: "unauthorised", code: "capability_utxo_spent"}} =
               subscribe_and_join(
                 socket,
                 WorldChannel,
                 "world:region:" <> @missing_region,
                 mock_join_params("captest-spent")
               )
    end

    test "join with a valid cap_token succeeds (verifier returns ok: true)" do
      {:ok, socket} = connect(UserSocket, mock_connect_params("captest-good"))

      # Joining a missing region still 'succeeds' at the channel level
      # (it surfaces snapshot/spawn_failed frames). The cap_token gate
      # is the contract under test here, not the region availability.
      assert {:ok, _reply, _channel_socket} =
               subscribe_and_join(
                 socket,
                 WorldChannel,
                 "world:region:" <> @missing_region,
                 mock_join_params("captest-good")
               )

      assert_push("snapshot", _)
    end
  end

  # ── D-A1 — cert_id is the wire key for entity_action ─────────────────────

  describe "D-A1 entity_action carries cert_id" do
    setup do
      region_id = "region-cert-id-action-#{System.unique_integer([:positive])}"
      {:ok, _pid} = WorldHost.RegionSupervisor.start_region(region_id)

      on_exit(fn ->
        case Registry.lookup(WorldHost.RegionRegistry, region_id) do
          [{pid, _}] -> Process.exit(pid, :shutdown)
          _ -> :ok
        end
      end)

      %{region_id: region_id}
    end

    test "entity_action from the channel sets cert_id (not session_id) on the action",
         %{region_id: region_id} do
      {:ok, socket} = connect(UserSocket, mock_connect_params("acts-as-cert"))

      {:ok, _, channel_socket} =
        subscribe_and_join(
          socket,
          WorldChannel,
          "world:region:" <> region_id,
          mock_join_params("acts-as-cert")
        )

      assert_push("you_are", %{entity_id: entity_id})

      ref =
        push(channel_socket, "entity_action", %{
          "entity_id" => entity_id,
          "op" => "move",
          "args" => %{"delta" => [1.0, 0.0, 0.0]},
          "action_id" => "a1"
        })

      # Ownership-gated. If `controller` were keyed off a non-cert_id
      # value (e.g. a stale session_id) the apply would come back with
      # `not_authoritative`. The pass condition here is `ok: true`.
      assert_reply ref, :ok, %{ok: true}
    end
  end
end

```
