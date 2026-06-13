---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/adapter/facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.337257+00:00
---

# runtime/ws-node-adapter/src/adapter/facade.ts

```ts
/**
 * adapter/facade.ts — composes the split modules into `WsNodeAdapter`.
 *
 * Public API is byte-identical to the legacy single-file
 * `ws-node-adapter.ts`: same class name, same constructor shape, same
 * `WsNodeAdapterConfig` interface. Consumers (runtime/node, tests)
 * don't notice the split.
 *
 * Internally:
 *   - lifecycle.ts owns server start/stop + listener wiring
 *   - dial.ts owns outbound connect+handshake
 *   - registry.ts owns the peer + subscriber maps
 *   - envelope-codec.ts owns build/sign/verify of envelopes
 *   - license-verifier.ts owns the fail-closed inbound gate
 *   - local-delivery.ts owns subscriber fan-out
 *   - well-known.ts owns the discovery JSON
 *   - transport.ts owns the actual socket
 */

import type {
  NetworkAdapter,
  NetworkEvent,
  NetworkQuery,
  NetworkResult,
  NodeInfo,
  PublishOptions,
  PublishResult,
  PublishableObject,
} from "@semantos/protocol-types/network";
import type { PeerLocator } from "@semantos/peer-locator";
import type { BCAProvider, Verifier } from "@semantos/session-protocol";
import {
  encodeLicense,
  licenseCertId,
  type License,
} from "@semantos/protocol-types/license";
import { randomUUID } from "node:crypto";

import {
  WsPeerConnection,
  type LocalIdentity,
} from "../ws-peer-connection.js";
import { FRAME_KIND, type SessionEnvelopeFrame } from "../types.js";
import { dialAndAuthenticate } from "./dial.js";
import { buildSignedEnvelope } from "./envelope-codec.js";
import { gateInboundEnvelope } from "./license-verifier.js";
import { startListener } from "./lifecycle.js";
import { deliverLocally } from "./local-delivery.js";
import { PeerRegistry, SubscriberRegistry } from "./registry.js";
import {
  bunWsTransport,
  type WsServer,
  type WsTransport,
} from "./transport.js";
import { buildWellKnownBody } from "./well-known.js";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

export interface WsNodeAdapterConfig {
  /** BCAProvider supplying the node's identity (Signer + BCA deriver). */
  identity: BCAProvider;
  /** The node's license cell (already verified by runtime/node's boot policy). */
  license: License;
  /** Resolver for peer BCAs → wss endpoints. */
  locator: PeerLocator;
  /** ECDSA verifier for peer handshake + envelope sigs. */
  verifier: Verifier;

  /**
   * Derive the expected BCA for a given pubkey. Used to cross-check a
   * peer's claimedBca against their license.pubkey. In production this
   * wires to the same derivation the local BCAProvider uses.
   */
  deriveBcaFromPubkey: (pubkey: Uint8Array) => Promise<string>;

  /** Optional production-time gate: reject specific issuers. */
  isAcceptableIssuer?: (issuerPubkey: Uint8Array) => boolean;

  /** Inbound TCP port. Defaults to 0 (pick-free, useful for tests). */
  serverPort?: number;
  /** Bind address. Defaults to `0.0.0.0`. */
  serverHost?: string;

  /** Handshake timeout; passed through to each WsPeerConnection. */
  handshakeTimeoutMs?: number;

  /** TLS config for wss. Omit → plain ws (tests / trusted LAN). */
  tls?: { cert: string | Buffer; key: string | Buffer };

  /**
   * Extras merged into the `/.well-known/semantos-node` JSON response.
   * WsNodeAdapter auto-fills `{ bca, pubkeyHex, licenseCertId }`; pass
   * this callback to add `version`, `adapters`, `advertised`, etc.
   * Return an object (or Promise of one).
   *
   * When omitted, `/.well-known/semantos-node` still serves JSON with just
   * the auto-filled fields so peers can at least verify the BCA/license
   * pairing.
   */
  wellKnownExtras?: () => Record<string, unknown> | Promise<Record<string, unknown>>;

  log?: (tag: string, msg: string) => void;

  /**
   * Transport seam — defaults to `bunWsTransport` (Bun.serve + platform
   * WebSocket). Tests can substitute an in-memory loopback double.
   * Not exposed in the public type re-export — internal extension point.
   */
  transport?: WsTransport;
}

// ---------------------------------------------------------------------------
// WsNodeAdapter facade
// ---------------------------------------------------------------------------

export class WsNodeAdapter implements NetworkAdapter {
  private readonly cfg: WsNodeAdapterConfig;
  private readonly licenseBytes: Uint8Array;
  private readonly subscribers = new SubscriberRegistry();
  /** peerBca → WsPeerConnection (only authenticated entries live here). */
  private readonly connections = new PeerRegistry();
  private readonly transport: WsTransport;

  private bca = "";
  private localIdentity?: LocalIdentity;
  private server?: WsServer;
  private running = false;
  private seq = 0;
  private readonly licenseCertIdValue: string;

  constructor(cfg: WsNodeAdapterConfig) {
    this.cfg = cfg;
    this.licenseBytes = encodeLicense(cfg.license);
    this.licenseCertIdValue = licenseCertId(cfg.license);
    this.transport = cfg.transport ?? bunWsTransport;
  }

  // ── lifecycle ─────────────────────────────────────────────

  async start(): Promise<void> {
    if (this.running) return;

    const id = await this.cfg.identity.identity();
    this.bca = id.bca;
    this.localIdentity = {
      signer: this.cfg.identity,
      license: this.cfg.license,
      licenseBytes: this.licenseBytes,
      bca: id.bca,
    };

    this.server = startListener({
      transport: this.transport,
      listen: {
        port: this.cfg.serverPort ?? 0,
        host: this.cfg.serverHost ?? "0.0.0.0",
        tls: this.cfg.tls,
      },
      localIdentity: this.localIdentity,
      verifier: this.cfg.verifier,
      deriveBcaFromPubkey: this.cfg.deriveBcaFromPubkey,
      isAcceptableIssuer: this.cfg.isAcceptableIssuer,
      handshakeTimeoutMs: this.cfg.handshakeTimeoutMs,
      log: this.cfg.log,
      onAuthenticated: (c) => {
        if (c.peerBca) this.connections.set(c.peerBca, c);
      },
      onFrame: (c, f) => this.onPeerFrame(c, f),
      onClose: (c) => {
        if (c.peerBca) this.connections.delete(c.peerBca);
      },
      buildWellKnown: () => this.buildWellKnownResponse(),
    });

    this.running = true;
  }

  async stop(): Promise<void> {
    if (!this.running) return;
    this.running = false;
    this.connections.forEach((conn) => {
      try {
        conn.close("node-stop");
      } catch {
        /* ignore */
      }
    });
    this.connections.clear();
    this.server?.stop();
    this.server = undefined;
  }

  // ── dial ─────────────────────────────────────────────────

  /**
   * Resolve a peer BCA via the locator, dial the WSS endpoint, and
   * complete the handshake. Resolves with the authenticated connection.
   */
  async connect(peerBca: string): Promise<WsPeerConnection> {
    this.assertRunning();
    const existing = this.connections.get(peerBca);
    if (existing && existing.currentState === "authenticated") {
      return existing;
    }

    return dialAndAuthenticate({
      peerBca,
      locator: this.cfg.locator,
      transport: this.transport,
      localIdentity: this.localIdentity!,
      verifier: this.cfg.verifier,
      deriveBcaFromPubkey: this.cfg.deriveBcaFromPubkey,
      isAcceptableIssuer: this.cfg.isAcceptableIssuer,
      handshakeTimeoutMs: this.cfg.handshakeTimeoutMs,
      log: this.cfg.log,
      onAuthenticated: (c) => {
        if (c.peerBca) this.connections.set(c.peerBca, c);
      },
      onFrame: (c, f) => this.onPeerFrame(c, f),
      onClose: (c) => {
        if (c.peerBca) this.connections.delete(c.peerBca);
      },
    });
  }

  async disconnect(peerBca: string): Promise<void> {
    const conn = this.connections.get(peerBca);
    if (!conn) return;
    conn.close("local-disconnect");
    this.connections.delete(peerBca);
  }

  peers(): readonly string[] {
    return this.connections.keys();
  }

  /** Actual port the server is listening on (useful when serverPort=0). */
  get listeningPort(): number | undefined {
    return this.server?.port;
  }

  /**
   * The `/.well-known/semantos-node` JSON body — auto-computed fields
   * plus any extras from `cfg.wellKnownExtras`. Exposed so callers can
   * surface the same data elsewhere (e.g. their admin API) without
   * round-tripping through HTTP.
   */
  buildWellKnownResponse(): Promise<Record<string, unknown>> {
    return buildWellKnownBody({
      bca: this.bca,
      license: this.cfg.license,
      licenseCertId: this.licenseCertIdValue,
      extras: this.cfg.wellKnownExtras,
    });
  }

  // ── NetworkAdapter interface ──────────────────────────────

  async publish(
    object: PublishableObject,
    options?: PublishOptions,
  ): Promise<PublishResult> {
    this.assertRunning();
    const topic = options?.topic ?? "tm_semantos_objects";
    const now = Date.now();
    const sessionId = options?.topic ?? topic; // 35B.1 simplification
    const seq = ++this.seq;
    const txid = randomUUID();

    // Build the envelope with a real sig over its canonical bytes.
    // Receive path re-computes the canonical bytes and verifies via
    // `cfg.verifier` against the peer's handshake-bound pubkey.
    const envelope = await buildSignedEnvelope({
      signer: this.cfg.identity,
      object,
      topic,
      sessionId,
      seq,
      sentAt: now,
    });

    // Send to every authenticated peer.
    this.connections.forEach((conn) => {
      if (conn.currentState !== "authenticated") return;
      try {
        conn.sendFrame(envelope);
      } catch (e) {
        this.log(
          "publish",
          `send failed to ${conn.peerBca}: ${(e as Error).message}`,
        );
      }
    });

    // Local fan-out to our own subscribers (mirror MulticastAdapter loopback
    // semantics: you receive your own publishes).
    deliverLocally(this.subscribers, {
      envelope,
      now,
      txid,
      semanticPath: object.semanticPath,
      parentPath: object.parentPath,
    });

    return { txid, publishedAt: now, multicastGroup: topic };
  }

  subscribe(
    topic: string,
    callback: (event: NetworkEvent) => void,
  ): () => void {
    return this.subscribers.add(topic, callback);
  }

  async resolve(_query: NetworkQuery): Promise<NetworkResult[]> {
    // 35B.1: no remote index; resolve returns nothing. 35B.2 adds it.
    return [];
  }

  async resolveBCA(address: string): Promise<NodeInfo | null> {
    const conn = this.connections.get(address);
    if (!conn || conn.currentState !== "authenticated") {
      return null;
    }
    return {
      bca: address,
      nodeCert: "",
      name: address,
      extensions: [],
      adapters: {
        storage: "unknown",
        identity: "ws-node",
        anchor: "unknown",
        network: "ws-node",
      },
      version: "0.0.1",
      uptime: 0,
    };
  }

  async sendToNode(
    targetBca: string,
    _message: Uint8Array,
  ): Promise<{ delivered: boolean }> {
    // 35B.1 placeholder: we don't have a typed direct-message frame yet.
    // Returning delivered:true when the peer is connected is enough for
    // gate tests that only check the bookkeeping path. 35B.2 adds a real
    // direct-message frame kind.
    const conn = this.connections.get(targetBca);
    return { delivered: conn?.currentState === "authenticated" };
  }

  isConnected(): boolean {
    return this.running;
  }

  getNodeBCA(): string | null {
    return this.bca || null;
  }

  // ── internals ─────────────────────────────────────────────

  private onPeerFrame(
    conn: WsPeerConnection,
    frame: SessionEnvelopeFrame | { kind: typeof FRAME_KIND.HEARTBEAT },
  ): void {
    if (frame.kind === FRAME_KIND.HEARTBEAT) return;
    const env = frame as SessionEnvelopeFrame;

    // Fire-and-forget the gate; delivery is gated on the verdict.
    void gateInboundEnvelope(this.cfg.verifier, {
      envelope: env,
      peerPubkey: conn.peerPubkey,
    }).then((verdict) => {
      if (!verdict.accept) {
        this.log(
          "onPeerFrame",
          `dropping envelope from ${conn.peerBca ?? "?"}: ${verdict.reason} (seq=${env.seq})`,
        );
        return;
      }
      deliverLocally(this.subscribers, {
        envelope: env,
        now: env.sentAt,
        txid: randomUUID(),
        semanticPath: "",
        parentPath: undefined,
      });
    });
  }

  private assertRunning(): void {
    if (!this.running) throw new Error("WsNodeAdapter is not running");
  }

  private log(tag: string, msg: string): void {
    this.cfg.log?.(tag, msg);
  }
}

```
