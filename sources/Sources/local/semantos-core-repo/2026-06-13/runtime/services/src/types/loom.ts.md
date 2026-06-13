---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/types/loom.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.099576+00:00
---

# runtime/services/src/types/loom.ts

```ts
import type { CellHeader } from '@semantos/protocol-types/browser';
import type { ObjectTypeDefinition } from '../config/extensionConfig';

/** A semantic object managed by the loom. */
export interface LoomObject {
  id: string;
  typeDefinition: ObjectTypeDefinition;
  header: CellHeader;
  payload: Record<string, unknown>;
  packedCell?: Uint8Array;
  patches: ObjectPatch[];
  visibility: 'draft' | 'published' | 'revoked';
  typeCoordinate?: TypeCoordinate;
  createdAt: number;
  updatedAt: number;
}

/** A patch applied to a loom object (evidence chain entry). */
export interface ObjectPatch {
  id: string;
  kind: 'extraction' | 'rescore' | 'manual_override' | 'state_transition' | 'evidence_merge' | 'instrument_emit' | 'action' | 'conversation' | 'channel_transaction' | 'channel_settlement';
  timestamp: number;
  delta: Record<string, unknown>;
  hatId?: string;
  hatCapabilities?: number[];
  /**
   * Optional lexicon name identifying which grammar/domain the
   * author was operating under. Federates cleanly across systems:
   * a DocumentBundle round-trip preserves "tenant wrote this under
   * OJT's jural lexicon" vs "REA wrote that under
   * project-management." Matches a `Lexicon.name` from
   * `@semantos/semantos-sir` (jural / control-systems / cdm /
   * bills-of-lading / project-management / property-management /
   * risk-assessment / circuit-commands).
   *
   * Undefined for pre-Slice-4 patches and for patches written
   * without lexicon context.
   */
  lexicon?: string;
}

/** A card on the canvas representing an object, script, or flow. */
export interface LoomCard {
  id: string;
  type: 'object' | 'script' | 'flow';
  objectId: string;
  position: { x: number; y: number };
  size: { width: number; height: number };
  state: 'collapsed' | 'expanded' | 'maximized';
  connections: CardConnection[];
}

/** A connection between two cards. */
export interface CardConnection {
  id: string;
  fromCardId: string;
  fromPort: 'right' | 'bottom';
  toCardId: string;
  toPort: 'left' | 'top';
}

/** Overall loom state. */
export interface LoomState {
  objects: Map<string, LoomObject>;
  cards: Map<string, LoomCard>;
  selectedObjectId: string | null;
  selectedCardId: string | null;
  categoryFilter: string | null;
}

/** Selective disclosure trait structure. Public/hashed split for identity fields. */
export interface IdentityTraits {
  disclosed: Record<string, unknown>;  // public traits (name, etc.)
  hashed: Record<string, string>;      // SHA256 hashed, verifiable with preimage
  schema: string;                      // e.g. "semantos.identity.v0.1"
}

/** Identity — the root "you" object (AFFINE). */
export interface Identity {
  id: string;
  name: string;
  /** Plexus certificate ID (hex-prefixed). Set by PlexusService on registration. */
  certId?: string;
  /** Plexus public key (PEM format). Set by PlexusService on registration. */
  publicKey?: string;
  object: LoomObject;
  hats: Hat[];
  activeHatId: string;
  policies: IdentityPolicy[];
  traits?: IdentityTraits;
  linkedIdentities?: string[];  // object IDs of related identity connections
}

/** A hat of an identity — a capability-scoped role (RELEVANT once issued). */
export interface Hat {
  id: string;
  name: string;
  displayName: string;
  capabilities: number[];
  derivationPath: string;
  /** Plexus certificate ID for this hat. Set by PlexusService on derivation. */
  certId?: string;
  /** Plexus public key for this hat (PEM format). */
  publicKey?: string;
  object: LoomObject;
}


/** A policy created from a conversation decision (RELEVANT once activated). */
export interface IdentityPolicy {
  id: string;
  name: string;
  scope: Record<string, unknown>;
  conditions: Record<string, unknown>;
  actions: string[];
  object: LoomObject;
  createdViaChannel?: string;
  enabled: boolean;
}

/** A message in a conversation channel. */
export interface ConversationMessage {
  id: string;
  channelId: string;
  hatId: string;
  sender: 'user' | 'system';
  text: string;
  timestamp: number;
  patchId?: string;
}

/** Reputation score computed from evidence chain patches. */
export interface ReputationScore {
  base: number;              // always 50
  activity: number;          // patches in last 30 days, capped at 30
  disputeOutcomes: number;   // net score from dispute/stake resolutions
  contributions: number;     // bonus from approved Ballot proposals
  total: number;             // weighted sum
  context?: string;          // optional TypeCoordinate prefix scope
}

/** Weights for computing reputation scores. */
export interface ReputationWeights {
  base: number;
  activity: number;
  disputes: number;
  contributions: number;
}

/** A coordinate in the three-axis taxonomy space. */
export interface TypeCoordinate {
  what: string;        // e.g. "what.service.fabrication.carpentry"
  how: string[];       // e.g. ["how.physical.manual", "how.technical.joinery"]
  why: string[];       // e.g. ["why.production", "why.maintenance"]
}

/** Panel layout configuration. */
export interface PanelLayout {
  sidebarWidth: number;
  inspectorWidth: number;
  sidebarCollapsed: boolean;
  inspectorCollapsed: boolean;
}

// ── Phase 39: Attention Surface Types ──

/** A scored item on the Attention Surface. */
export interface AttentionItem {
  /** The underlying LoomObject. */
  object: LoomObject;
  /** Computed relevance score (0.0 – 1.0). */
  relevance: number;
  /** Why this item surfaced — human-readable reason. */
  reason: AttentionReason;
  /** Which coordination mode this item is most relevant to. */
  primaryMode: 'do' | 'talk' | 'find';
  /** Which context within the mode (1-3-5 pyramid). */
  context: import('@semantos/protocol-types').IntentContext;
  /** Urgency tier: immediate (red), soon (amber), background (none). */
  urgency: 'immediate' | 'soon' | 'background';
  /** Timestamp when this attention score was last computed. */
  scoredAt: number;
}

export type AttentionReason =
  | { type: 'active_work'; lastTouchedAgo: number }
  | { type: 'deadline_approaching'; field: string; deadline: number; remainingMs: number }
  | { type: 'goal_misalignment'; goalObjectId: string; description: string }
  | { type: 'pending_action'; action: string; awaitingSince: number }
  | { type: 'new_update'; patchCount: number; since: number }
  | { type: 'streak_continuation'; streakDays: number }
  | { type: 'scheduled'; scheduledTime: number }
  | { type: 'extension_signal'; extensionId: string; signal: string }
  | { type: 'graph_proximity'; activeContext: string; distance: number };

```
