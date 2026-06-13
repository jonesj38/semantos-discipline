---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.036303+00:00
---

# runtime/session-protocol/src/types.ts

```ts
/**
 * Session-protocol core types.
 *
 * Every type here is domain-neutral. No references to poker, table, stake, bot, etc.
 * See docs/prd/PHASE-35A-SESSION-PROTOCOL-PROMOTION.md §Architecture.
 */

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

/**
 * Cryptographic identity of a session participant or node.
 *
 * `bca` is the IPv6 Block-Chain-Address derived from the pubkey via the BCA
 * algorithm (see core/cell-engine/src/bca.zig). `certId` is populated when
 * the identity is backed by a Plexus certificate.
 */
export interface Identity {
  /** IPv6 string, derived from pubkey. */
  bca: string;
  /** 33-byte compressed secp256k1 public key. */
  pubkey: Uint8Array;
  /** Plexus cert SHA256 when available. */
  certId?: string;
}

// ---------------------------------------------------------------------------
// StateMachine plug-in (the only domain-specific piece the skeleton depends on)
// ---------------------------------------------------------------------------

/**
 * Result of a state-machine transition.
 *
 * `next` is the destination state. `emit` is an optional list of downstream
 * events to broadcast to session peers. `meterTick` is an optional billing
 * event consumed by a `MeteringHook`.
 */
export interface TransitionResult<Event, State> {
  next: State;
  emit?: Event[];
  meterTick?: MeteringTick;
}

/**
 * Plug-in contract supplied by a session consumer (poker, call, cdm, ...).
 *
 * `session-protocol` owns everything above this interface; the consumer owns
 * the state machine below it. This is the only per-domain code the runtime
 * needs to know about.
 */
export interface StateMachine<Event, State, Context = unknown> {
  readonly initialState: State;
  readonly terminalStates: ReadonlySet<State>;
  transition(
    current: State,
    event: Event,
    ctx: Context,
  ): TransitionResult<Event, State>;
  validate(current: State, event: Event, ctx: Context): boolean;
}

// ---------------------------------------------------------------------------
// Session shape
// ---------------------------------------------------------------------------

/** Static description of a session: who can join, on what substrate. */
export interface SessionDescriptor {
  /** Opaque session id (typically the formation proposal hash). */
  id: string;
  /** Optional human-readable tag. */
  label?: string;
  /** Minimum and maximum party size for formation to succeed. */
  minParty: number;
  maxParty: number;
  /** Topic the session publishes on (drives `TopicToGroup`). */
  topic: string;
  /** Optional metadata (kind, version, consumer-defined). */
  metadata?: Record<string, unknown>;
}

/** Runtime handle returned from `SessionRuntime.start()`. */
export interface SessionHandle<Event = unknown, State = unknown> {
  readonly descriptor: SessionDescriptor;
  /** Current state from the perspective of this runtime. */
  readonly state: State;
  /** Fire-and-forget submit an event to the session. */
  submit(event: Event): Promise<void>;
  /** Stop the runtime and release resources. */
  stop(): Promise<void>;
  /** Subscribe to state transitions. */
  onTransition(cb: (next: State, event: Event) => void): () => void;
}

/** A candidate or confirmed participant in a session. */
export interface AgentDescriptor {
  /** Identity of the agent. */
  identity: Identity;
  /** Capabilities this agent advertises (domain-defined). */
  capabilities: DomainCapability[];
  /** When this descriptor was last heard. */
  lastSeen: number;
}

/** Opaque capability tag interpreted by the consumer's `FormationPolicy`. */
export interface DomainCapability {
  /** Namespaced capability id, e.g. `poker/v1` or `voice/opus`. */
  kind: string;
  /** Optional structured parameters. */
  params?: Record<string, unknown>;
}

/**
 * Decides whether a candidate session is ready to start.
 *
 * `session-protocol` calls this repeatedly as discoveries arrive; the policy
 * returns `null` until the candidate set is acceptable, then returns the
 * confirmed `AgentDescriptor[]`.
 */
export interface FormationPolicy {
  /** Descriptor of the session this policy forms. */
  readonly descriptor: SessionDescriptor;
  /** Called each time the discovery pool changes. */
  evaluate(pool: readonly AgentDescriptor[]): AgentDescriptor[] | null;
}

// ---------------------------------------------------------------------------
// Metering hook (optional billing integration)
// ---------------------------------------------------------------------------

/** A billing event fired by a state transition. */
export interface MeteringTick {
  /** Metering channel id (as used by packages/metering FSM). */
  channelId: string;
  /** Monotonic sequence number within the channel. */
  seq: number;
  /** Amount in sats accrued by this tick. */
  sats: number;
  /** Hash of the event that produced this tick (for audit). */
  eventHash: Uint8Array;
}

/**
 * Optional hook that consumes metering ticks.
 *
 * If omitted at runtime construction, state-machine `meterTick` values are
 * dropped silently; attaching a hook turns them into real channel ticks.
 */
export interface MeteringHook {
  onTick(tick: MeteringTick): Promise<void>;
  /** Final settlement call on session stop; hook submits accumulated ticks. */
  onSettle(channelId: string): Promise<void>;
}

// ---------------------------------------------------------------------------
// Transport seams
// ---------------------------------------------------------------------------

/**
 * Maps a session topic to an IPv6 multicast group.
 *
 * `defaultTopicToGroup` (see topics.ts) returns `ff02::1` for every topic —
 * the hackathon single-group behaviour. Phase 34 replaces this with a
 * type-hash-derived group per topic.
 */
export type TopicToGroup = (topic: string) => string;

/**
 * Source of canonical txids for published cells.
 *
 * In production the provider is backed by `apps/settlement` (real BSV txids);
 * tests inject a counter-based stub. The `MulticastAdapter` never mints its
 * own txid — it always asks the provider.
 */
export interface TxidProvider {
  mint(cellBytes: Uint8Array): Promise<string>;
}

/** Observer of multicast-adapter heartbeat lifecycle. */
export interface HeartbeatSink {
  /** Fired each time this node sends its own heartbeat. */
  onHeartbeatSent?(timestamp: number): void;
  /** Fired when a remote peer's heartbeat is received. */
  onPeerHeartbeatReceived?(peer: PeerInfo): void;
}

/** Information about a remote peer observed by the multicast adapter. */
export interface PeerInfo {
  bca: string;
  /** When the peer was first seen. */
  firstSeen: number;
  /** Most recent heartbeat timestamp. */
  lastSeen: number;
  /** Advertised peer metadata (version, kinds, ...). */
  metadata?: Record<string, unknown>;
}

```
