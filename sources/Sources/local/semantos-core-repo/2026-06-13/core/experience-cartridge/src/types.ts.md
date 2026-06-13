---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/experience-cartridge/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.951428+00:00
---

# core/experience-cartridge/src/types.ts

```ts
/**
 * Cartridge type surfaces — RM-011.
 *
 * A "cartridge" is the runtime-loaded form of an experience extension.
 * It wraps the canonical `ExtensionManifest` (the on-disk artefact) with
 * the optional surfaces an experience may contribute:
 *   - an `ExtensionGrammar` declaring source data shapes + entity mappings
 *   - one or more `Lexicon<C>` instances registered into the SIR
 *   - state-machine edges (FSM transitions per D-O4)
 *   - reducer passes (custom intent-reducer passes the extension brings)
 *   - conversation hooks (turn handlers — populated by RM-031 once
 *     `core/conversation-graph` lifts the pipeline out of Oddjobz)
 *
 * All surface fields are optional — a manifest-only cartridge is valid.
 * The cartridge concept exists so future apps can ship as single
 * registrations rather than scattered first-boot wire-ups.
 */
import type { Lexicon } from '@semantos/lexicon-core';

/**
 * Shape-only mirror of `ExtensionManifest` so this package does not
 * import the concrete oddjobz manifest type. Any object that satisfies
 * this shape (id + version + description) can be loaded as a cartridge.
 */
export interface CartridgeManifestShape {
  readonly id: string;
  readonly version: string;
  readonly description: string;
}

// ── T2.a: canonical cellTypes[] entries on cartridge.json ───────────────
//
// Each cartridge's `cartridge.json` carries a unified `cellTypes[]`
// array per D11.  Identity fields (name + triple + linearity) are
// required; UI fields (displayName, primaryAnchor, description,
// payloadSchema, phases, initialPhase) are optional.
//
// The kernel `buildTypeHash` is called at load time over the triple to
// produce the 32-byte typeHash stamped into the cell header.  The hash
// is NEVER serialised in the manifest — always derived from the triple
// at load — preventing drift between declared triple and embedded hash
// (decision record §3.2).
//
// Versioning is NOT a typeHash concern (D12): names do not carry `.v1`
// suffixes; segment4 is empty for all current cell types (reserved slot
// for future qualifiers if a cartridge ever needs one).

/** Allowed linearity values — mirrors the kernel `LinearityType`. */
export type ManifestLinearity =
  | 'LINEAR'
  | 'AFFINE'
  | 'PERSISTENT'
  | 'RELEVANT'
  | 'DEBUG';

/** Positional 4-segment identity tuple (Q1 resolution: explicit object). */
export interface CellTypeManifestTriple {
  readonly segment1: string;
  readonly segment2: string;
  readonly segment3: string;
  readonly segment4: string;
}

/** One entry in cartridge.json `cellTypes[]`. */
export interface CellTypeManifestEntry {
  /** Canonical name (no `.v1` suffix per D12). */
  readonly name: string;
  /** Identity tuple fed to `buildTypeHash`. */
  readonly triple: CellTypeManifestTriple;
  /** Kernel linearity class. */
  readonly linearity: ManifestLinearity;
  /** UI label — present when this cellType surfaces in navigation. */
  readonly displayName?: string;
  /** True when this is the primary entity in a cartridge's UI. */
  readonly primaryAnchor?: boolean;
  /** Human-readable description (UI tooltips, docs). */
  readonly description?: string;
  /** Declarative field schema (used by form renderers + projections). */
  readonly payloadSchema?: Record<string, unknown>;
  /** State machine phase names (D-O4 FSM). */
  readonly phases?: ReadonlyArray<string>;
  /** Initial phase a freshly-minted cell starts in. */
  readonly initialPhase?: string;
}

/** Runtime shape after loading — adds the computed typeHash. */
export interface CellTypeRegistryEntry {
  readonly manifest: CellTypeManifestEntry;
  readonly typeHash: Uint8Array;
  readonly typeHashHex: string;
}

/**
 * Shape-only mirror of `ExtensionGrammar` so this package stays free of
 * a runtime dep on the full grammar interface. Only the fields the
 * cartridge layer reads are listed.
 */
export interface CartridgeGrammarShape {
  readonly grammarId: string;
  readonly grammarVersion: string;
}

/**
 * Generic FSM edge — `from -> to` keyed by a transition name. Mirrors
 * the D-O4 state-machine edges in oddjobz. The cartridge layer only
 * needs to enumerate edges; it does not interpret them.
 */
export interface FsmEdge {
  readonly transition: string;
  readonly from: string;
  readonly to: string;
  /** Capabilities required to traverse this edge, by domain-flag value. */
  readonly capabilities?: ReadonlyArray<number>;
}

/**
 * Reducer-pass placeholder. The full `PassFn` lives in
 * `@semantos/intent/reducer/types`; mirroring its full type here would
 * create a runtime cycle (intent depends on cartridge transitively in
 * the future). Cartridges declare passes as opaque `unknown`; the
 * reducer composer narrows them with its own structural check.
 */
export type CartridgeReducerPass = unknown;

/**
 * Conversation hooks — populated by RM-031 when the conversation
 * pipeline lifts to `core/conversation-graph`. Until then this is an
 * empty surface kept for forward compatibility.
 */
export interface CartridgeConversationHooks {
  /** `runConversationTurn`-equivalent. RM-031 fills in. */
  readonly runTurn?: unknown;
}

// ── Peer-view contract (D-cartridge-peer-view-contract) ──────────────────────

/**
 * The three persona projection faces that Find→Network can surface.
 * Matches the `PersonaProjection` face keys in `core/persona`.
 */
export type PersonaFace = 'social' | 'topical' | 'commercial';

/**
 * A declarative view a cartridge registers to scope Find→Network.
 *
 * The shell reads this from the active cartridge (via `/api/v1/info`'s
 * `cartridges[]`) and applies label/filter/sort hints to the contact list.
 * The substrate (`projectPersona`) is never aware of cartridge vocabulary —
 * cartridges provide vocabulary *on top*, never inside, the projection.
 *
 * All fields are optional; an empty `{}` peerView is valid and means
 * "show all contacts with default labels".
 */
export interface CartridgePeerView {
  /**
   * Singular label for a peer in this cartridge's context.
   * Replaces "Contact" in headings (e.g. "Customer", "Jammate").
   */
  readonly label?: string;
  /** Plural label (e.g. "Customers", "Jammates"). */
  readonly pluralLabel?: string;
  /** Text shown when the filtered list is empty. */
  readonly emptyState?: string;
  /**
   * Restrict the visible contact list to peers that have at least one
   * active edge whose `edgeType` is in this list.  Empty or absent = no filter.
   */
  readonly filterEdgeTypes?: ReadonlyArray<string>;
  /**
   * The persona face to show first on the contact detail panel.
   * Defaults to `'social'` when absent.
   */
  readonly defaultFace?: PersonaFace;
  /**
   * Edge types that are considered "primary" for this cartridge — shown
   * prominently in the connection list.  Others are grouped under "other".
   */
  readonly primaryEdgeTypes?: ReadonlyArray<string>;
  /**
   * Verb names from the cartridge manifest that are contextually relevant
   * when viewing a peer.  The shell may surface quick-action buttons for these.
   */
  readonly verbs?: ReadonlyArray<string>;
}

export interface LoadedCartridge {
  /** The manifest as supplied. */
  readonly manifest: CartridgeManifestShape;
  /** Optional declarative grammar. */
  readonly grammar?: CartridgeGrammarShape;
  /** Optional lexicon contributions. */
  readonly lexicons?: ReadonlyArray<Lexicon>;
  /** Optional FSM-edge declarations. */
  readonly fsmEdges?: ReadonlyArray<FsmEdge>;
  /** Optional reducer passes contributed by this cartridge. */
  readonly reducerPasses?: ReadonlyArray<CartridgeReducerPass>;
  /** Optional conversation hooks. */
  readonly conversationHooks?: CartridgeConversationHooks;
  /**
   * Optional peer-view declaration — scopes Find→Network label and filter
   * when this cartridge is active. See `CartridgePeerView`.
   */
  readonly peerView?: CartridgePeerView;
  /**
   * Cell-type identities declared by this cartridge, each with a
   * computed `typeHash`.  Populated by `loadCartridgeFromManifest`.
   * Absent for callers that build cartridges in-memory without a
   * manifest file (existing test fixtures, etc.).
   */
  readonly cellTypes?: ReadonlyArray<CellTypeRegistryEntry>;
}

/** Input to `loadCartridge` — manifest is required, surfaces optional. */
export interface CartridgeInput {
  manifest: CartridgeManifestShape;
  grammar?: CartridgeGrammarShape;
  lexicons?: ReadonlyArray<Lexicon>;
  fsmEdges?: ReadonlyArray<FsmEdge>;
  reducerPasses?: ReadonlyArray<CartridgeReducerPass>;
  conversationHooks?: CartridgeConversationHooks;
  peerView?: CartridgePeerView;
  cellTypes?: ReadonlyArray<CellTypeRegistryEntry>;
}

/** Error thrown when registration is rejected. */
export class CartridgeRegistrationError extends Error {
  readonly code:
    | 'INCOMPATIBLE_VERSION'
    | 'INVALID_VERSION'
    | 'DUPLICATE_REGISTRATION'
    | 'DUPLICATE_TYPE_HASH'
    | 'INVALID_MANIFEST';
  readonly cartridgeId: string;
  readonly existing: string | undefined;
  readonly attempted: string;
  constructor(input: {
    code:
      | 'INCOMPATIBLE_VERSION'
      | 'INVALID_VERSION'
      | 'DUPLICATE_REGISTRATION'
      | 'DUPLICATE_TYPE_HASH'
      | 'INVALID_MANIFEST';
    cartridgeId: string;
    existing?: string;
    attempted: string;
    message: string;
  }) {
    super(input.message);
    this.name = 'CartridgeRegistrationError';
    this.code = input.code;
    this.cartridgeId = input.cartridgeId;
    this.existing = input.existing;
    this.attempted = input.attempted;
  }
}

```
