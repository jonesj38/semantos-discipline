---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host_web/world_channel.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.315374+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host_web/world_channel.ex

```ex
defmodule WorldHostWeb.WorldChannel do
  @moduledoc """
  One Phoenix Channel topic per region. On join: subscribe to PubSub,
  push snapshot, spawn avatar. On terminate: despawn avatar.

  ## D-A1 — cert-bound identity at every action

  D-V3 wired `WorldHostWeb.UserSocket.connect/3` to the Verifier
  Sidecar; the verified `cert_id` lands on `socket.assigns.cert_id`.
  D-A1 makes that cert_id the **only** valid controller identifier on
  every channel-level action: the pre-D-V3 random-identifier wire key
  is gone, the legacy fallback in `controller_id_for/1` is gone, and
  any socket that reaches `join/3` without `cert_id` is refused.

  ## D-A1 — cap_token at the channel-join boundary

  Connect-time verification (D-V3) authenticates the principal. The
  cap_token authorises that principal for a *specific topic* — i.e. for
  the channel they're trying to join. Per
  `docs/spec/protocol-v0.5.md` §9.5 (Verifier Sidecar) the cap_token
  carries Phase-3 SPV checks (BRC-74 BUMP + BRC-95 atomic-BEEF +
  liveness); when present, the verifier confirms the capability UTXO
  is unspent before the channel join is accepted. When absent, the
  join is refused unless the topic is explicitly capability-free.

  ## Spec source

    - `docs/spec/protocol-v0.5.md` §4.2 (BRC-52 cert structure)
    - `docs/spec/protocol-v0.5.md` §9.5 (Verifier Sidecar)
    - `docs/spec/protocol-v0.5.md` §12.1 (SignedBundle envelope)

  ## K invariant

  K2 — every state-changing transition requires successful identity
  verification. `connect/3` enforces the BRC-100 boundary; `join/3`
  enforces the capability boundary; `handle_in("entity_action", ...)`
  enforces ownership against the entity's controller (cert_id).
  """
  use WorldHostWeb, :channel

  alias WorldHost.{Avatar, Region, SignedBundle}

  @impl true
  def join("world:region:" <> region_id, params, socket) do
    # D-A1: refuse the join if the socket has no verified cert_id.
    # connect/3 should always set this when verification succeeds, so a
    # missing value here means the connect path was bypassed (test
    # configuration drift, transport hack, etc.). Fail closed.
    case socket.assigns[:cert_id] do
      nil ->
        {:error, %{reason: "unauthenticated", detail: "missing cert_id on socket"}}

      cert_id when is_binary(cert_id) ->
        case authorise_join(socket, params) do
          :ok ->
            topic = Region.topic(region_id)
            :ok = Phoenix.PubSub.subscribe(WorldHost.PubSub, topic)
            send(self(), {:after_join, region_id})

            socket =
              socket
              |> assign(:region_id, region_id)
              |> assign(:avatar_entity_id, nil)

            {:ok, socket}

          {:error, detail} ->
            {:error, detail}
        end
    end
  end

  def join(topic, _params, _socket) do
    {:error, %{reason: "unknown_topic", topic: topic}}
  end

  @impl true
  def handle_info({:after_join, region_id}, socket) do
    snapshot =
      try do
        Region.snapshot(region_id)
      catch
        :exit, _ -> %{error: "region_not_found"}
      end

    signed_push(socket, "snapshot", snapshot)

    # If the region GenServer is missing (e.g. demo bootstrap failed), the
    # spawn call exits. Match the defensiveness of `Region.snapshot/1` above
    # and `handle_in("entity_action", ...)` below: surface a "spawn_failed"
    # frame to the client and keep the channel alive in an unspawned state
    # rather than crashing it into a reconnect loop. `assigns.avatar_entity_id`
    # stays nil, which `terminate/2` uses as the guard against a phantom despawn.
    #
    # D-A1: the controller identifier is the verified cert_id on the
    # socket (set by `WorldHostWeb.UserSocket.connect/3` via the
    # Verifier Sidecar). join/3 already refused any socket that lacked
    # one, so `controller_id_for/1` is total here.
    socket =
      try do
        case Avatar.spawn_for_session(region_id, controller_id_for(socket)) do
          {:ok, entity_id} ->
            signed_push(socket, "you_are", %{entity_id: entity_id})
            assign(socket, :avatar_entity_id, entity_id)

          {:error, detail} ->
            signed_push(socket, "spawn_failed", %{reason: "spawn_returned_error", detail: detail})
            socket

          _ ->
            signed_push(socket, "spawn_failed", %{reason: "spawn_returned_error"})
            socket
        end
      catch
        :exit, _ ->
          signed_push(socket, "spawn_failed", %{reason: "region_not_available"})
          socket
      end

    {:noreply, socket}
  end

  # Region.broadcast_* signs once and fans the same envelope out via
  # PubSub. We just forward the pre-signed envelope to this socket.
  def handle_info({:world_frame, kind, envelope}, socket) do
    push(socket, kind, envelope)
    {:noreply, socket}
  end

  @impl true
  def handle_in("entity_action", payload, socket) do
    region_id = socket.assigns.region_id
    controller_id = controller_id_for(socket)

    # D-A1: the action's authorisation wire key is `cert_id`, sourced
    # from the verified cert_id on the socket. `WorldHost.Entity.handle_call({:apply_action, ...})`
    # matches this against the entity's `controller` to enforce ownership (K2).
    # Per `docs/spec/protocol-v0.5.md` §4.2 (BRC-52 cert) and §9.5
    # (Verifier Sidecar).
    #
    # The client wraps the action in a §12.1 SignedBundle envelope before
    # sending. The connect-time sidecar verification already authenticated
    # the principal and bound their cert_id to `socket.assigns`, so we
    # trust that cert_id and just extract the inner action payload here.
    # (Per-action BRC-100 signature verification is a strict-mode
    # hardening pass tracked separately.)
    inner_action = unwrap_envelope(payload)
    action = Map.put(inner_action, "cert_id", controller_id)

    result =
      try do
        Region.apply_action(region_id, action)
      catch
        :exit, _ -> {:error, %{reason: "region_not_available"}}
      end

    reply_payload =
      case result do
        {:ok, delta} -> %{ok: true, delta: delta}
        {:error, detail} -> Map.merge(%{ok: false}, detail)
      end

    {:reply, {:ok, SignedBundle.build(reply_payload)}, socket}
  end

  def handle_in(event, _payload, socket) do
    Logger.debug("unhandled channel event: #{event}")
    {:reply, {:error, %{reason: "unknown_event", event: event}}, socket}
  end

  # ── Push helpers ──────────────────────────────────────────────────

  defp signed_push(socket, event, payload) do
    push(socket, event, SignedBundle.build(payload))
  end

  # Inbound from the client may arrive wrapped in a §12.1 SignedBundle
  # envelope (the production path) or as a raw map (legacy/test path).
  # If we see BRC-100 headers + a "payload" field, unwrap; otherwise
  # treat the map as the raw action.
  defp unwrap_envelope(%{"x-brc100-identitykey" => _, "payload" => inner}) when is_map(inner),
    do: inner

  defp unwrap_envelope(other) when is_map(other), do: other

  @impl true
  def terminate(_reason, socket) do
    region_id = socket.assigns[:region_id]
    controller_id = controller_id_for(socket)
    avatar_entity_id = socket.assigns[:avatar_entity_id]

    # Only despawn if `:after_join` actually completed a spawn — otherwise
    # there's nothing to clean up and the despawn call would just exit on a
    # missing region GenServer (same dead-region condition that took us here).
    # The inner try/catch is belt-and-braces for the case where the region
    # died after spawn but before disconnect.
    if region_id && controller_id && avatar_entity_id do
      try do
        Avatar.despawn_for_session(region_id, controller_id)
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end

  # D-A1: the avatar controller-id is the verified cert_id, sourced
  # solely from `socket.assigns.cert_id` (set by
  # `WorldHostWeb.UserSocket.connect/3`). The pre-D-V3 random-identifier
  # fallback path is removed — a socket without `cert_id` is rejected at
  # join/3 before this function ever sees it.
  defp controller_id_for(socket) do
    socket.assigns[:cert_id]
  end

  # D-A1: lift cap_token verification from connect/3 to join/3.
  #
  # Connect authenticates the principal; join authorises them for the
  # specific channel topic via the cap_token. Per
  # `docs/spec/protocol-v0.5.md` §9.5 (Verifier Sidecar), the sidecar
  # runs Phase-3 SPV checks (BRC-74 BUMP + BRC-95 atomic-BEEF + liveness)
  # whenever a cap_token is present.
  #
  # Behaviour:
  #   * `cap_token` absent → join is refused with `unauthorised`.
  #   * `cap_token` present and the verifier returns `ok: false` → join
  #     is refused, propagating the verifier's structured `code` /
  #     `message` so the client can react.
  #   * `cap_token` present and the verifier returns `ok: true` → :ok.
  #
  # The verifier is invoked through the same `WorldHost.VerifierClient`
  # behaviour that connect/3 uses, so test-time mocking (configured via
  # `:world_host, :verifier_client`) covers join/3 too.
  defp authorise_join(socket, params) do
    case parse_cap_token(params) do
      {:ok, nil} ->
        {:error,
         %{
           reason: "unauthorised",
           code: "cap_token_missing",
           detail: "join requires a `cap_token` param (see protocol-v0.5.md §9.5)"
         }}

      {:ok, cap_token} ->
        cert_id = socket.assigns[:cert_id]

        case WorldHost.VerifierClient.verify_cap_token(cert_id, cap_token) do
          %{ok: true} ->
            :ok

          %{ok: false, code: code, message: message} ->
            {:error,
             %{
               reason: "unauthorised",
               code: code,
               detail: message
             }}
        end

      {:error, detail} ->
        {:error,
         %{
           reason: "unauthorised",
           code: "cap_token_malformed",
           detail: detail
         }}
    end
  end

  # Parse a `cap_token` join param. Mirrors the connect-time parsing in
  # `WorldHostWeb.UserSocket.parse_cap_token/1` but distinguishes a
  # missing token from a malformed one (connect tolerated `nil`; join
  # treats it as a hard failure).
  defp parse_cap_token(params) do
    case Map.get(params, "cap_token") do
      nil ->
        {:ok, nil}

      cap when is_map(cap) ->
        {:ok, cap}

      cap when is_binary(cap) ->
        case Jason.decode(cap) do
          {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
          _ -> {:error, "`cap_token` is not valid JSON"}
        end

      _ ->
        {:error, "`cap_token` must be a JSON object or JSON-encoded string"}
    end
  end

end

```
