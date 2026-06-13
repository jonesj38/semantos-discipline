---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/runtime.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.035728+00:00
---

# runtime/session-protocol/src/runtime.ts

```ts
/**
 * SessionRuntime — domain-neutral event loop for multi-party sessions.
 *
 * This is the load-bearing piece of the session-protocol skeleton: it
 * owns nothing about the application (poker, voice, cdm, auction …) —
 * everything domain-specific is delegated to the injected `StateMachine`.
 *
 * Wiring at a glance:
 *
 *   submit(ev) ─┐
 *               ├─► state.transition(current, ev, ctx)
 *   remote ev ─┘    │
 *                   ├─► next state         ──► onTransition callbacks
 *                   ├─► emit[] events      ──► adapter.publish(topic)
 *                   └─► meterTick?         ──► MeteringHook.onTick
 *
 * `SessionRuntime` holds no BSV / crypto dependency — signing responsibility
 * lives behind the `Signer` seam (passed in options). Encoding of session
 * events over the wire is also injectable (default: JSON), because events
 * are domain-defined.
 */

import type {
  NetworkAdapter,
  NetworkEvent,
  PublishResult,
} from "@semantos/protocol-types/network";
import type {
  AgentDescriptor,
  MeteringHook,
  SessionDescriptor,
  SessionHandle,
  StateMachine,
} from "./types.js";
import type { Signer } from "./signer.js";

// ── Wire envelope ──────────────────────────────────────────────

/**
 * Envelope the runtime places around every event before handing it to
 * the NetworkAdapter. `from` is the sender's BCA; `seq` is monotonic
 * per-sender; `payload` is the opaque encoded event.
 */
interface SessionEnvelope {
  kind: "session_event";
  sessionId: string;
  from: string;
  seq: number;
  payload: string;
  sentAt: number;
}

/**
 * Pluggable encoder for session events. Default uses `JSON.stringify` so
 * consumers don't need to ship a codec unless they care about size or
 * determinism. Consumers with strict message formats pass CBOR / Protobuf /
 * whatever via `encode` + `decode`.
 */
export interface EventCodec<Event> {
  encode(event: Event): string;
  decode(wire: string): Event;
}

export const jsonCodec: EventCodec<unknown> = {
  encode: (event) => JSON.stringify(event),
  decode: (wire) => JSON.parse(wire) as unknown,
};

// ── Config ────────────────────────────────────────────────────

export interface SessionRuntimeConfig<
  Event,
  State,
  Context = unknown,
> {
  descriptor: SessionDescriptor;
  stateMachine: StateMachine<Event, State, Context>;
  adapter: NetworkAdapter;
  /** Signer for envelope auth. Currently used to surface the sender's BCA. */
  signer?: Signer;
  /** Initial context handed to `stateMachine.transition`. */
  context?: Context;
  /** Optional metering hook; ticks from `emit[].meterTick` are routed here. */
  meteringHook?: MeteringHook;
  /** Wire codec. Defaults to JSON. */
  codec?: EventCodec<Event>;
  /** Verbose logging. Defaults to silent. */
  log?: (tag: string, msg: string) => void;
}

// ── Implementation ────────────────────────────────────────────

export class SessionRuntime<Event, State, Context = unknown>
  implements SessionHandle<Event, State>
{
  readonly descriptor: SessionDescriptor;

  private readonly stateMachine: StateMachine<Event, State, Context>;
  private readonly adapter: NetworkAdapter;
  private readonly signer?: Signer;
  private readonly context: Context;
  private readonly meteringHook?: MeteringHook;
  private readonly codec: EventCodec<Event>;
  private readonly log: (tag: string, msg: string) => void;

  private currentState: State;
  private transitionCallbacks: Array<(next: State, event: Event) => void> = [];

  private senderBca = "local";
  private outgoingSeq = 0;
  private unsubscribe: (() => void) | null = null;
  private running = false;

  constructor(config: SessionRuntimeConfig<Event, State, Context>) {
    this.descriptor = config.descriptor;
    this.stateMachine = config.stateMachine;
    this.adapter = config.adapter;
    this.signer = config.signer;
    this.context = config.context ?? (undefined as unknown as Context);
    this.meteringHook = config.meteringHook;
    this.codec =
      (config.codec as EventCodec<Event> | undefined) ??
      (jsonCodec as EventCodec<Event>);
    this.log =
      config.log ??
      (() => {
        /* silent */
      });

    this.currentState = this.stateMachine.initialState;
  }

  // ── SessionHandle ──────────────────────────────────────────

  get state(): State {
    return this.currentState;
  }

  onTransition(cb: (next: State, event: Event) => void): () => void {
    this.transitionCallbacks.push(cb);
    return () => {
      const idx = this.transitionCallbacks.indexOf(cb);
      if (idx >= 0) this.transitionCallbacks.splice(idx, 1);
    };
  }

  async submit(event: Event): Promise<void> {
    if (!this.running) throw new Error("SessionRuntime is not running");
    await this.applyEvent(event, { origin: "local" });
  }

  async stop(): Promise<void> {
    this.running = false;
    if (this.unsubscribe) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────

  /**
   * Begin listening on the adapter for this session's topic. Returns `this`
   * so callers can use a fluent style: `const h = await new SessionRuntime(…).start()`.
   */
  async start(): Promise<SessionHandle<Event, State>> {
    // Priority: signer > adapter.getNodeBCA() > random. A unique senderBca
    // per runtime is load-bearing — the envelope-echo filter in
    // handleNetworkEvent drops messages whose `from` matches `senderBca`, so
    // two runtimes sharing an id cause each to treat the other's publishes
    // as its own and never apply them.
    if (this.signer) {
      const id = await this.signer.identity();
      this.senderBca = id.bca;
    } else {
      const bca = this.adapter.getNodeBCA();
      if (bca) {
        this.senderBca = bca;
      } else {
        this.senderBca =
          "anon-" +
          Math.floor(Math.random() * 0xffffffff)
            .toString(16)
            .padStart(8, "0");
      }
    }

    this.unsubscribe = this.adapter.subscribe(
      this.descriptor.topic,
      (ev) => {
        this.handleNetworkEvent(ev).catch((err) => {
          this.log("RUNTIME", `handler error: ${err}`);
        });
      },
    );
    this.running = true;
    return this;
  }

  // ── Internals ──────────────────────────────────────────────

  /**
   * Handle an inbound NetworkEvent: decode the envelope, reject messages
   * not tagged for this session, and apply the carried event.
   */
  private async handleNetworkEvent(ev: NetworkEvent): Promise<void> {
    if (!this.running) return;
    if (ev.type !== "object_published") return;

    const cellBytes = ev.result.cellBytes;
    let env: SessionEnvelope;
    try {
      env = JSON.parse(new TextDecoder().decode(cellBytes)) as SessionEnvelope;
    } catch {
      return; // ignore non-envelope cells on this topic
    }
    if (env.kind !== "session_event") return;
    if (env.sessionId !== this.descriptor.id) return;
    if (env.from === this.senderBca) return; // echo of our own publish

    let event: Event;
    try {
      event = this.codec.decode(env.payload);
    } catch {
      return; // malformed payload — drop silently
    }

    await this.applyEvent(event, { origin: "remote", from: env.from });
  }

  /**
   * Apply an event through the state machine. Drives the three side-effects:
   *   - update currentState + fire onTransition callbacks
   *   - on the ORIGINATOR only: publish this event + emits to the wire and
   *     recursively apply emits locally so local state stays in sync
   *   - deliver meterTick (if present) to the MeteringHook
   *
   * Semantics: emits are "downstream events to broadcast" (per PRD). The
   * originator publishes each emit to the wire, so receivers observe them
   * as normal remote events on their subscribe callback — no need for
   * receivers to re-apply emits themselves (would cause divergence if the
   * originator's state machine disagreed).
   */
  private async applyEvent(
    event: Event,
    origin: { origin: "local" | "remote"; from?: string },
  ): Promise<void> {
    if (!this.stateMachine.validate(this.currentState, event, this.context)) {
      this.log(
        "RUNTIME",
        `validate failed for state=${String(this.currentState)} event=${JSON.stringify(event)}`,
      );
      return;
    }

    const res = this.stateMachine.transition(
      this.currentState,
      event,
      this.context,
    );

    this.currentState = res.next;
    for (const cb of this.transitionCallbacks) {
      try {
        cb(res.next, event);
      } catch (err) {
        this.log("RUNTIME", `onTransition error: ${err}`);
      }
    }

    if (res.meterTick && this.meteringHook) {
      try {
        await this.meteringHook.onTick(res.meterTick);
      } catch (err) {
        this.log("RUNTIME", `metering onTick error: ${err}`);
      }
    }

    if (origin.origin !== "local") return;

    // Originator: publish this event, then publish + locally apply each emit
    // so the originator's state converges the same way a receiver's does.
    await this.publishSessionEvent(event);
    if (res.emit) {
      for (const e of res.emit) {
        await this.publishSessionEvent(e);
        // Apply the emit locally through the state machine. Recursive call —
        // an emit that itself produces emits is handled by the same branch.
        await this.applyEvent(e, { origin: "local" });
      }
    }
  }

  /**
   * Wrap an event in a session envelope and hand it to the adapter. Uses
   * a deterministic semantic path scheme so duplicate-path detection on
   * the adapter can't fire on the same (session × sender × seq).
   */
  private async publishSessionEvent(event: Event): Promise<PublishResult> {
    this.outgoingSeq++;
    const env: SessionEnvelope = {
      kind: "session_event",
      sessionId: this.descriptor.id,
      from: this.senderBca,
      seq: this.outgoingSeq,
      payload: this.codec.encode(event),
      sentAt: Date.now(),
    };
    const cellBytes = new TextEncoder().encode(JSON.stringify(env));
    const contentHash = await simpleHash(cellBytes);

    return this.adapter.publish(
      {
        cellBytes,
        semanticPath: `/sessions/${this.descriptor.id}/${this.senderBca}/${this.outgoingSeq}`,
        contentHash,
        ownerCert: this.senderBca,
        typeHash: "type-session-envelope",
      },
      { topic: this.descriptor.topic },
    );
  }
}

// ── AgentDescriptor helper (light-touch) ──────────────────────

/** Minimal constructor for `AgentDescriptor`. Exported for consumer convenience. */
export function agentDescriptor(
  bca: string,
  capabilities: AgentDescriptor["capabilities"],
  metadata?: Record<string, unknown>,
): AgentDescriptor {
  return {
    identity: {
      bca,
      pubkey: new Uint8Array(33),
      certId: undefined,
    },
    capabilities,
    lastSeen: Date.now(),
    ...(metadata ? { metadata } : {}),
  };
}

// ── Internals ────────────────────────────────────────────────

/**
 * Tiny non-cryptographic hash for `contentHash` on wire envelopes. Enough
 * for deduplication / audit, not for security — signer authentication
 * lives separately via the Signer seam.
 */
async function simpleHash(bytes: Uint8Array): Promise<string> {
  let h = 2166136261; // FNV-1a 32-bit
  for (let i = 0; i < bytes.length; i++) {
    h ^= bytes[i]!;
    h = Math.imul(h, 16777619);
  }
  return "fnv1a-" + (h >>> 0).toString(16).padStart(8, "0");
}

```
