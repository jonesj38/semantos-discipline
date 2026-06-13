---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/socket.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.818036+00:00
---

# archive/apps-world-client/src/socket.ts

```ts
/**
 * WorldSocket — Phoenix WebSocket client with BRC-100 signed envelopes.
 *
 * Spec source:   docs/spec/protocol-v0.5.md §4 (Identity), §12.1 (SignedBundle).
 * Canonical terms:
 *   - SignedBundle (glossary id: signed-bundle)
 *   - BRC-100 (glossary id: brc-100)
 *   - BRC-52  (glossary id: brc-52)
 *   - cert_id (glossary id: cert-id)
 *
 * D-A2 deliverable — Phase 1b.
 *
 * Wire convention (from D-V3):
 *   - Socket connect params carry `signed_bundle` (full §12.1 envelope with
 *     x-brc100-identitykey, x-brc100-nonce, x-brc100-timestamp,
 *     x-brc100-signature, x-brc52-certificate, payload) + optional `cap_token`.
 *   - Every outbound action carries `cert_id` (D-A1 rename; the legacy random-id path is removed).
 *   - Server signs responses; client verifies before delivering to subscribers.
 *
 * BRC compliance:
 *   BRC-100 — signed-request standard (signed_bundle envelope on connect
 *              + every emitted action message).
 *   BRC-52  — BRC-52 cert carried in x-brc52-certificate (cert_id =
 *              SHA-256 of canonical preimage).
 *   BRC-42  — key derivation delegated to IdentityProvider (D-A3 Helm will
 *              supply the real BRC-42 child-key derivation).
 */

import { Socket, type Channel } from "phoenix";
import type { WorldFrame, EntityAction } from "./types";
import {
  buildSignedBundle,
  verifyInboundEnvelope,
  type RawSignedBundle,
} from "@semantos/world-sdk/signed-bundle";
import {
  EphemeralIdentityProvider,
  type IdentityProvider,
} from "./identity-provider";

// ── Re-export IdentityProvider so callers can import from a single place ──
export type { IdentityProvider, Brc52Certificate } from "./identity-provider";
export { EphemeralIdentityProvider } from "./identity-provider";

// ── Handlers ──────────────────────────────────────────────────────────────

export interface WorldSocketHandlers {
  onSnapshot(frame: Extract<WorldFrame, { kind: "snapshot" }>): void;
  onTickDelta(frame: Extract<WorldFrame, { kind: "tick_delta" }>): void;
  onEntitySpawn(frame: Extract<WorldFrame, { kind: "entity_spawn" }>): void;
  onEntityDespawn(frame: Extract<WorldFrame, { kind: "entity_despawn" }>): void;
  onActionResult(frame: Extract<WorldFrame, { kind: "entity_action_result" }>): void;
  onStatus(status: string): void;
}

// Re-export for callers that import these from socket.ts directly.
export type { RawSignedBundle } from "@semantos/world-sdk/signed-bundle";
export { buildSignedBundle, verifyInboundEnvelope } from "@semantos/world-sdk/signed-bundle";

// ── WorldSocket ───────────────────────────────────────────────────────────

export class WorldSocket {
  private socket: Socket;
  private channel: Channel | null = null;

  /**
   * The cert_id for this session, derived from the IdentityProvider's cert.
   * Set at construction time (synchronously available — no connect() needed).
   *
   * Canonical wire field name: cert_id (per §12.1, D-A1 renaming).
   */
  public readonly certId: string;

  /**
   * The identity provider for this session.
   * Exposed so callers (D-A3 Helm) can introspect the cert.
   */
  public readonly identityProvider: IdentityProvider;

  constructor(
    private readonly regionId: string,
    private readonly handlers: WorldSocketHandlers,
    identityProvider?: IdentityProvider,
  ) {
    // Use provided IdentityProvider or fall back to ephemeral (dev/test).
    this.identityProvider = identityProvider ?? new EphemeralIdentityProvider();
    // getCert() is synchronous for EphemeralIdentityProvider and other signing
    // providers. Assert synchronous + non-null here; cert-manager providers
    // (IdentityStore) that return null/Promise must not be passed to WorldSocket.
    const certHandle = this.identityProvider.getCert();
    if (!certHandle || certHandle instanceof Promise) {
      throw new Error(
        "WorldSocket requires a synchronous signing IdentityProvider whose getCert() " +
        "returns a non-null cert synchronously. Use EphemeralIdentityProvider or PlexusIdentityProvider.",
      );
    }
    this.certId = certHandle.certId;

    // Build the §12.1 SignedBundle connect payload.
    // The connect payload is an empty object (the socket-level handshake
    // carries identity; application payloads come at the channel level).
    const connectBundle = buildSignedBundle(this.identityProvider, {});

    this.socket = new Socket("/socket", {
      params: {
        signed_bundle: JSON.stringify(connectBundle),
        // cert_id in params for server-side convenience (also in the bundle).
        cert_id: this.certId,
      },
      logger: () => {},
    });
    this.socket.onOpen(() => handlers.onStatus("open"));
    this.socket.onClose(() => handlers.onStatus("closed"));
    this.socket.onError(() => handlers.onStatus("error"));
  }

  connect() {
    this.socket.connect();

    const topic = `world:region:${this.regionId}`;
    // Dev stub cap_token: world_channel.ex requires SOME cap_token at
    // join (D-A1 hardening) but the verifier sidecar's Phase 3 SPV path
    // is a no-op without a configured SpvProvider, so any well-shaped
    // CapabilityTokenRef is accepted in dev. Real BRC-108 cap UTXOs come
    // from the wallet (gap 1 — tracked separately).
    this.channel = this.socket.channel(topic, {
      cap_token: {
        txId: "00".repeat(32),
        vout: 0,
      },
    });

    // Inbound message handlers — verify server signature before delivery.
    this.channel.on("snapshot", (raw: unknown) => {
      if (!this._acceptInbound(raw, "snapshot")) return;
      const payload = this._extractPayload(raw);
      this.handlers.onSnapshot({ kind: "snapshot", ...(payload as Record<string, unknown>) } as Extract<WorldFrame, { kind: "snapshot" }>);
    });

    this.channel.on("tick_delta", (raw: unknown) => {
      if (!this._acceptInbound(raw, "tick_delta")) return;
      this.handlers.onTickDelta(this._extractPayload(raw) as Extract<WorldFrame, { kind: "tick_delta" }>);
    });

    this.channel.on("entity_spawn", (raw: unknown) => {
      if (!this._acceptInbound(raw, "entity_spawn")) return;
      this.handlers.onEntitySpawn(this._extractPayload(raw) as Extract<WorldFrame, { kind: "entity_spawn" }>);
    });

    this.channel.on("entity_despawn", (raw: unknown) => {
      if (!this._acceptInbound(raw, "entity_despawn")) return;
      this.handlers.onEntityDespawn(this._extractPayload(raw) as Extract<WorldFrame, { kind: "entity_despawn" }>);
    });

    this.channel.on("entity_action_result", (raw: unknown) => {
      if (!this._acceptInbound(raw, "entity_action_result")) return;
      this.handlers.onActionResult(this._extractPayload(raw) as Extract<WorldFrame, { kind: "entity_action_result" }>);
    });

    this.channel.join()
      .receive("ok", () => {
        this.handlers.onStatus("joined");
      })
      .receive("error", (resp: unknown) =>
        this.handlers.onStatus(`join_error:${JSON.stringify(resp)}`)
      )
      .receive("timeout", () => this.handlers.onStatus("join_timeout"));
  }

  /**
   * Send an entity action with a BRC-100 signed envelope.
   *
   * Per D-A2 requirements: every outbound action carries a valid BRC-100
   * signature and includes `cert_id` (D-A1 wire-key rename).
   *
   * Strict mode: the channel reply MUST also be a §12.1 SignedBundle
   * envelope from the host. Unsigned or signature-invalid replies are
   * rejected.
   */
  sendAction(action: EntityAction): Promise<unknown> {
    if (!this.channel) return Promise.reject(new Error("not connected"));

    // Build the signed action payload per §12.1.
    // cert_id is included in the payload (D-A1 wire key rename).
    const actionWithCertId = {
      ...action,
      cert_id: this.certId,
    };
    const envelope = buildSignedBundle(this.identityProvider, actionWithCertId);

    return new Promise((resolve, reject) => {
      this.channel!.push("entity_action", envelope as unknown as object)
        .receive("ok", (raw: unknown) => {
          if (!this._acceptInbound(raw, "entity_action.reply")) {
            reject(new Error("entity_action reply failed signature verification"));
            return;
          }
          resolve(this._extractPayload(raw));
        })
        .receive("error", reject)
        .receive("timeout", () => reject(new Error("timeout")));
    });
  }

  disconnect() {
    this.channel?.leave();
    this.socket.disconnect();
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  /**
   * Verify a server-signed inbound message and decide whether to accept.
   *
   * Strict mode: the server is required to wrap every push in a §12.1
   * SignedBundle envelope (host-side `WorldHost.SignedBundle.build/1`).
   * Anything missing the BRC-100 headers, or with an invalid signature,
   * is dropped.
   */
  private _acceptInbound(raw: unknown, event: string): boolean {
    if (!raw || typeof raw !== "object") {
      console.warn(`[WorldSocket] inbound "${event}" dropped: not an object`);
      return false;
    }
    const env = raw as Record<string, unknown>;

    if (!("x-brc100-identitykey" in env) || !("x-brc100-signature" in env)) {
      console.warn(
        `[WorldSocket] inbound "${event}" dropped: missing BRC-100 headers (strict mode)`,
      );
      return false;
    }

    if (!verifyInboundEnvelope(raw)) {
      console.warn(
        `[WorldSocket] inbound "${event}" dropped: BRC-100 signature invalid`,
        { identityKey: env["x-brc100-identitykey"] },
      );
      return false;
    }

    return true;
  }

  /**
   * Extract the application payload from an inbound message.
   *
   * If the message is a §12.1 envelope, return `envelope.payload`.
   * If the message is a plain Phoenix payload (no BRC-100 headers), return
   * it as-is (backward-compatible with pre-D-A2 server side).
   */
  private _extractPayload(raw: unknown): unknown {
    if (!raw || typeof raw !== "object") return raw;
    const env = raw as Record<string, unknown>;
    if ("x-brc100-identitykey" in env && "payload" in env) {
      return env["payload"];
    }
    return raw;
  }
}

```
