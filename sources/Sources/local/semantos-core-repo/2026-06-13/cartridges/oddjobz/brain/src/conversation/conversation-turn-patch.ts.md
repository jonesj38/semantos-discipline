---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/conversation-turn-patch.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.525173+00:00
---

# cartridges/oddjobz/brain/src/conversation/conversation-turn-patch.ts

```ts
/**
 * Conversation-turn patch — the intake bot's per-turn audit record.
 *
 * D-ODDJOBZ-turns-as-sem-objects (foundation): every intake turn is
 * now persisted via TWO parallel sinks (additive, neither replaces
 * the other):
 *
 *   1. The jsonl ConversationPatch sink (kept verbatim; V1 audit log).
 *   2. A sem_objects sink that receives the CANONICAL turn shape per
 *      `ODDJOBZ-CONVERSATION-ARCHITECTURE.md` §4 — one row per turn
 *      of `objectKind='oddjobz.conversation.turn'`.
 *
 * Both sinks fire side-by-side. Each intake interaction produces TWO
 * canonical turns: an inbound (the customer message) and an outbound
 * (the AI/operator reply). The jsonl path emits ONE ConversationPatch
 * per interaction (preserving the existing audit shape), so the jsonl
 * is unchanged on disk.
 *
 * The sem-object sink is INJECTED as an optional dep. The default is
 * a no-op — production wiring of a real Database-backed sink happens
 * at the brain-reactor boundary (see project memory
 * `semantos_brain_single_threaded_reactor`: this file runs as the
 * spawned bun child, which must NOT sync-call back into the brain's
 * HTTP surface). The sink shape is the seam where a future brain-side
 * sem_objects bridge (using the detached-grandchild submitter
 * pattern, or a brain-reactor pre-record) plugs in. Until that lands,
 * the production sink stays no-op and the sem-objects row is purely a
 * test/contract artifact.
 *
 * Why the seam belongs here: this cartridge has no
 * `@semantos/semantic-objects` dependency (deliberately — Database
 * handles belong with the brain reactor, not in the cartridge). The
 * injected sink lets the canonical payload be CONSTRUCTED here (where
 * intake context is available) while keeping the Database write at
 * the appropriate substrate boundary.
 *
 * Mapping from `IntakeTurnBody` (the existing per-turn metadata) onto
 * the canonical shape uses the architecture doc's recommended
 * **option (a)**: the legacy `IntakeTurnBody` rides as a typed entry
 * inside the canonical turn's `bodyParts[]` (kind:'oddjobz-intake-
 * meta'). No data loss; forward-compatible.
 *
 * Pure + injectable (id/clock/write/sink all DI'd). No brain call.
 */

import { appendFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import {
  meetsRatificationThreshold,
  DEFAULT_RATIFICATION_THRESHOLD,
} from './ratification-config.js';
import {
  writeConversationPatch,
  type ConversationPatchShape,
  type ConversationPatchDeps,
  type ConversationPatchResult,
} from '@semantos/intent';
import type { SIRConstraint } from '@semantos/semantos-sir';
import {
  intakeTemplateDescriptor,
  type TemplateVersionDescriptor,
} from './template-version.js';
import { promptVersionRef, PROMPT_IDS } from './prompt-store.js';
import type { ReplyAuditSink, OddjobzReplyAuditPayload } from './reply-audit.js';
import {
  resolveNlRelations,
  type NlRelationSink,
} from './nl-relation-resolver.js';
import type { OutboundState } from './outbound-state-machine.js';

/** The structured turn carried as the ConversationPatch `body`. */
export interface IntakeTurnBody {
  readonly kind: 'intake_turn';
  /** What the customer said this turn. */
  readonly message: string;
  /** Compact snapshot of accumulated job state at decision time
   *  (not the whole context window — just what drove the cascade). */
  readonly stateSummary?: Record<string, unknown>;
  /** What the bot replied + the decision-tree action it took. */
  readonly reply: string;
  readonly action: { readonly type: string; readonly [k: string]: unknown };
  /** LLM model id used for this turn. */
  readonly model: string;
  /** Versioned prompt + decision-tree provenance for THIS turn. */
  readonly prompt: TemplateVersionDescriptor;
}

// ── Canonical turn shape (architecture doc §4) ───────────────
//
// One row per turn in sem_objects, objectKind='oddjobz.conversation.turn'.
// In this foundation PR, we keep `entityRef` optional — D-OJ-conv-entity-
// anchoring binds it. `identityHandle` is also optional in the foundation
// — D-OJ-conv-multiparty-identity wires the full identity model.

/** participantRole enum per architecture doc §5.1, plus `unknown`
 *  for legacy/unmigrated turns where the producer couldn't reliably
 *  distinguish. (Better than fabricating a role.) */
export type ParticipantRole =
  | 'operator'
  | 'ai'
  | 'tenant'
  | 'agent'
  | 'owner'
  | 'subcontractor'
  | 'tradesman'
  | 'external'
  | 'unknown';

export type ConversationSurface =
  | 'widget'
  | 'meta-inbox'
  | 'email'
  | 'voice'
  | 'sms'
  | 'import'
  | 'cli';

// ── D-OJ-conv-multiparty-identity ─────────────────────────────
//
// Tiered identity model (§13.2, RESOLVED 2026-05-21). Un-cert'd
// parties carry an `identityHandle` instead of an `actorCertId`:
//
//   L0 — browser cookie  (anonymous session marker; first widget
//        contact). `identityHandle = { kind: 'cookie', value }`.
//   L1 — phone OR email  (upgraded when the party provides contact;
//        surface adapters bind here by default).
//        `identityHandle = { kind: 'phone'|'email', value }`.
//   L2 — Plexus cert     (operators + AI + cert'd subs only).
//        `actorCertId = cert_id`, `identityHandle = null`.
//
// The `kind` union is a strict superset of the architecture doc §4.1
// shape (`phone|email|ig|fb|free`) plus `cookie` (the §13.2 L0 marker,
// not in the original §4.1 schema). `ig`/`fb`/`free` are retained for
// the Meta-inbox / catch-all surfaces (un-cert'd, tier L1-equivalent).
// The merge capability that operates on these handles is a SEPARATE
// deliverable (`D-OJ-conv-identity-merge`) — NOT built here.
export type IdentityHandleKind =
  | 'cookie' // L0 — anonymous browser session
  | 'phone' // L1 — E.164
  | 'email' // L1
  | 'ig' // L1-equiv — Instagram handle (Meta inbox)
  | 'fb' // L1-equiv — Facebook handle (Meta inbox)
  | 'free'; // L1-equiv — free-form catch-all

/** The L0/L1 identity token for un-cert'd parties. `null` (absent)
 *  for cert-bound parties (operator/ai/cert'd-sub) — they carry
 *  `actorCertId` instead. */
export interface IdentityHandle {
  readonly kind: IdentityHandleKind;
  readonly value: string;
}

/** Identity tier per §13.2. L2 if cert-bound; L1 if a phone/email/
 *  social handle is bound; L0 if only an anonymous cookie is bound.
 *  Useful for downstream queries + the future `D-OJ-conv-identity-
 *  merge` deliverable (which merges L0/L1 participants). */
export type IdentityTier = 'L0' | 'L1' | 'L2';

/** Sentinel for the AI role's `actorCertId` when the agent cert has
 *  NOT been provisioned yet. AI cert provisioning is the LATER
 *  deliverable `D-OJ-conv-ai-participant` (it pairs the agent child
 *  cert via `agent-cert-provider.ts`). Until that lands at the
 *  turn-persist call site, an AI turn whose `agentCertId` wasn't
 *  threaded through carries this sentinel instead of a fabricated
 *  cert — making the "real binding pending" state explicit and
 *  greppable rather than silently dropping the cert binding. A turn
 *  carrying this sentinel still reports tier L2 (it IS a cert-tier
 *  role; the cert value is just not-yet-bound). */
export const AI_CERT_PENDING_SENTINEL =
  'cert_ai_pending:D-OJ-conv-ai-participant';

/** A typed entry inside the canonical turn's bodyParts array.
 *  Discriminated union — extend with more `kind`s as needed. */
export type OddjobzTurnBodyPart =
  | {
      /** Carries the legacy `IntakeTurnBody` (per turn-patch's audit
       *  surface) so the canonical row stays a strict superset and
       *  legacy consumers can recover their shape. Option (a) per
       *  ODDJOBZ-CONVERSATION-ARCHITECTURE.md §4.2. */
      readonly kind: 'oddjobz-intake-meta';
      readonly payload: IntakeTurnBody;
    }
  | {
      /** Free-form attachment slot for future extensions
       *  (transcripts, structured intent-extractor outputs, etc.). */
      readonly kind: 'attachment' | 'transcript' | 'extracted-intent';
      readonly payload: unknown;
    };

/** The canonical payload for an `objectKind='oddjobz.conversation.turn'`
 *  sem_objects row. See `ODDJOBZ-CONVERSATION-ARCHITECTURE.md` §4. */
export interface OddjobzConversationTurnPayload {
  /** Stable per-turn id. ULID/UUID. Generated by the caller's
   *  `generatePatchId` dep so the id is deterministic in tests. */
  readonly turnId: string;
  /** Conversation aggregate id. In the foundation PR this is just
   *  the intake session_id; future deliverables (entity-anchoring,
   *  aggregate-sir) refine it to `hash(entity.cellHash)`. */
  readonly conversationId: string;
  /** Job/site/customer cell hash. Optional in the foundation PR —
   *  bound by D-OJ-conv-entity-anchoring. */
  readonly entityRef?: {
    readonly kind: 'job' | 'site' | 'customer';
    readonly cellHash: string;
  };
  /** Who said it. Single source of truth for downstream filters. */
  readonly participantRole: ParticipantRole;
  /** Sub-discriminator for `participantRole === 'external'` (§13.7).
   *  Free-form string — e.g. `'utility-provider'`, `'insurer'`,
   *  `'council'`, `'real-estate-agent'`. Absent when `participantRole`
   *  is anything other than `'external'`, or when the external kind is
   *  unknown. No routing or business logic depends on this in V1;
   *  it is persisted for future use and is entirely optional. */
  readonly externalKind?: string;
  /** L2 identity binding when cert-bound (operator, AI, subcontractor
   *  once they have certs). Null/absent for un-cert'd parties (which
   *  carry `identityHandle` instead). For an AI turn whose agent cert
   *  isn't yet provisioned this is the `AI_CERT_PENDING_SENTINEL`. */
  readonly actorCertId?: string;
  /** L0/L1 identity binding for un-cert'd parties
   *  (tenant/owner/agent/external, and pre-cert subcontractors).
   *  `{ kind:'cookie' }` = L0 (anonymous widget session);
   *  `{ kind:'phone'|'email'|... }` = L1. Absent for cert-bound
   *  parties (operator/ai/cert'd-sub — they carry `actorCertId`).
   *  Invariant: a turn carries `actorCertId` XOR `identityHandle`
   *  (never both populated); see `bindParticipantIdentity`. The
   *  `D-OJ-conv-identity-merge` deliverable operates on this shape. */
  readonly identityHandle?: IdentityHandle;
  /** Surface this turn entered (inbound) or leaves (outbound) on. */
  readonly surface: ConversationSurface;
  /** Direction. Inbound = from customer; outbound = to customer. */
  readonly direction: 'inbound' | 'outbound';
  /** Operator-readable plain-text body. The canonical message. */
  readonly bodyText: string;
  /** Structured body parts — attachments, transcripts, the legacy
   *  IntakeTurnBody (option a per architecture §4.2). */
  readonly bodyParts?: ReadonlyArray<OddjobzTurnBodyPart>;
  /** SCG REPLIES_TO target. Foundation PR leaves this unset for the
   *  inbound turn; the outbound turn sets it to the inbound turnId
   *  so REPLIES_TO can auto-emit at cut-over time. */
  readonly quotedTurnId?: string;
  /** Outbound-only: the recipient's contact handle (phone or email).
   *  Present on outbound turns to encode WHERE to deliver the message.
   *  Distinct from `identityHandle` (which is the ACTOR's identity for
   *  inbound un-cert'd parties). Absent on inbound turns. */
  readonly recipientHandle?: IdentityHandle;
  /** If true, the approve script should generate a customer reply link
   *  (ojt.info/{token}) and append it to the outbound message body.
   *  Relevant for widget-surface outbounds and any SMS where you want
   *  the recipient to be able to reply back into the conversation. */
  readonly includeCustomerLink?: boolean;
  /** Outbound state machine state (§8.1, D-OJ-conv-outbound-routing).
   *  Populated for `direction='outbound'` turns only. When absent on an
   *  outbound turn the state is implicitly `drafted` (the initial state).
   *
   *  State progression:
   *    drafted → proposed → approved → sent → delivered | failed
   *                    ↓
   *                rejected (terminal)
   *
   *  Async delivery callbacks (`sent → delivered|failed`) from
   *  Twilio/SMTP/IG arrive hours later and update this field in-place
   *  (Option A: UPDATE payload JSONB on the sem_objects row). Per the
   *  durability benchmark (see `outbound-durability-benchmark.ts`):
   *    - Option A median 0.309 ms vs Option C median 0.179 ms → 1.73×
   *    - Within the 2× threshold → Option A selected for simplicity. */
  readonly outboundState?: OutboundState;
  /** Keeps existing intent-pipeline threading semantics. Mirrors
   *  ConversationPatchShape.correlationId. */
  readonly correlationId: string;
  /** Domain lexicon when known. Optional. */
  readonly lexicon?: string;
  /** Unix-millis at persist time. */
  readonly timestamp: number;
}

/** The sem_objects sink shape. The sink RECEIVES a fully-formed
 *  canonical turn payload and is responsible for persisting it as a
 *  `sem_objects` row (e.g. via `createObject` from
 *  `@semantos/semantic-objects`). Default no-op.
 *
 *  Production wiring: a brain-side adapter that:
 *  (a) lives inside the brain reactor (so it has direct Database
 *      access — no self-call deadlock per project memory
 *      `semantos_brain_single_threaded_reactor`), OR
 *  (b) writes a payload file the detached-grandchild submitter
 *      picks up and submits via the loopback REPL (same pattern as
 *      `intake-handler.ts --detached-submit`).
 *
 *  Either way the cartridge doesn't open a Database handle itself. */
export type SemObjectTurnSink = (
  turn: OddjobzConversationTurnPayload,
) => Promise<void> | void;

// ── D-OJ-conv-entity-anchoring ────────────────────────────────
//
// Every persisted turn anchors to the job/site/customer it concerns
// via a `BELONGS_TO_ENTITY` SCG relation
// (`ODDJOBZ-CONVERSATION-ARCHITECTURE.md` §7). The relation's
//   source = the turn's sem_objects.id,
//   target = the entity cell's sem_objects.id.
//
// Like the sem_objects sink, the relation emit is an INJECTED callback
// — NOT a direct `createRelation` from the intake child. The intake
// child runs as a spawned bun of the single-threaded brain reactor and
// must NOT sync-call back into the brain (project memory
// `semantos_brain_single_threaded_reactor`). The brain-side adapter
// (which holds the Database handle) wires this callback; the intake
// child leaves it absent (dormant). The callback receives a
// fully-formed relation request, mirroring the foundation's
// injected-sem-object-sink discipline.

/** A `BELONGS_TO_ENTITY` relation to emit for a persisted turn. The
 *  emit target carries both ids (source = turn, target = entity) and
 *  the entity kind (denormalised for the brain-side adapter's logging
 *  / target-must-exist check). */
export interface BelongsToEntityRelation {
  readonly kind: 'BELONGS_TO_ENTITY';
  /** The persisted turn's sem_objects.id (the relation source). */
  readonly turnId: string;
  /** The entity cell's sem_objects.id / cellHash (the relation
   *  target). Target-must-exist (§7.2) is enforced by the brain-side
   *  adapter that holds the Database handle. */
  readonly entityCellHash: string;
  /** Entity kind, for logging + the adapter's existence check. */
  readonly entityKind: 'job' | 'site' | 'customer';
}

/** The injected relation sink. RECEIVES a fully-formed
 *  `BELONGS_TO_ENTITY` relation request and is responsible for minting
 *  it via `createRelation` (from `@semantos/scg-relations`) AFTER the
 *  turn row exists. Default absent (dormant) in the intake child.
 *
 *  ONE-PER-TURN ENFORCEMENT (§13.1): the catalogue of relations for a
 *  turn is assembled in `buildTurnRelations` below — exactly one
 *  `BELONGS_TO_ENTITY` is produced per turn that carries an
 *  `entityRef`. This is the relation-pass-equivalent rejection point
 *  for this code path: the set is built deterministically with a
 *  single entry, so a turn can never carry two anchors. The
 *  architecture doc leans toward relation-pass enforcement (§13.1);
 *  because the Oddjobz turn-persist path emits the relation directly
 *  (not through the 10th reducer), the equivalent enforcement point is
 *  this builder. The brain-side adapter MAY additionally assert
 *  one-per-turn at `createRelation` time (a `listRelationsFrom(turnId,
 *  {kind:'BELONGS_TO_ENTITY'})` check) if a stronger guarantee is
 *  wanted — documented as an option, not built here. */
export type SemObjectRelationSink = (
  relation: BelongsToEntityRelation,
) => Promise<void> | void;

// ── D-SCG-oddjobz-consumer-cutover — REPLIES_TO ───────────────
//
// When a persisted turn quotes a prior turn (`quotedTurnId` set), a
// `REPLIES_TO` SCG relation is emitted from the turn → the quoted turn
// (`core/conversation-graph/src/auto-emit.ts` :: `autoEmitReplyRelation`,
// RM-031 / SCG §3.6). As with the `BELONGS_TO_ENTITY` anchor above, the
// emit is an INJECTED callback — NOT a direct `createRelation` /
// `autoEmitReplyRelation` from the intake child. The intake child runs
// as a spawned bun of the single-threaded brain reactor and must NOT
// sync-call back into the brain (project memory
// `semantos_brain_single_threaded_reactor`). The brain-side adapter
// (which holds the Database handle — see
// `core/conversation-graph/src/auto-emit.ts` ::
// `makeReplyRelationEmitter`) wires this callback; the intake child
// leaves it absent (dormant).
//
// PRODUCTION ACTIVATION IS GATED on a real Database-backed sem_objects
// sink being wired brain-side (tracked as
// `D-OJ-conv-sem-objects-sink-activation`). The production
// `semObjectSink` is still no-op today (foundation
// D-ODDJOBZ-turns-as-sem-objects), so this `replyRelationSink` is
// likewise dormant in production until that activation lands. The logic
// + the canonical→Turn mapping ship here, fully exercised through an
// injected test Database in the test suite.

/** A `REPLIES_TO` relation to emit for a persisted turn. Source = the
 *  quoting turn's sem_objects.id; target = the quoted turn's
 *  sem_objects.id. `authorCertId` (when present) is threaded onto the
 *  relation as `createdByCertId` (the turn's `actorCertId` from
 *  multiparty-identity). Target-must-exist / vacuous-quote handling is
 *  the brain-side `autoEmitReplyRelation`'s responsibility (it no-ops
 *  on an unset `quotedTurnId`). */
export interface RepliesToRelation {
  readonly kind: 'REPLIES_TO';
  /** The quoting turn's sem_objects.id (the relation source). */
  readonly turnId: string;
  /** The quoted prior turn's sem_objects.id (the relation target). */
  readonly quotedTurnId: string;
  /** The quoting turn's author cert id, when cert-bound. Threaded onto
   *  the relation as `createdByCertId`. Absent for un-cert'd turns. */
  readonly authorCertId?: string;
}

/** The injected `REPLIES_TO` relation sink. RECEIVES a fully-formed
 *  `REPLIES_TO` relation request and is responsible for minting it via
 *  the brain-side `autoEmitReplyRelation` (which calls `createRelation`
 *  from `@semantos/scg-relations`) AFTER the turn row exists. Default
 *  absent (dormant) in the intake child — the brain-side adapter wires
 *  it (see `makeReplyRelationEmitter` in
 *  `core/conversation-graph/src/auto-emit.ts`). Best-effort + isolated:
 *  a failure NEVER regresses turn persistence (mirrors the
 *  `BELONGS_TO_ENTITY` sink isolation). */
export type SemObjectReplyRelationSink = (
  relation: RepliesToRelation,
) => Promise<void> | void;

export interface RecordIntakeTurnArgs {
  /** Conversation/session id the patch attaches to. */
  readonly objectId: string;
  /** Authoring hat (the operator/site hat; customers aren't certs). */
  readonly hatId: string;
  readonly message: string;
  readonly stateSummary?: Record<string, unknown>;
  readonly reply: string;
  readonly action: { readonly type: string; readonly [k: string]: unknown };
  readonly model: string;
  /** The EXACT assembled prompt the LLM saw this turn (BASE_SYSTEM +
   *  system-injection + any ROM line). Hashed into the descriptor. */
  readonly assembledPrompt: string;
  /** Threads conversation + any derived/ratification patches. */
  readonly correlationId?: string;
  // ── Canonical-turn extensions (foundation PR; optional) ─────
  /** Surface this intake came in on. Defaults to 'widget' (today's
   *  intake-handler entry point). */
  readonly surface?: ConversationSurface;
  /** Operator's cert when known. The inbound turn's customer is
   *  always un-cert'd at intake time (external/tenant); only the
   *  reply turn may carry an actor cert (operator or AI). */
  readonly operatorCertId?: string;
  /** AI agent's cert when the reply was AI-produced. Today's intake-
   *  handler always uses the haiku LLM for replies, so this maps to
   *  the agent cert when one is provisioned. */
  readonly agentCertId?: string;
  /** Inbound participant role for the customer-side turn. Today the
   *  intake widget is anonymous (no cert, no resolved tenant), so
   *  defaults to 'external'. */
  readonly inboundParticipantRole?: ParticipantRole;
  // ── Inbound identity context (D-OJ-conv-multiparty-identity) ─
  /** Inbound party's L1 contact when known (E.164 phone). Binds the
   *  inbound `identityHandle` for un-cert'd roles. */
  readonly inboundPhone?: string;
  /** Inbound party's L1 contact when known (email address). Binds the
   *  inbound `identityHandle` for un-cert'd roles. */
  readonly inboundEmail?: string;
  /** Inbound party's L0 anonymous-session marker (browser cookie).
   *  Used when no phone/email yet — first widget contact. */
  readonly inboundCookie?: string;
  /** When the inbound party is a cert'd subcontractor/tradesman, their
   *  own Plexus-issued cert id. When absent, a subcontractor/tradesman
   *  role falls to `external` per §5.4 (no invented "guest cert"). */
  readonly inboundActorCertId?: string;
  /** Outbound participant role for the reply turn. Today the reply
   *  is ALWAYS produced by the haiku LLM (see reply-generator.ts:
   *  `replyText = await input.llm(...)`), so defaults to 'ai'.
   *  Operator-typed replies (when added in a future deliverable)
   *  should pass 'operator' here. */
  readonly outboundParticipantRole?: ParticipantRole;
  /** Domain lexicon hint. */
  readonly lexicon?: string;
  // ── Entity anchoring (D-OJ-conv-entity-anchoring) ───────────
  /** The job/site/customer entity this interaction concerns. When
   *  set, BOTH canonical turns (inbound + outbound) carry
   *  `entityRef` (denormalised for cheap reads, §4.1) AND — when a
   *  `relationSink` is wired — a `BELONGS_TO_ENTITY` relation is
   *  emitted per persisted turn (§7.1).
   *
   *  Determining the entity is the caller's responsibility (it lives
   *  where intake context is available — the job/lead id, the
   *  resolved customer cell, etc.). At today's anonymous-widget
   *  intake the entity is not yet known synchronously (the
   *  lead-on-contact job is minted REPL-side in the detached
   *  grandchild AFTER this turn persists — see `ensure-lead-job.ts`
   *  + `intake-handler.ts --detached-submit`), so this stays absent
   *  at that entry point. A future deliverable threads the minted
   *  lead's cell hash back so it can be set; until then a brain-side
   *  adapter that resolves the entity sets it. Surfaced in the PR
   *  body. */
  readonly entityRef?: {
    readonly kind: 'job' | 'site' | 'customer';
    readonly cellHash: string;
  };
  // ── Reply audit (D-OJ-conv-reply-audit-log) ─────────────────
  /** Extraction confidence score in [0, 1] for the OUTBOUND reply's
   *  driving intent. Optional — absent until D-OJ-conv-confidence-
   *  threshold wires confidence scoring through the reply path. Passed
   *  through verbatim into the reply-audit payload.
   *
   *  D-OJ-conv-confidence-threshold: when this value meets or exceeds
   *  `ratificationThreshold`, the outbound AI turn is auto-approved
   *  (`outboundState: 'approved'`) rather than parked as 'proposed'. */
  readonly replyConfidence?: number;
  /** D-OJ-conv-confidence-threshold: the minimum confidence required for
   *  an AI outbound turn to be auto-approved (outboundState: 'approved').
   *  Turns below this threshold start as 'proposed' (operator review queue).
   *  When absent, DEFAULT_RATIFICATION_THRESHOLD (0.85) is used.
   *  Load from cartridge.json via `loadRatificationConfig` in the caller. */
  readonly ratificationThreshold?: number;
  /** Operator's ratify/reject decision (absent for auto-sent replies
   *  that cleared the threshold without entering the operator queue). */
  readonly replyOperatorDecision?: 'ratified' | 'rejected';
  /** SIR / IR / cell hash chain produced by the reply path. Recorded
   *  opportunistically — absent when not available at emit time. */
  readonly replyCellChain?: string;

  // ── Quote affordance (D-ODDJOBZ-quote-affordance) ───────────
  /** EXPLICIT/STRUCTURAL reply reference: the prior turn id this
   *  inbound message replies to / quotes, as supplied by the SURFACE
   *  (the widget's "reply to this message" affordance, an email
   *  `In-Reply-To` header resolved to a turn id, a Meta Inbox reply
   *  reference, etc.). When set, it maps to the INBOUND canonical
   *  turn's `quotedTurnId` so the SCG cut-over's `autoEmitReplyRelation`
   *  can mint a `REPLIES_TO` edge from the inbound turn to the quoted
   *  prior turn (§13.8 explicit/structural path; the doc's
   *  inferred-from-content path — NLP "as you said earlier…" resolution
   *  — is a documented FOLLOW-UP, NOT built here).
   *
   *  Distinct from the OUTBOUND turn's `quotedTurnId`, which the
   *  foundation already sets to THIS interaction's inbound turn id
   *  (the reply quotes the message it answers). This field is the
   *  CROSS-INTERACTION case: the customer's NEW message itself quotes
   *  a turn from earlier in the thread.
   *
   *  Surfaces populate this the same way multiparty-identity wired
   *  `inboundPhone`/`inboundEmail` — the adapters (later deliverables:
   *  D-OJ-conv-widget-intake, -email-intake, -meta-inbox-bridge) set
   *  it; at today's anonymous-widget entry point it stays absent (no
   *  fabrication — a turn without an explicit reply marker carries no
   *  `quotedTurnId` on its inbound side).
   *
   *  VALIDATION (carry, don't pre-verify): we do NOT look up whether
   *  the referenced turn exists or belongs to the same conversation —
   *  that would require a sem_objects read from the intake child, which
   *  must not sync-call back into the single-thread brain reactor
   *  (project memory `semantos_brain_single_threaded_reactor`). Turn
   *  ids carry no embedded conversationId, so same-conversation can't
   *  be checked cheaply from the id alone either. We DO apply one cheap
   *  structural guard: a reference equal to the inbound turn's OWN id
   *  is dropped (a turn cannot quote itself). Target-existence /
   *  cross-conversation rejection is deferred to the brain-side
   *  `createRelation` / `autoEmitReplyRelation` (which already no-ops
   *  when the quoted turn is absent — see
   *  `core/conversation-graph/src/auto-emit.ts`). */
  readonly inReplyToTurnId?: string;

  // ── D-OJ-conv-per-turn-compression ──────────────────────────
  /** The SIRConstraints from the turn's reduced intent, forwarded so
   *  the NL-phrase relation resolver can detect and mint SCG relations
   *  (SUPPORTS, DISPUTES, CITES, SUPERSEDES, FORKS, REQUESTS_ACTION,
   *  FULFILLS, PAYS, ATTESTS, GRANTS_ACCESS, APPROVES) from phrases like
   *  "+1 on that", "I disagree", "see also: Y", etc.
   *
   *  Absent = no relation phrases detected this turn (pass-through
   *  no-op, nothing minted). The caller provides this from
   *  `handleConversationTurn`'s returned `intent.constraints`.
   *
   *  REPLIES_TO is intentionally excluded here — it is handled by the
   *  structural `quotedTurnId` → `replyRelationSink` path. BELONGS_TO_ENTITY
   *  has its own `relationSink`. REFERENCES_OBJECT is deferred (§13.10). */
  readonly reducerRelationConstraints?: ReadonlyArray<SIRConstraint>;
}

/**
 * Append-only jsonl conversation-log sink. One line per turn-patch:
 * `{objectId, ...ConversationPatchShape}`. Mirrors the existing
 * intake-handler messages.jsonl append idiom (mkdirSync recursive +
 * appendFileSync). The `write` dep `writeConversationPatch` expects.
 */
export function makeJsonlConversationSink(
  filePath: string,
): (objectId: string, patch: ConversationPatchShape) => void {
  return (objectId, patch) => {
    mkdirSync(dirname(filePath), { recursive: true });
    appendFileSync(
      filePath,
      JSON.stringify({ objectId, ...patch }) + '\n',
      'utf8',
    );
  };
}

// ── D-OJ-conv-multiparty-identity — per-role binding ──────────

/** The context a single participant's identity binding needs. */
export interface IdentityBindingContext {
  /** Operator-root cert id (L2). Required for the `operator` role.
   *  When absent for an operator turn, the binding leaves both
   *  actorCertId and identityHandle absent and the caller surfaces
   *  that the operator-root cert source wasn't available (we do NOT
   *  invent an identity source — §5.2). */
  readonly operatorCertId?: string;
  /** AI agent's child cert id (L2), when provisioned via
   *  `agent-cert-provider.ts`. Absent until `D-OJ-conv-ai-participant`
   *  threads it through — an `ai` turn then carries
   *  `AI_CERT_PENDING_SENTINEL` so the pending state is explicit. */
  readonly agentCertId?: string;
  /** A cert'd subcontractor/tradesman's own cert id (L2). When absent
   *  for a subcontractor/tradesman role, the role falls to `external`
   *  + L1 handle per §5.4 (no invented guest cert). */
  readonly subcontractorCertId?: string;
  /** Un-cert'd party's L1 phone (E.164). */
  readonly phone?: string;
  /** Un-cert'd party's L1 email. */
  readonly email?: string;
  /** Un-cert'd party's L0 anonymous-session cookie. */
  readonly cookie?: string;
}

/** The result of binding identity for one participant: the
 *  (possibly-narrowed) role plus exactly-one-of cert/handle (or
 *  neither, when an operator-root cert source was unavailable). */
export interface BoundIdentity {
  /** The effective role AFTER narrowing (e.g. an un-cert'd
   *  subcontractor narrows to `external`). */
  readonly role: ParticipantRole;
  /** L2 cert binding (operator/ai/cert'd-sub). Mutually exclusive
   *  with `identityHandle`. */
  readonly actorCertId?: string;
  /** L0/L1 handle (un-cert'd parties). Mutually exclusive with
   *  `actorCertId`. */
  readonly identityHandle?: IdentityHandle;
}

/** Pick the best available un-cert'd handle from the context:
 *  phone/email (L1) preferred over cookie (L0). Returns `undefined`
 *  when nothing is available (a fully-anonymous party with no marker
 *  at all — rare; the row then carries neither cert nor handle). */
function pickHandle(
  ctx: IdentityBindingContext,
): IdentityHandle | undefined {
  if (ctx.phone) return { kind: 'phone', value: ctx.phone };
  if (ctx.email) return { kind: 'email', value: ctx.email };
  if (ctx.cookie) return { kind: 'cookie', value: ctx.cookie };
  return undefined;
}

/**
 * Per-role identity binding (architecture doc §5; tiers per §13.2).
 *
 * Maps a participant role + available context onto the
 * actorCertId-XOR-identityHandle invariant:
 *
 *  - operator      → actorCertId = operator-root cert (L2). When the
 *                    operator-root cert source is unavailable, returns
 *                    neither (caller surfaces — we don't invent one).
 *  - ai            → actorCertId = AI agent cert (L2), or
 *                    `AI_CERT_PENDING_SENTINEL` when not yet
 *                    provisioned (D-OJ-conv-ai-participant binds the
 *                    real cert later).
 *  - subcontractor → actorCertId = their cert (L2) IF cert'd; else
 *  / tradesman       NARROWS to `external` + L1/L0 handle (§5.4 — no
 *                    invented guest cert).
 *  - tenant/owner/  → actorCertId = null, identityHandle = phone/email
 *    agent/external    (L1) or cookie (L0) per what's available (§5.5).
 *  - unknown       → handle if any (legacy/unmigrated; best-effort).
 *
 * Pure — no IO.
 */
export function bindParticipantIdentity(
  role: ParticipantRole,
  ctx: IdentityBindingContext,
): BoundIdentity {
  switch (role) {
    case 'operator':
      // §5.2 — operator-root cert. If the source isn't available,
      // surface (caller checks) rather than invent an identity.
      return ctx.operatorCertId
        ? { role: 'operator', actorCertId: ctx.operatorCertId }
        : { role: 'operator' };

    case 'ai':
      // §5.3 — AI's own child cert. Sentinel until
      // D-OJ-conv-ai-participant provisions + threads the real cert.
      return {
        role: 'ai',
        actorCertId: ctx.agentCertId ?? AI_CERT_PENDING_SENTINEL,
      };

    case 'subcontractor':
    case 'tradesman':
      // §5.4 — cert'd sub participates with their own cert; pre-cert
      // they fall to `external` identified by phone/email/cookie.
      if (ctx.subcontractorCertId) {
        return { role, actorCertId: ctx.subcontractorCertId };
      }
      return {
        role: 'external',
        ...(pickHandle(ctx) ? { identityHandle: pickHandle(ctx) } : {}),
      };

    case 'tenant':
    case 'owner':
    case 'agent':
    case 'external':
    case 'unknown':
    default:
      // §5.5 / §5.6 — un-cert'd. actorCertId null; bind the handle.
      return {
        role,
        ...(pickHandle(ctx) ? { identityHandle: pickHandle(ctx) } : {}),
      };
  }
}

/**
 * Derive the identity tier (§13.2) of a turn:
 *  - L2 if `actorCertId` is present (cert-bound — operator/ai/cert'd-
 *    sub; the AI pending sentinel still counts as L2 since the role
 *    IS cert-tier).
 *  - L1 if `identityHandle` is a phone/email/social handle.
 *  - L0 if `identityHandle` is a cookie (anonymous session marker).
 *
 * Returns `'L0'` as the conservative floor when neither is present
 * (a fully-anonymous, marker-less turn) — there's no tier below L0.
 *
 * Useful for downstream queries + the future merge deliverable
 * (`D-OJ-conv-identity-merge`, which merges L0/L1 participants).
 *
 * Pure — no IO. */
export function identityTier(turn: {
  readonly actorCertId?: string | null;
  readonly identityHandle?: IdentityHandle | null;
}): IdentityTier {
  if (turn.actorCertId) return 'L2';
  if (turn.identityHandle) {
    return turn.identityHandle.kind === 'cookie' ? 'L0' : 'L1';
  }
  return 'L0';
}

/** Build the two canonical turns (inbound customer + outbound reply)
 *  for an intake interaction. Pure — no IO. */
export function buildCanonicalTurns(
  args: RecordIntakeTurnArgs,
  correlationId: string,
  timestamp: number,
  inboundTurnId: string,
  outboundTurnId: string,
): {
  inbound: OddjobzConversationTurnPayload;
  outbound: OddjobzConversationTurnPayload;
} {
  // Legacy intake metadata, preserved verbatim as a bodyParts entry
  // (option (a) per ODDJOBZ-CONVERSATION-ARCHITECTURE.md §4.2). The
  // metadata describes the WHOLE interaction (it carries both the
  // message and the reply); we attach it to the outbound turn since
  // that's the turn the LLM-and-decision-tree actually produced.
  const intakeMeta: IntakeTurnBody = {
    kind: 'intake_turn',
    message: args.message,
    ...(args.stateSummary ? { stateSummary: args.stateSummary } : {}),
    reply: args.reply,
    action: args.action,
    model: args.model,
    prompt: intakeTemplateDescriptor(args.assembledPrompt),
  };

  const surface: ConversationSurface = args.surface ?? 'widget';

  // Inbound: the customer message. Today's widget intake is
  // anonymous (no cert, no resolved tenant identity), so the default
  // role is 'external'. The caller can override with
  // `inboundParticipantRole` once richer identity wiring lands.
  // D-OJ-conv-multiparty-identity: bind the inbound party's identity
  // per role. The inbound side is never the operator/ai (those are
  // outbound reply roles); it's a tenant/owner/agent/sub/external whose
  // L0/L1 handle is bound from the inbound contact context (phone/
  // email/cookie), or a cert'd subcontractor carrying their own cert.
  const inboundRole = args.inboundParticipantRole ?? 'external';
  const inboundBound = bindParticipantIdentity(inboundRole, {
    ...(args.inboundActorCertId
      ? { subcontractorCertId: args.inboundActorCertId }
      : {}),
    ...(args.inboundPhone ? { phone: args.inboundPhone } : {}),
    ...(args.inboundEmail ? { email: args.inboundEmail } : {}),
    ...(args.inboundCookie ? { cookie: args.inboundCookie } : {}),
  });

  // D-ODDJOBZ-quote-affordance: when the SURFACE supplies an explicit
  // reply reference (`inReplyToTurnId`), map it onto the INBOUND turn's
  // `quotedTurnId` so the SCG cut-over's `autoEmitReplyRelation` can
  // mint a REPLIES_TO edge (inbound turn → quoted prior turn). Cheap
  // structural guard only: drop a self-reference (a turn cannot quote
  // itself). Target-existence + cross-conversation checks are deferred
  // to the brain-side `createRelation` (no sync-call from the intake
  // child — see the field doc + `semantos_brain_single_threaded_reactor`).
  const inboundQuotedTurnId =
    args.inReplyToTurnId && args.inReplyToTurnId !== inboundTurnId
      ? args.inReplyToTurnId
      : undefined;

  const inbound: OddjobzConversationTurnPayload = {
    turnId: inboundTurnId,
    conversationId: args.objectId,
    participantRole: inboundBound.role,
    ...(inboundBound.actorCertId
      ? { actorCertId: inboundBound.actorCertId }
      : {}),
    ...(inboundBound.identityHandle
      ? { identityHandle: inboundBound.identityHandle }
      : {}),
    surface,
    direction: 'inbound',
    bodyText: args.message,
    ...(inboundQuotedTurnId ? { quotedTurnId: inboundQuotedTurnId } : {}),
    correlationId,
    timestamp,
    ...(args.entityRef ? { entityRef: args.entityRef } : {}),
    ...(args.lexicon ? { lexicon: args.lexicon } : {}),
  };

  // Outbound: the reply. Today's intake-handler ALWAYS routes the
  // reply through the haiku LLM (reply-generator.ts), so 'ai' is the
  // honest default. D-OJ-conv-multiparty-identity: bind per role —
  // operator → operator-root cert; ai → agent cert (or pending
  // sentinel). An operator turn with no operator cert leaves the
  // binding empty (surfaced — we don't invent an identity source).
  const outboundRole = args.outboundParticipantRole ?? 'ai';
  const outboundBound = bindParticipantIdentity(outboundRole, {
    ...(args.operatorCertId ? { operatorCertId: args.operatorCertId } : {}),
    ...(args.agentCertId ? { agentCertId: args.agentCertId } : {}),
  });

  // D-OJ-conv-ai-participant: set outboundState based on who produced
  // the reply. AI-produced turns start as 'proposed' (parked for
  // operator approval), UNLESS the confidence meets the ratification
  // threshold (D-OJ-conv-confidence-threshold) — in which case they
  // auto-approve and start as 'approved'.
  // Operator turns always start as 'drafted' (ready to send, subject
  // to the operator's own review). Confidence check is AI-only.
  //
  // §9 / §13.3 enforcement: state assignment at turn-construction time.
  // NOT a new SIR constraint kind; NOT a two-step intent.
  const threshold = args.ratificationThreshold ?? DEFAULT_RATIFICATION_THRESHOLD;
  const outboundState: OutboundState =
    outboundRole === 'operator'
      ? 'drafted'
      : meetsRatificationThreshold(args.replyConfidence, threshold)
        ? 'approved'
        : 'proposed';

  const outbound: OddjobzConversationTurnPayload = {
    turnId: outboundTurnId,
    conversationId: args.objectId,
    participantRole: outboundBound.role,
    ...(outboundBound.actorCertId
      ? { actorCertId: outboundBound.actorCertId }
      : {}),
    ...(outboundBound.identityHandle
      ? { identityHandle: outboundBound.identityHandle }
      : {}),
    surface,
    direction: 'outbound',
    bodyText: args.reply,
    bodyParts: [{ kind: 'oddjobz-intake-meta', payload: intakeMeta }],
    quotedTurnId: inboundTurnId,
    outboundState,
    correlationId,
    timestamp,
    ...(args.entityRef ? { entityRef: args.entityRef } : {}),
    ...(args.lexicon ? { lexicon: args.lexicon } : {}),
  };

  return { inbound, outbound };
}

/**
 * Build the `BELONGS_TO_ENTITY` relation set for a persisted turn.
 *
 * ONE-PER-TURN ENFORCEMENT POINT (§7.2 / §13.1): this builder is the
 * relation-pass-equivalent rejection point for the Oddjobz turn-persist
 * path. It returns AT MOST ONE relation — exactly one when the turn
 * carries an `entityRef`, zero when it doesn't. By construction a turn
 * can never carry two `BELONGS_TO_ENTITY` anchors: the set is a single
 * deterministic entry keyed off the turn's `entityRef`. (The
 * architecture doc §13.1 leans toward relation-pass enforcement; the
 * Oddjobz path doesn't route through the 10th reducer, so this builder
 * IS that enforcement point. A benchmark for an additional
 * createRelation-time guard is not needed because the source-of-truth
 * is this single-entry builder, not a reducer that could accumulate
 * duplicates.)
 *
 * Target-must-exist (§7.2) is NOT checked here — this builder has no
 * Database handle (it runs where intake context lives, not where the
 * Database lives). The brain-side `relationSink` that mints the
 * relation enforces target-must-exist before calling `createRelation`.
 *
 * Pure — no IO. */
export function buildTurnRelations(
  turn: OddjobzConversationTurnPayload,
): BelongsToEntityRelation[] {
  if (!turn.entityRef) return [];
  return [
    {
      kind: 'BELONGS_TO_ENTITY',
      turnId: turn.turnId,
      entityCellHash: turn.entityRef.cellHash,
      entityKind: turn.entityRef.kind,
    },
  ];
}

/**
 * Build the `REPLIES_TO` relation set for a persisted turn
 * (D-SCG-oddjobz-consumer-cutover).
 *
 * Returns AT MOST ONE relation — exactly one when the turn carries a
 * `quotedTurnId`, zero when it doesn't (the brain-side
 * `autoEmitReplyRelation` is vacuous in the latter case anyway). The
 * relation's source = THIS turn's id; target = the quoted prior turn's
 * id; `createdByCertId` = the turn's `actorCertId` from the
 * multiparty-identity binding (absent for un-cert'd turns).
 *
 * Mirrors `buildTurnRelations` (BELONGS_TO_ENTITY): this builder is the
 * deterministic single-entry assembly point; it has no Database handle
 * (it runs where intake context lives, not where the Database lives).
 * The brain-side `replyRelationSink` mints the relation. Pure — no IO. */
export function buildReplyRelations(
  turn: OddjobzConversationTurnPayload,
): RepliesToRelation[] {
  if (!turn.quotedTurnId) return [];
  return [
    {
      kind: 'REPLIES_TO',
      turnId: turn.turnId,
      quotedTurnId: turn.quotedTurnId,
      ...(turn.actorCertId !== undefined
        ? { authorCertId: turn.actorCertId }
        : {}),
    },
  ];
}

export interface RecordIntakeTurnDeps extends ConversationPatchDeps {
  /** Optional sem_objects sink — when set, fires alongside the
   *  jsonl `write` dep with the two canonical turns (inbound +
   *  outbound). Default no-op. */
  readonly semObjectSink?: SemObjectTurnSink;
  /** Optional `BELONGS_TO_ENTITY` relation sink (D-OJ-conv-entity-
   *  anchoring). When set AND the turn carries an `entityRef`, fires
   *  AFTER the turn's sem_objects row lands (so the relation source id
   *  exists). Default absent (dormant in the intake child — the
   *  brain-side adapter wires it; see `SemObjectRelationSink`). The
   *  relation emit is best-effort + isolated: a failure NEVER regresses
   *  turn persistence or the jsonl audit write (mirrors the
   *  sem-object-sink isolation). */
  readonly relationSink?: SemObjectRelationSink;
  /** Optional `REPLIES_TO` relation sink (D-SCG-oddjobz-consumer-cutover).
   *  When set AND a turn carries a `quotedTurnId`, fires AFTER the turn's
   *  sem_objects row lands (so the relation source id exists). Default
   *  absent (dormant in the intake child — the brain-side adapter wires
   *  it via `makeReplyRelationEmitter`). Best-effort + isolated: a
   *  failure NEVER regresses turn persistence or the jsonl audit write
   *  (mirrors the BELONGS_TO_ENTITY sink isolation).
   *
   *  PRODUCTION ACTIVATION GATED on `D-OJ-conv-sem-objects-sink-
   *  activation` (the real Database-backed sem_objects sink) — see the
   *  `SemObjectReplyRelationSink` doc-comment. */
  readonly replyRelationSink?: SemObjectReplyRelationSink;
  /** Optional reply-audit sink (D-OJ-conv-reply-audit-log). When set AND
   *  the sem_objects sink is wired, fires for the OUTBOUND turn AFTER its
   *  sem_objects row lands. Persists a `sem_objects` row of
   *  `objectKind='oddjobz.conversation.reply_audit'` carrying the prompt
   *  version ref + optional confidence + operator decision + cell chain.
   *
   *  Best-effort + isolated: a failure MUST NOT break the reply (mirrors
   *  the BELONGS_TO_ENTITY / REPLIES_TO sink isolation). Absent = dormant.
   *  The `promptVersionRef` for the reply prompt is resolved here (using
   *  PROMPT_IDS.reply) so the sink receives a fully-formed payload. */
  readonly replyAuditSink?: ReplyAuditSink;
  /** Optional NL-relation sink (D-OJ-conv-per-turn-compression). When set
   *  AND the sem_objects sink is wired AND the turn's reduced intent carries
   *  relation SIRConstraints, fires AFTER both turn rows land (source id
   *  exists). Mints the resolved canonical SCG relation for each eligible
   *  kind (SUPPORTS, DISPUTES, CITES, SUPERSEDES, FORKS, REQUESTS_ACTION,
   *  FULFILLS, PAYS, ATTESTS, GRANTS_ACCESS, APPROVES).
   *
   *  REPLIES_TO is intentionally excluded — handled by replyRelationSink.
   *  BELONGS_TO_ENTITY is excluded — handled by relationSink.
   *  REFERENCES_OBJECT is deferred pending §13.10 design resolution.
   *
   *  Best-effort + isolated: a failure MUST NOT break the reply or any
   *  prior sink (mirrors BELONGS_TO_ENTITY / REPLIES_TO isolation).
   *  Absent = dormant. */
  readonly nlRelationSink?: NlRelationSink;
}

/**
 * Emit one ConversationPatch + (when sink wired) two sem_objects
 * canonical turns for an intake interaction. Builds the versioned
 * `IntakeTurnBody` (input/output + template descriptor) for the
 * jsonl audit log, and the canonical inbound/outbound pair for the
 * sem_objects substrate.
 *
 * Both sinks fire best-effort and independently — a sem-object sink
 * failure is logged but does NOT regress the jsonl audit write or
 * the caller's reply.
 */
export async function recordIntakeTurn(
  args: RecordIntakeTurnArgs,
  deps: RecordIntakeTurnDeps,
): Promise<ConversationPatchResult> {
  // Existing path — unchanged on disk. The legacy IntakeTurnBody
  // rides as the ConversationPatch body, same as before.
  const body: IntakeTurnBody = {
    kind: 'intake_turn',
    message: args.message,
    ...(args.stateSummary ? { stateSummary: args.stateSummary } : {}),
    reply: args.reply,
    action: args.action,
    model: args.model,
    prompt: intakeTemplateDescriptor(args.assembledPrompt),
  };

  const jsonlResult = await writeConversationPatch(
    {
      objectId: args.objectId,
      hatId: args.hatId,
      body,
      source: 'nl',
      ...(args.correlationId
        ? { correlationId: args.correlationId as never }
        : {}),
    },
    deps,
  );

  // Canonical-shape (sem_objects) sink — fires when wired. We reuse
  // the patch's correlationId + timestamp so the audit-log and
  // sem_objects rows agree on threading. Each interaction = one
  // inbound + one outbound canonical turn (§4 of architecture doc).
  if (deps.semObjectSink) {
    try {
      const correlationId = String(jsonlResult.correlationId);
      const timestamp = jsonlResult.patch.timestamp;
      const inboundTurnId = `turn-in-${deps.generatePatchId()}`;
      const outboundTurnId = `turn-out-${deps.generatePatchId()}`;
      const { inbound, outbound } = buildCanonicalTurns(
        args,
        correlationId,
        timestamp,
        inboundTurnId,
        outboundTurnId,
      );
      await deps.semObjectSink(inbound);
      await deps.semObjectSink(outbound);

      // D-OJ-conv-reply-audit-log: emit the reply-audit row for the
      // OUTBOUND turn, AFTER the outbound turn row lands (so turnId
      // is a valid reference in sem_objects). Best-effort + isolated:
      // a failure MUST NOT regress turn persistence or the jsonl path.
      if (deps.replyAuditSink) {
        try {
          const auditPayload: OddjobzReplyAuditPayload = {
            turnId: outbound.turnId,
            promptVersionRef: promptVersionRef(PROMPT_IDS.reply),
            ...(args.replyConfidence !== undefined
              ? { confidence: args.replyConfidence }
              : {}),
            ...(args.replyOperatorDecision !== undefined
              ? { operatorDecision: args.replyOperatorDecision }
              : {}),
            ...(args.replyCellChain !== undefined
              ? { cellChain: args.replyCellChain }
              : {}),
            timestamp,
          };
          await deps.replyAuditSink(auditPayload);
        } catch (auditErr) {
          deps.logger.emit({
            ts: new Date().toISOString(),
            correlationId: jsonlResult.correlationId,
            intentId: null,
            stage: 'conversation_patch_written',
            durationMs: 0,
            hatId: args.hatId,
            source: 'nl',
            data: {
              replyAuditSinkError:
                auditErr instanceof Error
                  ? auditErr.message
                  : String(auditErr),
              turnId: outbound.turnId,
            },
          });
        }
      }

      // D-OJ-conv-entity-anchoring: emit the BELONGS_TO_ENTITY
      // relation per turn AFTER the turn row lands (source id now
      // exists). One-per-turn is structural (buildTurnRelations
      // returns at most one). Relation emit is independently isolated:
      // a relation-sink failure must NOT regress turn persistence (the
      // turn rows already landed above) — mirrors the foundation's
      // sink-failure-isolation. Each turn's relation is emitted in its
      // own try/catch so one turn's failure doesn't drop the other's.
      if (deps.relationSink) {
        for (const turn of [inbound, outbound]) {
          for (const rel of buildTurnRelations(turn)) {
            try {
              await deps.relationSink(rel);
            } catch (relErr) {
              deps.logger.emit({
                ts: new Date().toISOString(),
                correlationId: jsonlResult.correlationId,
                intentId: null,
                stage: 'conversation_patch_written',
                durationMs: 0,
                hatId: args.hatId,
                source: 'nl',
                data: {
                  belongsToEntitySinkError:
                    relErr instanceof Error
                      ? relErr.message
                      : String(relErr),
                  turnId: turn.turnId,
                },
              });
            }
          }
        }
      }

      // D-SCG-oddjobz-consumer-cutover: emit the REPLIES_TO relation
      // per turn that quotes a prior turn, AFTER the turn row lands
      // (source id now exists). One-per-turn is structural
      // (buildReplyRelations returns at most one). The brain-side
      // adapter (makeReplyRelationEmitter) maps the request onto
      // `autoEmitReplyRelation(db, …)`. Independently isolated: a
      // reply-relation-sink failure must NOT regress turn persistence
      // (the turn rows already landed above) — mirrors the
      // BELONGS_TO_ENTITY isolation. Each turn's relation is emitted in
      // its own try/catch so one turn's failure doesn't drop the other's.
      if (deps.replyRelationSink) {
        for (const turn of [inbound, outbound]) {
          for (const rel of buildReplyRelations(turn)) {
            try {
              await deps.replyRelationSink(rel);
            } catch (relErr) {
              deps.logger.emit({
                ts: new Date().toISOString(),
                correlationId: jsonlResult.correlationId,
                intentId: null,
                stage: 'conversation_patch_written',
                durationMs: 0,
                hatId: args.hatId,
                source: 'nl',
                data: {
                  repliesToSinkError:
                    relErr instanceof Error
                      ? relErr.message
                      : String(relErr),
                  turnId: turn.turnId,
                },
              });
            }
          }
        }
      }

      // D-OJ-conv-per-turn-compression: emit NL-phrase relations
      // detected by the 10th reducer pass (RM-030) AFTER both turn rows
      // land (source id exists). The resolver maps the inbound turn as
      // the source and resolves a target from context (explicit quote >
      // outbound turn from this interaction). Independently isolated: a
      // failure MUST NOT regress turn persistence or any prior sink.
      // REPLIES_TO excluded (structural path); BELONGS_TO_ENTITY excluded
      // (entity-anchoring sink); REFERENCES_OBJECT deferred (§13.10).
      if (deps.nlRelationSink && args.reducerRelationConstraints?.length) {
        const nlRelations = resolveNlRelations(
          args.reducerRelationConstraints,
          inbound,
          outbound,
        );
        for (const req of nlRelations) {
          try {
            await deps.nlRelationSink(req);
          } catch (relErr) {
            deps.logger.emit({
              ts: new Date().toISOString(),
              correlationId: jsonlResult.correlationId,
              intentId: null,
              stage: 'conversation_patch_written',
              durationMs: 0,
              hatId: args.hatId,
              source: 'nl',
              data: {
                nlRelationSinkError:
                  relErr instanceof Error
                    ? relErr.message
                    : String(relErr),
                nlRelationKind: req.kind,
                sourceId: req.sourceId,
                targetId: req.targetId,
              },
            });
          }
        }
      }
    } catch (e) {
      // Best-effort — the jsonl audit log already landed; never let
      // a sem-object sink failure regress the reply path. Logger
      // ride-along (no new dep): emit a stage event the caller's
      // logger already drains.
      deps.logger.emit({
        ts: new Date().toISOString(),
        correlationId: jsonlResult.correlationId,
        intentId: null,
        stage: 'conversation_patch_written',
        durationMs: 0,
        hatId: args.hatId,
        source: 'nl',
        data: {
          semObjectSinkError:
            e instanceof Error ? e.message : String(e),
        },
      });
    }
  }

  return jsonlResult;
}

// ── D-OJ-conv-ai-participant — OutboundStateSink ──────────────
//
// The sink that patches the `outboundState` field on a persisted
// `sem_objects` turn row. This is the "Option A" UPDATE path from the
// durability benchmark: a per-turn JSONB patch on `sem_objects.payload`.
// Called by `approveOutboundTurn` to drive the state machine:
//   proposed → approved → sent | failed
//
// The sink is INJECTED (not hardwired to a Database) so it remains
// testable in isolation and the brain-reactor boundary is preserved.

/** Patch the `outboundState` field on a persisted turn row (in-place
 *  JSONB UPDATE on `sem_objects`). Injected by the brain-side adapter
 *  (`makeOutboundStateSink` in `db.ts`). Default absent (dormant). */
export type OutboundStateSink = (
  turnId: string,
  newState: OutboundState,
) => Promise<void>;

// Re-exports for consumers that import from conversation-turn-patch
// rather than knowing about nl-relation-resolver directly.
export type { NlRelationRequest, NlRelationSink } from './nl-relation-resolver.js';

// ── D-OJ-conv-identity-merge — outbound payload annotation ───
//
// When the operator initiates an identity merge via the conversation module
// (§13.2), a reply turn of this shape is emitted toward the operator surface
// confirming the merge outcome. This type lives in the conversation module's
// type catalogue so operator-facing clients can discriminate the body part.
//
// The turn itself carries `direction: 'outbound'`, `participantRole: 'operator'`
// (it IS the operator-initiated action), and `bodyParts` containing one
// `OutboundIdentityMergePayload` entry of `kind: 'identity-merge-result'`.
//
// NOTE: the full HTTP endpoint + intent dispatch wiring is a SEPARATE
// deliverable — this type annotation ships here so the type catalogue is
// complete. The `processIdentityMerge` function in `identity-merge.ts` owns
// the core logic.

/** Body-part payload for a MERGES relation that has been confirmed by the
 *  operator. Carried in a turn's `bodyParts` array under
 *  `kind: 'identity-merge-result'`. Carries enough context for operator-
 *  facing UIs to surface a meaningful confirmation message. */
export interface OutboundIdentityMergePayload {
  readonly kind: 'identity-merge-result';
  readonly payload: {
    /** The participant that was merged away (the source of the MERGES edge). */
    readonly sourceParticipantId: string;
    /** The canonical participant that is retained (the target of the MERGES edge). */
    readonly targetParticipantId: string;
    /** The challenge question that was presented to the customer. */
    readonly challengeQuestion: string;
    /** Outcome of the merge operation. */
    readonly outcome:
      | 'merged'
      | 'challenge_not_confirmed'
      | 'same_identity'
      | 'already_merged';
    /** The `sem_objects.id` of the newly-minted MERGES relation, when the
     *  outcome is `'merged'`. Absent for failure outcomes. */
    readonly relationId?: string;
  };
}

```
