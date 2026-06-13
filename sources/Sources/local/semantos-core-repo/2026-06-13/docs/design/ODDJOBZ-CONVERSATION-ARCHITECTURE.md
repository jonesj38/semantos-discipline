---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/ODDJOBZ-CONVERSATION-ARCHITECTURE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.738254+00:00
---

# Oddjobz Conversation Architecture — entity-anchored, multi-party, multi-surface

Status: **Forward-looking architecture, drafted 2026-05-21.** Companion to
`ODDJOBZ-CONVERSATION-AS-SUBSTRATE-PROJECTION.md`. That doc is the
**implementation log** (P3.x decisions, debt items, build receipts
through 2026-05-18); this doc is the **target architecture**. The
PROJECTION doc owns "what landed and why"; this doc owns "where we're
going and what shape it has."

> **Scope.** This is the design for "conversation on a job/site/customer
> is a first-class citizen, multi-party, multi-surface, AI-participant
> inclusive." It pins the canonical turn shape, the participant model,
> the surface-adapter contract, the SCG relation catalog, and the
> deliverable decomposition. It does **not** restate `INTENT-PIPELINE.md`
> (substrate), `ODDJOBZ-CONVERSATION-AS-SUBSTRATE-PROJECTION.md`
> (implementation log), `CUSTOMER-CONV-LOOP-PLAN.md` (SMS TDD loop), or
> `SCG-IMPLEMENTATION-TRACKING.md` (SCG substrate). Each is
> cross-referenced; nothing is duplicated.

---

## 1. Executive summary

Oddjobz is supposed to be **conversations as first-class citizens on
jobs, sites and customers.** The operator works a job by going back and
forward with themselves, an AI agent, the tenant, the real estate
agent, the property owner, subcontractors, and other tradesmen. Every
one of those exchanges — whether it came in over the Oddjobz chat
widget, Meta Inbox (IG/FB DM), email, voice, SMS, or a historical CSV
import — is one stream over **one substrate**: `sem_objects` rows of
`objectKind='oddjobz.conversation.turn'`, anchored to the job/site/
customer entity by an SCG `BELONGS_TO_ENTITY` relation. Talk renders
the unified thread. Outbound replies (operator-drafted, AI-assisted,
operator-approved) ship out over whichever surface the customer uses
and are the same turn shape going the other way. Each turn drives the
compression gradient (NL → Intent → SIR → IR → cells); the 10th
reducer pass emits SCG relations as a side-effect, and a conversation
is itself a higher-order semantic object.

This doc owns:
- The 9 architecture pillars (§3).
- The canonical turn shape and how it relates to the existing
  `IntakeTurnBody` / `ConversationPatchShape` (§4).
- The multi-party identity model — `participantRole` enum, per-role
  identity binding (§5).
- The surface-adapter contract — what every protocol bridge must
  implement (§6).
- Entity anchoring (§7), outbound routing (§8), AI-participant
  integration (§9), per-turn compression (§10), and the SCG relation
  catalog (§11).
- The deliverable decomposition: **14 deliverables**, of which 11 are
  new (`D-OJ-conv-*`) and 3 are existing entries kept under their
  current names with cross-references (§12).
- Open questions and design decisions that need product input (§13).

---

## 2. What's already there

Build on what shipped; do not re-litigate.

### Substrate

- **`core/conversation-graph/`** (`@semantos/conversation-graph`,
  RM-031a/b) — substrate-level `Turn` + `autoEmitReplyRelation`. The
  `Turn` type carries `{ conversationId, turnId, quotedTurnId?,
  authorCertId? }` and is the minimal shape every domain pipeline
  normalises down to.
- **`core/scg-relations/`** — typed relations on `sem_objects`. 15
  canonical `RelationKind` values today: `REPLIES_TO`, `SUPPORTS`,
  `DISPUTES`, `SUPERSEDES`, `CITES`, `FORKS`, `REQUESTS_ACTION`,
  `FULFILLS`, `PAYS`, `ATTESTS`, `GRANTS_ACCESS`, `APPROVES`,
  `ESCROW_LOCKS`, `ESCROW_RELEASES`, `MERGES`. **`BELONGS_TO_ENTITY`
  does NOT exist yet** — adding it is part of D-OJ-conv-entity-anchoring
  (§12).
- **`runtime/intent/`** — `processIntent`, triage, `handleMessage`, the
  `ConversationPatchShape` writer, the ratification primitive, the
  full compression gradient (NL → Intent → SIR → IR → cells).
- **`runtime/intent/src/reducer/relation-pass.ts`** — 10th reducer
  pass (SCG §3.5) that emits SCG relations as a side-effect of the
  reduction. Wired but not consuming Oddjobz turns yet.

### Cartridge

- **`cartridges/oddjobz/brain/src/conversation/`** — Oddjobz's local
  conversation pipeline. Today it:
  - Persists turns to `oddjobz/conversation.jsonl` via
    `writeConversationPatch` + `makeJsonlConversationSink`
    (`conversation-turn-patch.ts`). The patch shape carries
    `IntakeTurnBody { kind:'intake_turn', message, stateSummary?,
    reply, action, model, prompt }`.
  - Threads with a flat `correlationId` UUID chain; **no
    `quotedTurnId`** — see PROJECTION doc §14 and the `D-ODDJOBZ-
    quote-affordance` deliverable.
  - Provisions an AI-agent child cert via `agent-cert-provider.ts`
    (P3.4 — operator-root signs the pairing token, agent child cert
    has narrow cap allowlist). This is the foundation the
    multi-participant model builds on.
- **`cartridges/oddjobz/brain/src/intake-handler.ts`** — spawn-bun-child
  intake path that creates turns. Runs as a stdin/stdout child of the
  brain reactor — must NOT sync-call back into the brain (project
  memory `semantos_brain_single_threaded_reactor`).

### Decisions already pinned (PROJECTION doc)

- **A3 transport — Option C** (2026-05-17): brain↔TS over the
  shipped envelope path, no new transport surface.
- **A4 — DISSOLVED** (2026-05-18): customer→brain auth bridge exists
  in prod (passphrase-derived operator-root key per
  `BRIDGE-OPERATOR-IDENTITY`).
- **A5 — pricing policy as Ricardian operator-config cell** (pending,
  deferred; not load-bearing for this doc).
- **P4C — Option (ii)-pure decoupled sellable cartridge** (operator,
  2026-05-18). The AI-agent integration follows this shape.
- **SD2 — lead-on-contact, ROM-optional + lead→authorized edge**
  (operator, 2026-05-18).
- **SD3 — MANIFEST-PRIMARY** (operator, 2026-05-18).
- **Self-call deadlock** (live outage 2026-05-18, recovered): intake
  child uses the **detached grandchild submitter** pattern. Anything
  this doc proposes must respect that boundary.

### Matrix row

- **U12 — Conversation Graph (SCG)** in
  `docs/canon/unification-matrix.yml`. Phase 1 substantially landed
  (RM-010..082); the Oddjobz consumer cut-over (D-SCG-oddjobz-
  consumer-cutover) is now **merged-with-caveat** (2026-05-22, after the
  two pre-reqs `D-ODDJOBZ-turns-as-sem-objects` + `D-ODDJOBZ-quote-
  affordance` landed): the `autoEmitReplyRelation` wiring + canonical→Turn
  mapping + tests ship via an injected `replyRelationSink` (cartridge) and
  the brain-side `makeReplyRelationEmitter` (conversation-graph).
  **Production activation is GATED** on the real Database-backed
  sem_objects sink — tracked as `D-OJ-conv-sem-objects-sink-activation`
  (the same gate as the dormant `BELONGS_TO_ENTITY` sink).

---

## 3. Architecture pillars

Nine pillars; each ~200 words. Each pillar is the design intent — the
"why this shape" — that the deliverables operationalise.

### 3.1 Entity-anchored conversation graph

The unit of "where a conversation lives" is the **entity** —
job/site/customer. Each entity is a cell (oddjobz.{job,site,
customer}.v2, minted via the cell-DAG mint path landed by D-DOG.1.0c).
A conversation is a directed acyclic graph of turns, all sharing one
`BELONGS_TO_ENTITY` relation to that entity. The graph is **not** an
opaque thread blob; it is `sem_objects` rows tied together by SCG
edges. A conversation thread is therefore queryable, projectable, and
referenceable by other entities (a quote can `CITES` a specific turn,
an invoice can `FULFILLS` a `REQUESTS_ACTION` turn). When you load a
job, you load its conversation graph; when you re-anchor a turn (e.g.
"that lead-job was actually two jobs"), you re-point its
`BELONGS_TO_ENTITY` relation. The graph stays content-addressed,
append-only, and replayable — corrections are new turns and new
relations, not destructive edits.

### 3.2 Multi-party participant model

Participants are an enumerated set: **operator, ai, tenant, agent
(real-estate or other), owner, subcontractor, tradesman, external**.
Each participant carries identity proportional to their role — the
operator has the operator-root cert; the AI agent has a narrow
operator-issued child cert (already shipped via
`agent-cert-provider.ts`); subcontractors and other tradesmen hold
their own Semantos certs once Plexus issues them; tenants/owners/
agents are typically un-cert'd third parties identified by phone /
email and bound by a `participantRole + identityHandle` pair (see
§5.5). The **AI agent is first-class**, not a tool: it produces turns
with `participantRole='ai'`, its replies pass through the same
draft/approve/send state machine as any other outbound turn, and its
capability scope is structurally pinned by the operator-signed
pairing token. The `participantRole` enum is the single
authoritative discriminator — every consumer (Talk renderer, intent
extractor, access gate) keys off it.

### 3.3 Multi-surface intake, one substrate

Oddjobz chat widget, Meta Inbox (IG/FB DMs), email (gmail reingest),
voice, SMS (Twilio per `CUSTOMER-CONV-LOOP-PLAN.md`), and historical
CSV import all funnel into the **same** substrate path: a sem_objects
row of `objectKind='oddjobz.conversation.turn'`. Per the project
memory `semantos_streams_shell_native`, the conversation engine ships
native in the shell; Meta Inbox / IG / FB / Slack / Discord-style
clients are **protocol-bridge adapters**, NOT cartridges. The adapter
implements one well-typed interface (§6) that maps the surface's
native message shape onto the canonical turn shape (§4) and binds the
incoming identity to a `participantRole`. This is the
canonical-schema-spine fix from project memory
`semantos_canonical_schema_spine` — source shape ≠ cell ≠ model ≠
UI; the adapter is the normalisation seam.

### 3.4 Talk renders the unified thread

Whatever surface a turn entered on, Talk shows it as one stream over
the entity. The render layer reads from `sem_objects` (filtered by
`BELONGS_TO_ENTITY` to the entity) plus the SCG relation graph
(`REPLIES_TO` reconstructs nesting; `REFERENCES_OBJECT` annotates
cross-entity mentions). Per-turn metadata (`surface`, `participantRole`,
`actorCertId`) lets Talk colour, group, or filter. The shell stays
the only UI; protocol-bridge adapters never own UI surface. Talk's
single-stream view is what makes "one conversation per entity" feel
real to the operator regardless of how the customer chose to reach
them.

### 3.5 Outbound is symmetric

An operator-drafted reply (often AI-assisted) → operator approves →
ships out via whichever surface the customer uses. The outbound turn
is the **same shape** as inbound; it differs only in `surface`
(outbound carries the destination surface, which the surface adapter
uses to route), `participantRole` (operator or ai), and an outbound
state-machine field (`drafted`/`proposed`/`approved`/`sent`/
`delivered`/`failed`). No separate "outbox" log — the conversation
graph itself is the outbox. Symmetry is what unlocks the operator
"never leave Talk" workflow: every reply is a turn in the same
substrate as the inbound it answers, related by `REPLIES_TO`.

### 3.6 AI agent as first-class participant

The AI agent has its own cert (the `agent-cert-provider.ts` shipped
P3.4 child cert) under the operator root. Capability scope is the
operator-signed pairing token's narrow allowlist (cannot mint quotes
without operator approval, cannot send outbound without traversing
the approval state machine, etc.). The agent's turns are tagged
`participantRole='ai'`; its drafts sit in the same draft/approve/
send pipeline as operator drafts. Per the project memory
`semantos_no_ai_in_substrate`, the LLM call stays at the edge — the
agent's turn-producer is a producer adapter, the substrate sees only
`sem_objects` writes. This puts the AI on the same footing as a
subcontractor or operator — it can be cited, replied-to, escrow-
attested, paid (future) — without the substrate caring that it
happens to be powered by a model.

### 3.7 Compression gradient per turn

Every turn drives the existing compression gradient
(`runtime/intent/`): NL text → Intent (typed classifier output) → SIR
(semantic IR) → IR (lowered bytecode) → cells (minted by
`processIntent`). The pipeline runs PER-TURN. The 10th reducer pass
(`runtime/intent/src/reducer/relation-pass.ts`, SCG §3.5) is the
bridge from "turn produced an intent" to "an SCG relation should be
emitted." For example: a turn whose intent is `accept_rom` and that
targets a job whose pending ROM was authored by the AI emits both a
`REPLIES_TO` (to the AI's ROM turn) and an `APPROVES` (operator → AI
ROM proposal). The compression gradient stays the same; only the
side-effect catalog grows.

### 3.8 SCG relations annotate the graph

The relation catalog (§11) is how the conversation graph carries
meaning beyond chronological order. `REPLIES_TO` reconstructs
threading. `BELONGS_TO_ENTITY` anchors a turn to a job/site/customer
(NEW; see D-OJ-conv-entity-anchoring). `REFERENCES_OBJECT` (NEW;
candidate kind) annotates when a turn mentions a different entity
("we also need to follow up with the tenant on 14 Acacia"). Future
economic relations from SCG Phase 3 (`PAYS`, `ESCROW_LOCKS`,
`GRANTS_ACCESS`) hang off turns once the wallet integration lands
(D-SCG-wallet-integration). The relations are themselves
`sem_objects` rows — same recovery, hash chain, capability-gated
mint as any other cell — so the conversation graph IS a Semantos
cell DAG.

### 3.9 Conversation as higher-order semantic object

A conversation thread isn't just a list of turns; it's a SIR-
aggregable semantic object. The aggregate carries (a) the entity ref,
(b) participants set, (c) summarised intent state (what's still open,
what's ratified), (d) outbound state machine snapshot. The aggregate
is the object you reference from outside the conversation — "the
quote derived from conversation Q" attaches a `CITES` relation to the
conversation aggregate, not to a specific turn. The aggregate is
deterministic over the patch stream (per the
`semantos_dx_priorities` memory's "snapshot/replay determinism"
constraint), so any two nodes with the same turn-patch sequence
project the same aggregate. This is D-OJ-conv-aggregate-sir.

---

## 4. Canonical turn shape

The canonical turn shape that the surface adapters target. Designed to
extend, not replace, `IntakeTurnBody` and `ConversationPatchShape`.

### 4.1 Schema

```ts
/** A row of objectKind='oddjobz.conversation.turn' in sem_objects. */
interface OddjobzConversationTurn {
  /** sem_objects.id — canonical turnId per the conversation-graph Turn type. */
  readonly turnId: string;

  /** Conversation aggregate id. Per-entity by construction:
   *  for an entity E, conversationId = hash(E.cellHash). */
  readonly conversationId: string;

  /** The job/site/customer cell hash this turn belongs to.
   *  Persisted as a BELONGS_TO_ENTITY relation, also denormalised
   *  on the row for cheap reads. */
  readonly entityRef: { kind: 'job' | 'site' | 'customer'; cellHash: string };

  /** Who said it. Single source of truth for downstream filters. */
  readonly participantRole:
    | 'operator' | 'ai' | 'tenant' | 'agent' | 'owner'
    | 'subcontractor' | 'tradesman' | 'external';

  /** Identity binding for the participant. cert_id when cert-bound;
   *  null when external (a phone-only tenant has no cert). When null,
   *  identityHandle carries the binding token (E.164 phone, email
   *  address, IG/FB handle, etc.). */
  readonly actorCertId: string | null;
  readonly identityHandle: { kind: 'phone' | 'email' | 'ig' | 'fb' | 'free'; value: string } | null;

  /** The surface this turn entered (or, for outbound, leaves) on. */
  readonly surface: 'widget' | 'meta-inbox' | 'email' | 'voice' | 'sms' | 'import';

  /** Direction. */
  readonly direction: 'inbound' | 'outbound';

  /** Plain-text body (the operator-readable summary; the canonical
   *  message). */
  readonly bodyText: string;

  /** Structured body parts — attachments, transcripts, structured
   *  intent-extractor outputs. Each part has a kind discriminator. */
  readonly bodyParts: ReadonlyArray<{
    kind: 'attachment' | 'transcript' | 'extracted-intent' | 'rom-proposal' | 'quote' | 'ratification';
    payload: unknown;  // shape per kind, lexicon-governed
  }>;

  /** SCG: when set, autoEmitReplyRelation emits a REPLIES_TO edge. */
  readonly quotedTurnId?: string;

  /** Correlation id — keeps the existing intent-pipeline threading
   *  semantics (handleMessage / processIntent / ratification all
   *  share a correlationId per turn). */
  readonly correlationId: string;

  /** Outbound state machine. Populated for direction='outbound' only. */
  readonly outboundState?:
    | 'drafted' | 'proposed' | 'approved' | 'sent' | 'delivered' | 'failed';

  /** Per-turn template-version descriptor when the turn was AI-produced
   *  (mirrors today's IntakeTurnBody.prompt). */
  readonly prompt?: TemplateVersionDescriptor;

  /** Server clock at persist time. */
  readonly persistedAt: string;  // ISO 8601
}
```

### 4.2 Relationship to existing shapes

- **`IntakeTurnBody` (today)** — kept as the **bodyParts payload**
  for the `extracted-intent` part kind, NOT as the row body.
  Migration path: the existing `recordIntakeTurn` writes a sem_objects
  row whose `bodyParts` carries an `extracted-intent` part whose
  payload is the legacy `IntakeTurnBody`. No data loss; new consumers
  read the row's structured `bodyText` + `bodyParts`; legacy consumers
  can still project the `IntakeTurnBody` from the part.
- **`ConversationPatchShape`** — the substrate primitive
  (`writeConversationPatch`) still writes the patch. The patch's
  `delta.body` carries the canonical turn shape above instead of the
  today's `IntakeTurnBody`. The patch sink upgrades from the jsonl
  appender to a sem_objects writer (D-OJ-conv-turns-as-sem-objects).
  The jsonl can stay as a secondary audit-log projection.
- **`Turn` (conversation-graph)** — produced by projecting
  `{ conversationId, turnId, quotedTurnId, authorCertId: actorCertId }`
  off the row. Passed straight to `autoEmitReplyRelation`.

---

## 5. Multi-party identity model

**Status: per-role binding LANDED 2026-05-22** (D-OJ-conv-multiparty-
identity, feat/oj-conv-multiparty-identity). The enum (§5.1) shipped
with the foundation (#535); `bindParticipantIdentity` /
`identityTier` / the `identityHandle` field now implement the tiered
binding below (§5.2–§5.6 + §13.2). The MERGES capability over
`identityHandle` remains the separate `D-OJ-conv-identity-merge`.

### 5.1 The enum

```ts
type ParticipantRole =
  | 'operator'        // the Oddjobz operator (tradesperson)
  | 'ai'              // operator's AI assistant (own child cert)
  | 'tenant'          // resident of the site
  | 'agent'           // real estate agent / property manager
  | 'owner'           // property owner / landlord
  | 'subcontractor'   // operator's hired sub
  | 'tradesman'       // other tradesperson in the conversation
  | 'external';       // catch-all (utility provider, insurer, etc.)
```

### 5.2 Operator

Operator-root cert (Plexus-issued, passphrase-derived per
`BRIDGE-OPERATOR-IDENTITY`). Holds all capabilities by default;
ratifies proposals; signs outbound. `actorCertId = operator-root
cert_id`.

### 5.3 AI

Narrow child cert under the operator root. Already shipped:
`agent-cert-provider.ts` pairs once via an operator-signed pairing
token, capability allowlist is structurally pinned. The AI's outbound
turns are `drafted`/`proposed` only — they require operator
approval to transition to `approved`/`sent`. The state machine
itself is enforced by `processIntent` (an `ai_send` intent without an
accompanying operator ratification is structurally rejected at SIR
lowering, mirroring how customer-tier mutations on operator-tier
state are rejected today).

### 5.4 Subcontractors & other tradesmen

Once Plexus issues them their own cert, they participate with
`actorCertId = their cert_id`. Pre-cert they participate as `external`
identified by phone/email — see §5.5. There is no "guest cert"; we do
not invent identity primitives just for this case.

### 5.5 Tenants, owners, agents, external (un-cert'd)

`actorCertId = null`, `identityHandle = { kind: 'phone' | 'email', value }`.
The identity is bound by the entity (the job's site has the tenant's
phone; the conversation is via that phone). For the same phone seen
on a new job, the operator confirms identity in-Talk (an explicit
"this is the same tenant" intent emits a `MERGES`-style relation or
a simple identity assertion turn). No invented cert; the phone IS
the identity until Plexus issues one.

### 5.6 External

Catch-all for parties that don't fit the enum (utility provider
calling about the meter, insurer, council). Carries
`identityHandle` only. Useful for inbound CRM-style threads where
the operator wants the convo logged against a site but the other
party isn't a normal customer-shaped contact.

---

## 6. Surface adapter contract

Per `semantos_streams_shell_native`: protocol-bridge adapters are
**not** cartridges. They run as substrate-side adapters that take a
native protocol payload, map to the canonical turn shape, and submit
it via the brain's existing intent submission path (the detached
grandchild submitter pattern from the 2026-05-18 self-call deadlock
fix).

### 6.1 Abstract interface

```ts
interface ConversationSurfaceAdapter {
  /** Identifier — matches `surface` field on the canonical turn. */
  readonly surface: 'widget' | 'meta-inbox' | 'email' | 'voice' | 'sms' | 'import';

  /** Map a native protocol payload to a canonical turn. May return
   *  multiple turns (e.g. an email thread import is many turns). */
  ingest(payload: unknown, ctx: AdapterContext): Promise<OddjobzConversationTurn[]>;

  /** Send an outbound turn. Adapter looks up the route from the
   *  entity's contact info, marshalls the canonical turn to the
   *  native protocol shape, sends, and returns the delivered/failed
   *  state. */
  send(turn: OddjobzConversationTurn, ctx: AdapterContext): Promise<{
    state: 'delivered' | 'failed';
    surfaceMessageId?: string;
    error?: string;
  }>;
}

interface AdapterContext {
  /** The operator's cert; adapters need it to sign outbound and
   *  to authenticate to upstream provider APIs as the operator. */
  readonly operatorCert: Brc52Cert;
  /** Lookup entity from a `kind+identityHandle` pair (e.g. resolve
   *  a phone number to a customer cell). */
  resolveEntity(handle: { kind: string; value: string }): Promise<{ cellHash: string; kind: 'job' | 'site' | 'customer' } | null>;
  /** Submit a canonical turn through the standard intake path. */
  submitTurn(turn: OddjobzConversationTurn): Promise<void>;
}
```

### 6.2 Concrete adapters (each is a deliverable)

| Surface | Inbound shape | Identity strategy |
|---|---|---|
| `widget` | Oddjobz chat-widget WS payload | `external` by phone (pre-cert'd customer flow) |
| `meta-inbox` | IG/FB Graph API DM webhook payload | `tenant`/`owner`/`external` by FB/IG handle |
| `email` | Gmail watch/pubsub envelope | `agent`/`owner`/`external` by email address |
| `voice` | Voice-note payload (per `voice_notes_workflow` memory) | `operator` (voice-to-self) or third-party transcript |
| `sms` | Twilio inbound webhook (per `CUSTOMER-CONV-LOOP-PLAN.md`) | by E.164 phone |
| `import` | Historical CSV / IG legacy export | best-effort by phone/email; turns flagged `historical:true` in bodyParts |

Each adapter has its own canon deliverable (§12).

### 6.3 Identity-binding policy

If `resolveEntity` returns a hit, the turn's `entityRef` is set; if
not, the adapter creates a `lead`-state job (SD2: lead-on-contact)
and anchors the turn there. The operator can later re-anchor.

---

## 7. Entity anchoring

### 7.1 The relation

`BELONGS_TO_ENTITY` — new SCG `RelationKind` (D-OJ-conv-entity-
anchoring). Source = `sem_objects.id` of the turn; target =
`sem_objects.id` of the job/site/customer row.

### 7.2 Constraints

- **One per turn.** Every turn has exactly one `BELONGS_TO_ENTITY`
  relation. Enforced at `createRelation` time by a constraint in
  `runtime/intent/src/reducer/relation-pass.ts` (or in the
  `BELONGS_TO_ENTITY` mint code path — design choice, see §13).
- **Target must exist.** A turn cannot anchor to a non-existent
  job/site/customer cell. Enforced by lookup at mint time.

### 7.3 Lifecycle

- **First contact, no entity yet.** SD2 says lead-on-contact: the
  first turn against a phone with no entity match auto-mints a
  `lead`-state job and anchors there. The conversation starts at the
  same time as the entity.
- **Re-anchoring.** Operator says "this is actually two jobs."
  Operator action emits new `BELONGS_TO_ENTITY` relations for each
  affected turn and revokes the originals. The pre-image (original
  anchoring) stays in the patch chain — corrections are new patches.

---

## 8. Outbound routing

### 8.1 State machine

```
drafted → proposed → approved → sent → delivered | failed
                ↓
            rejected (terminal)
```

- **`drafted`** — operator or AI is composing.
- **`proposed`** — AI has produced a draft awaiting operator
  approval, OR operator has produced a draft awaiting their own
  "send."
- **`approved`** — operator approved (clicked send / ratified the AI
  proposal). The intent pipeline mints an `outbound_send` intent.
- **`sent`** — the surface adapter has accepted the send and is
  awaiting confirmation.
- **`delivered` / `failed`** — terminal states reported by the
  adapter.

### 8.2 Surface selection

Default: the surface the customer uses (look up `surface` from the
most recent inbound turn from the same identity on the same entity).
Operator override available (e.g. customer always emails but operator
wants to call them — opens a new `voice` surface).

### 8.3 Symmetry

Outbound turn shape is the same as inbound. The surface adapter's
`send` method consumes the canonical turn and returns the
`delivered`/`failed` state; the state-machine projection updates the
turn's `outboundState` accordingly.

---

## 9. AI participant integration

### 9.1 Cert provisioning

Already shipped (P3.4): `cartridges/oddjobz/brain/src/conversation/
agent-cert-provider.ts`. Operator-root signs the pairing token,
agent cert is a child with a narrow capability allowlist.

### 9.2 Capability scope

What the agent can do without operator approval:
- Read its own conversations and their entities.
- Propose ROMs (existing flow — `accept_rom` requires operator-side
  ratification).
- Draft outbound turns (state stays in `proposed` until operator
  approves).

What the agent CANNOT do:
- Send outbound without operator approval.
- Mint quotes/invoices without operator approval.
- Re-anchor turns or merge entities.

Enforced **structurally** at SIR lowering (mirrors the customer-tier
case): an `outbound_send` intent signed by `participantRole='ai'`
without an accompanying operator ratification is rejected at
lowering, not at runtime.

### 9.3 LLM at the edge

Per `semantos_no_ai_in_substrate`: the LLM call lives in the
producer adapter (the agent's turn-producer). The substrate sees only
`sem_objects` writes. No agent or MCP runs inside the brain or the
cell engine.

---

## 10. Compression gradient integration

Per `runtime/intent/`:

```
NL text  →  Intent  →  SIR  →  IR  →  Cells
                              ↓
                       relation-pass (10th reducer)
                              ↓
                       SCG relations (REPLIES_TO,
                        BELONGS_TO_ENTITY, REFERENCES_OBJECT, …)
```

Each turn runs the gradient. The 10th reducer pass emits the SCG
relations as a side-effect of the reduction. Two consequences:

1. **The conversation graph is built by the same pipeline that runs
   ratifications.** No separate "conversation reducer."
2. **A new turn that quotes a prior turn AND ratifies a pending
   proposal emits BOTH a `REPLIES_TO` and an `APPROVES` in one
   reduction.**

D-OJ-conv-per-turn-compression is the wiring deliverable.

---

## 11. SCG relation catalog

Existing kinds and where they apply on Oddjobz conversations:

| Kind | Source | Target | Use on Oddjobz |
|---|---|---|---|
| `REPLIES_TO` | turn | turn | Threading; auto-emitted by `autoEmitReplyRelation` when `quotedTurnId` is set. **Cut-over wired 2026-05-22 (D-SCG-oddjobz-consumer-cutover, merged-with-caveat)**: cartridge `replyRelationSink` → brain-side `makeReplyRelationEmitter`. Dormant in production until `D-OJ-conv-sem-objects-sink-activation`. |
| `APPROVES` | turn | turn (the proposal turn) | Operator approves an AI proposal or a customer-tier ratification. |
| `SUPERSEDES` | turn | turn | Operator corrects a previously-sent turn ("ignore my last message, the actual price is…"). |
| `REQUESTS_ACTION` | turn | turn or entity | Customer asks operator to do something. |
| `FULFILLS` | turn or entity | turn | Operator's action turn fulfills a prior `REQUESTS_ACTION`. |
| `CITES` | turn or other object | turn | A quote/invoice/job-detail object cites the turn that authorised it. |
| `ATTESTS` | turn | object | A turn attests something about an entity (e.g. operator confirms tenant identity). |
| `PAYS` | turn | turn or invoice | Payment turn pays an invoice — money-bearing per RM-060. |
| `GRANTS_ACCESS` | turn | turn (paid content) | Reserved for Phase-3 paid-content gating. |
| `ESCROW_LOCKS` / `ESCROW_RELEASES` | turn | turn | Reserved for Phase-3 escrow on conversation outcomes. |

New kinds proposed (D-OJ-conv-entity-anchoring):

| Kind | Source | Target | Use |
|---|---|---|---|
| `BELONGS_TO_ENTITY` | turn | job / site / customer | Anchors every turn to an entity. |
| `REFERENCES_OBJECT` | turn | any sem_object | Turn mentions another entity ("we should follow up with the tenant at 14 Acacia"). Allows cross-entity threading without re-anchoring. |

Both kinds extend the existing `RelationKind` union in
`core/scg-relations/src/types.ts`; both add to
`relationLexicon` (15 → 17 kinds); `verifyLexiconInjective` keeps
passing because the kinds are still string-identity.

---

## 12. Deliverable decomposition

14 deliverables. Three are existing entries (kept under their current
names, cross-referenced); eleven are new under the `D-OJ-conv-*`
namespace.

**Naming reconciliation:** the existing `D-ODDJOBZ-turns-as-sem-objects`
and `D-ODDJOBZ-quote-affordance` (added 2026-05-21 via PR #529) are
kept under their current names. The new D-OJ-conv-* entries
cross-reference them. Renaming the two existing entries to the new
namespace was considered but rejected — PR #529 just merged with
those names, and renaming would invalidate the rationale captured in
the cut-over deliverable. Naming consistency is less valuable than
not invalidating a freshly-shipped PR's references.

### Existing deliverables (cross-referenced, NOT renamed)

1. **`D-ODDJOBZ-turns-as-sem-objects`** — turns are sem_objects rows.
   Foundation for everything below. Surfaced via PR #529; **landed
   2026-05-22 via feat/oddjobz-turns-as-sem-objects** (dual-sink
   persistence: jsonl audit log + canonical sem_objects shape; option
   (a) `IntakeTurnBody` as bodyParts entry; sink is injected so a
   future brain-side adapter wires it without violating the
   single-thread-reactor self-call guard).
2. **`D-ODDJOBZ-quote-affordance`** — quoting UI + extractor. Surfaced
   via PR #529; **landed 2026-05-22 via feat/oj-conv-quote-affordance**
   (explicit/structural path only — `RecordIntakeTurnArgs.inReplyToTurnId`
   maps to the inbound canonical turn's `quotedTurnId`; surfaces
   populate the field like multiparty-identity wired
   `inboundPhone`/`inboundEmail`; self-reference dropped, target-
   existence deferred to `autoEmitReplyRelation`. The inferred-from-
   content path (§13.8) — NLP "as you said earlier…" → turn resolution
   — is a documented FOLLOW-UP, not built).
3. **`D-SCG-oddjobz-consumer-cutover`** — REPLIES_TO auto-emit. **LANDED
   merged-with-caveat 2026-05-22.** The cartridge gains a
   `RepliesToRelation` request + `buildReplyRelations` (one-per-turn) +
   an injected `replyRelationSink` (fired per quoting turn after the row
   lands, isolated). The brain-side adapter
   `makeReplyRelationEmitter(db, opts)` (in
   `core/conversation-graph/src/auto-emit.ts`) maps the request → `Turn`
   → `autoEmitReplyRelation(db, …)`. Mapping: turnId→source,
   quotedTurnId→target, actorCertId→createdByCertId; capabilityCheck
   forwarded. Production flip-on is GATED on
   `D-OJ-conv-sem-objects-sink-activation` (the cartridge stays
   Database-free; the intake child never sync-calls the brain).

### New deliverables (`D-OJ-conv-*`)

4. **`D-OJ-conv-entity-anchoring`** — add `BELONGS_TO_ENTITY` SCG
   relation kind; wire every turn-write to mint one. Mechanical once
   D-ODDJOBZ-turns-as-sem-objects lands.
5. **`D-OJ-conv-multiparty-identity`** — `participantRole` enum +
   per-role identity binding. Includes the `identityHandle` shape
   for un-cert'd parties. **LANDED 2026-05-22 via
   feat/oj-conv-multiparty-identity** (`identityHandle` field on the
   canonical turn; `bindParticipantIdentity` maps each role to L2 cert
   or L0/L1 handle per §5 + §13.2; `identityTier` derives L0/L1/L2; AI
   cert uses a documented pending sentinel until D-OJ-conv-ai-participant
   provisions it; the MERGES capability is the separate
   D-OJ-conv-identity-merge).
6. **`D-OJ-conv-widget-intake`** — wire the existing chat widget to
   produce canonical turns through the substrate.
7. **`D-OJ-conv-meta-inbox-bridge`** — IG/FB DM protocol bridge.
   Large deliverable — Meta Graph API auth, webhook receiver,
   identity binding to `agent`/`tenant`/`external`.
8. **`D-OJ-conv-email-intake`** — normalise gmail reingest (the
   ~150-job recovery flow surfaced 2026-05-19) into the canonical
   turn shape.
9. **`D-OJ-conv-voice-intake`** — voice notes → turns per the
   `voice_notes_workflow` memory's two paths
   (capture-time-bound and inferred-from-content).
10. **`D-OJ-conv-sms-intake`** — Twilio SMS bridge. Cross-ref
    `CUSTOMER-CONV-LOOP-PLAN.md` W1–W6.
11. **`D-OJ-conv-ai-participant`** — AI agent's draft/approve/send
    state machine, structural SIR enforcement. Builds on shipped
    `agent-cert-provider.ts`.
12. **`D-OJ-conv-outbound-routing`** — operator-approves-draft → ship
    to right surface. Wires the state machine to the surface
    adapters' `send` methods.
13. **`D-OJ-conv-per-turn-compression`** — wire the existing
    compression gradient to run per-turn on the canonical turn shape;
    emit SCG relations via the 10th reducer.
14. **`D-OJ-conv-aggregate-sir`** — conversation-as-higher-order-SIR.
    Deterministic projection over the patch stream; references the
    entity via `BELONGS_TO_ENTITY`.

### Honest scope flag

These are not equal-sized.

- **Mechanical (1-day work each):** D-OJ-conv-entity-anchoring (once
  D-ODDJOBZ-turns-as-sem-objects lands), D-OJ-conv-per-turn-compression
  (mostly wiring existing pieces).
- **Medium (week each):** D-OJ-conv-widget-intake, D-OJ-conv-email-
  intake, D-OJ-conv-sms-intake, D-OJ-conv-outbound-routing.
- **Large (multi-week, design + implementation):** D-OJ-conv-meta-
  inbox-bridge (Meta Graph API, webhook auth, IG/FB shape diff),
  D-OJ-conv-ai-participant (the structural SIR rejection wiring is
  non-trivial), D-OJ-conv-multiparty-identity (enum is easy; the
  identity-handle ↔ entity-merge UI flow is genuinely a design
  conversation), D-OJ-conv-aggregate-sir (determinism over patch
  stream is a substrate-shaped piece of work).
- **Big design conversation, not just implementation:** D-OJ-conv-
  multiparty-identity, D-OJ-conv-aggregate-sir. These need product
  decisions before they're tractable.

---

## 13. Open questions (and resolutions)

Honest list of decisions. **Questions 13.2, 13.3, and 13.5 were
resolved by Todd 2026-05-21 during this PR's review.** Resolutions
are documented under each question; the rest remain genuinely open
and will surface in further design review.

### 13.1 BELONGS_TO_ENTITY constraint enforcement — RESOLVED 2026-05-23

**Resolution: enforced by construction in `buildTurnRelations`; no
benchmark needed.**

`buildTurnRelations` in `conversation-turn-patch.ts` is the single
factory that emits `BELONGS_TO_ENTITY` relations for a turn. It
returns **at most one** — exactly one when the turn carries an
`entityRef`, zero when it doesn't. Because all turn-persist paths
flow through this builder, the "one per turn" invariant holds by
construction. A relation-pass rejection guard or a
`createRelation`-time check would be redundant. The benchmark
(relation-pass overhead) is deferred indefinitely; the source of
truth is the builder, not a reducer that could accumulate duplicates.
See D-OJ-conv-entity-anchoring + inline comment in `buildTurnRelations`.

### 13.2 Identity binding for un-cert'd parties — RESOLVED 2026-05-21

**Resolution: tiered identity with operator-initiated merge gated on
job-history challenges.**

Three identity tiers for un-cert'd parties:
- **L0 browser cookie** — anonymous session marker; first contact via
  the widget creates an L0 participant
- **L1 phone OR email** — upgraded from L0 when the party provides a
  contact; surface adapters (widget, email, Meta Inbox) bind to L1 by
  default
- **L2 Plexus cert** — operators only; tenants/external parties stay
  at L1 indefinitely

When the same human appears with a new phone / cleared cookie / new
email, they enter as a **new participant**. Acceptable cost of not
inventing identity.

**Merging two L0/L1 participants into one:** an operator-initiated
intent `identity.merge_request` emits a `MERGES` SCG relation from
the new identity → the canonical identity. The merge is **gated on a
challenge** the operator picks from the would-be-merged party's job
history (e.g. *"what was the address of the last job we did?"*, *"who
referred you to us?"*, *"what's the colour of the rear door we
painted?"*). Wrong-answer → merge refused.

Downstream queries that list "all conversations with tenant X" chase
`MERGES` chains transitively (`X → Y → Z` returns the union, with the
canonical identity's facets winning on conflict per the operator's
merge confirmation).

Belongs in §5.5 (identity tiers) + §11 (`MERGES` relation kind) + a
new deliverable: `D-OJ-conv-identity-merge` (not yet in canon — add
when the foundation deliverables land).

### 13.3 AI outbound ratification — RESOLVED 2026-05-21

**Resolution: confidence-gated outbound with versioned-prompt audit
trail. NOT a new SIR constraint kind, NOT a two-step intent.**

The compression gradient (NL → Intent → SIR → IR) emits a
**confidence score** alongside the intent. The cartridge declares a
**ratification threshold** in `cartridge.json` (default e.g. 0.85);
intents whose confidence is **at or above** threshold can ship
without operator ratification, intents **below** threshold are
parked in a `proposed` state for operator review.

Every outbound — auto-sent OR ratified — is **logged** with:
- the extracted intent + its confidence score
- the **versioned prompt schema** used to generate the reply
  (prompts are first-class artefacts, content-addressed and schemad
  like cells; bumping a prompt = new version with the old version
  retained for the audit chain)
- the operator's ratify/reject decision when applicable
- the resulting SIR / IR / cell hash chain

Audit utility: when a reply turns out wrong, the operator can trace
back to the specific prompt version + confidence score + reduction
pass that produced it — and decide whether to (a) downgrade the
prompt (revert), (b) tighten the threshold for that cartridge / role
pair, or (c) re-train the extractor against the corrected reply.

This shape sidesteps both options from the original question — no
new SIR kind needed (the confidence is gradient output, not a
constraint), no forced two-step intent (the proposal-vs-send split
is operationally available via the threshold, not structurally
forced).

Belongs in §9 (AI participant) + a new section §9.6 "Confidence,
prompt versioning, audit trail". Three new deliverables to add to
canon when the foundation lands:
- `D-OJ-conv-confidence-threshold` — cartridge.json ratification
  threshold field + reducer-side confidence emission
- `D-OJ-conv-prompt-versioning` — versioned prompt schema + content-
  addressed prompt storage. **LANDED 2026-05-22** (per-cartridge
  extension path: `cartridges/oddjobz/brain/src/conversation/prompt-
  store.ts` — version registry + `resolvePrompt(id, version?)`,
  content-hashed via the shared content-store primitive; old versions
  retained for the audit chain. The reply-audit-log consumes the
  `(promptId, version, contentHash)` pin triple it exposes.)
- `D-OJ-conv-reply-audit-log` — durable audit trail (separate
  sem_objects kind `oddjobz.conversation.reply_audit`)

### 13.4 Re-anchoring semantics

§7.3 says "the operator emits new `BELONGS_TO_ENTITY` relations and
revokes the originals." But: does revoking preserve the relation row
(append-only constraint) or actually delete it? SCG relations live
in `sem_objects.payload` (jsonb) and the substrate is append-only —
"revocation" today is a new `revoked` patch on the relation row.
Decide whether re-anchoring is a patch-revoke + new-relation OR a
`SUPERSEDES` relation between two `BELONGS_TO_ENTITY` rows.

**Resolution: SUPERSEDES pattern (2026-05-23)**

Re-anchoring mints a new `BELONGS_TO_ENTITY` to the new entity and a
`SUPERSEDES` relation (source=newRelation, target=oldRelation). Append-only
— no rows modified. `getActiveAnchor(db, turnId)` finds the live anchor by
filtering out any BELONGS_TO_ENTITY that is a SUPERSEDES target. HTTP
endpoint: `POST /api/v1/conversation/turn/:turnId/re-anchor`.
See D-OJ-conv-re-anchor.

### 13.5 Meta Inbox adapter hosting — RESOLVED 2026-05-21

**Resolution: standard Meta webhooks. Operator's brain registers
directly as the webhook endpoint. No NAT punching, no Plexus relay.**

Meta's Graph API supports standard outbound webhooks; the operator's
brain just needs an internet-reachable endpoint (Caddy reverse
proxy, Cloudflare Tunnel, or static IP — operator's choice of
deployment). This matches the existing operator-sovereign deployment
posture (the brain runs where the operator runs; no centralised
Plexus-hosted service is in the trust path).

**Blocker (operational, not architectural):** Todd's Meta Business
account needs to be unrestricted before any of this is testable
end-to-end. Likely related to Meta ID verification — separate work,
not on this PR's critical path. The adapter design itself can land
and be tested with synthetic webhook payloads in the meantime.

Belongs in §6.3 (Meta Inbox adapter contract) — the adapter is a
standard webhook receiver. No special hosting story to design.

### 13.6 Outbound state machine — durability — RESOLVED 2026-05-22

**Resolution: per-turn JSONB UPDATE on `sem_objects.payload` (Option A);
no delivery callbacks; state machine terminates at `sent`.**

Benchmark result (see `outbound-durability-benchmark.ts`):
- Option A (UPDATE payload JSONB): median 0.309 ms
- Option C (separate delivery-tracker rows): median 0.179 ms
- 1.73× — within the 2× simplicity threshold → Option A selected.

Todd confirmed: no Twilio delivery callbacks. The `sent` state is
terminal for now. The `delivered` / `failed` transitions exist in
`outbound-state-machine.ts` for future use but are not driven by
external callbacks in V1. The per-turn JSONB UPDATE path is
implemented in `conversation-turn-patch.ts` (see `updateOutboundState`).
See D-OJ-conv-outbound-routing.

### 13.7 External participantRole — RESOLVED 2026-05-23

**Resolution: add optional `externalKind?: string` sub-discriminator;
no routing logic depends on it in V1.**

`OddjobzConversationTurnPayload.externalKind` is a free-form string
(e.g. `'utility-provider'`, `'insurer'`, `'council'`, `'real-estate-agent'`)
that is only meaningful when `participantRole === 'external'`. Absent
on all other roles. Nothing in V1 reads it — it is persisted in the
`sem_objects.payload` JSONB for future filtering/routing without
requiring a migration. The oddjobtodd operator instance has no active
use for it today; the field exists so callers who *do* know the
external kind can record it. See `OddjobzConversationTurnPayload`
in `conversation-turn-patch.ts`.

### 13.8 Voice ingest — capture-time-bound vs inferred — RESOLVED 2026-05-22

**Resolution: capture-time-bound first; inferred deferred.**

D-OJ-conv-voice-intake (PR #605, merged) ships the capture-time-bound
path only. The operator taps the voice-note button in a job context;
the entity is the open job; no NLP entity resolution is needed at
intake time. The inferred-from-content path (transcript → entity-
resolver → anchor) is deferred to a future deliverable (no ETA).
See D-OJ-conv-voice-intake.

### 13.9 Historical import — un-anchored turns — RESOLVED 2026-05-22

**Resolution: option (b) — submit with entityRef absent; operator
re-anchors via POST /api/v1/conversation/turn/:id/re-anchor.**

D-OJ-conv-historical-import (PR #607, merged) implements this in
`surface-adapters/import.ts`. When `ctx.resolveEntity` returns null
for a contact handle, the turn is still submitted (§6.3
lead-on-contact); `entityRef` is left absent. The operator sees the
un-anchored turns in Talk and can attach them to the right entity
using the re-anchor endpoint (D-OJ-conv-re-anchor). This matches the
live inbound path (widget + SMS lead-on-contact). Refusing the import
(option c) was rejected as too lossy. Auto-creating leads (option a)
was deferred — the operator knows their entity graph; a fresh ghost
job is more noise than help for historical data.
See D-OJ-conv-historical-import + D-OJ-conv-re-anchor.

### 13.10 REFERENCES_OBJECT — necessary or nice-to-have? — DEFERRED

**Resolution: deferred; marked optional in D-OJ-conv-per-turn-compression.**

D-OJ-conv-per-turn-compression (merged) marks `REFERENCES_OBJECT` as
`// optional, §13.10` in the SCG relation catalog. It is NOT emitted by
the current reduction pass. Turns carry free-text mentions; downstream
extractors can produce `REFERENCES_OBJECT` relations later when the
NL-relation pass runs. The relation kind is registered in
`core/scg-relations/src/types.ts` so future emitters have a stable
anchor, but nothing is wired to produce it today. Revisit if the
"as you said earlier…" conversational reference path (§13.8 content
path) ships.
See D-OJ-conv-per-turn-compression.

---

## 14. Cross-references

- **`docs/design/ODDJOBZ-CONVERSATION-AS-SUBSTRATE-PROJECTION.md`** —
  the implementation log. Owns P3.x phase receipts, decisions
  resolved through 2026-05-18, the build sequence. **This doc is the
  forward-looking companion.**
- **`docs/design/CUSTOMER-CONV-LOOP-PLAN.md`** — TDD loop for the
  Twilio SMS bridge (W0–W8). D-OJ-conv-sms-intake consumes this.
- **`docs/design/ODDJOBZ-CUSTOMER-CONVERSATIONS.md`** — the
  customer-side conversation flow (return-link, ROM/qualify). The
  PROJECTION doc §1 maps it onto `runtime/intent/`.
- **`docs/SCG-IMPLEMENTATION-TRACKING.md`** — SCG substrate
  implementation log (RM-010..082). §3.5 is the 10th reducer pass
  this doc's compression gradient consumes; §3.6 is the cut-over
  deliverable D-OJ-conv-* sits on top of; §14 verifies Oddjobz ↔
  conversation-graph wiring (the verification this doc
  operationalises).
- **`docs/INTENT-PIPELINE.md`** — canonical pipeline. Not restated
  here.
- **`docs/canon/unification-matrix.yml`** — U12 (Conversation Graph
  SCG) is the substrate row this doc's deliverables hang off.
- **`docs/canon/deliverables.yml`** — the 14 D-OJ-conv-* + cross-
  referenced entries land here. See §12.

Project memories load-bearing for this design:

- `semantos_streams_shell_native` — protocol bridges are adapters,
  not cartridges. Drives §6.
- `semantos_canonical_schema_spine` — source ≠ cell ≠ model ≠ UI.
  Drives the canonical turn shape (§4) and the adapter contract (§6).
- `voice_notes_workflow` — two paths for voice. Drives §6.2 + open
  question 13.8.
- `semantos_brain_single_threaded_reactor` — no self-calls from
  intake children. Drives the adapter's `submitTurn` shape (§6.1).
- `semantos_no_ai_in_substrate` — LLM stays at the edge. Drives
  §9.3.
- `semantos_dx_priorities` — snapshot/replay determinism. Drives
  §3.9 (conversation-as-aggregate determinism).
- `brain_auth_model_intent` — BRC-52 cert + capability + Plexus-
  challenge. Drives §5 (AI agent capability scope).
- `no_hardcoded_workarounds` — don't propose hardcoding bypasses.
  Drives §13 (open questions instead of invented decisions).

---

## Appendix A — schema diff vs today

Added kinds in `core/scg-relations/src/types.ts`:

```ts
| 'BELONGS_TO_ENTITY'     // D-OJ-conv-entity-anchoring
| 'REFERENCES_OBJECT'     // D-OJ-conv-per-turn-compression (optional, §13.10)
```

Added object kind in `sem_objects`:

```ts
objectKind: 'oddjobz.conversation.turn'
```

Schema for the turn payload: §4.1.

No schema migration on `sem_objects` (it's jsonb-payload).
`verifyLexiconInjective` still passes (string-identity header).

---

## Appendix B — file paths touched by the deliverables

| Deliverable | Primary files | Tests |
|---|---|---|
| D-ODDJOBZ-turns-as-sem-objects | `cartridges/oddjobz/brain/src/conversation/conversation-turn-patch.ts`, `intake-handler.ts` | conversation-turn-patch tests |
| D-ODDJOBZ-quote-affordance | `cartridges/oddjobz/brain/src/conversation/turn-extractor.ts`, IntakeTurnBody type | new |
| D-SCG-oddjobz-consumer-cutover | `cartridges/oddjobz/brain/src/conversation/conversation-turn-patch.ts` (`buildReplyRelations` + `replyRelationSink`), `core/conversation-graph/src/auto-emit.ts` (`makeReplyRelationEmitter`) | `conversation-turn-patch.test.ts` + `core/conversation-graph/src/__tests__/auto-emit.test.ts` (CUT1–4) |
| D-OJ-conv-sem-objects-sink-activation | brain-side: real `createObject` sem_objects sink + bind `relationSink`/`replyRelationSink` (detached-grandchild OR brain-reactor pre-record) | pending |
| D-OJ-conv-entity-anchoring | `core/scg-relations/src/types.ts`, `lexicon.ts`, `relation-pass.ts` | new lexicon vector |
| D-OJ-conv-multiparty-identity | new `cartridges/oddjobz/brain/src/conversation/participant-role.ts` | new |
| D-OJ-conv-widget-intake | new `cartridges/oddjobz/brain/src/surface-adapters/widget.ts` | new |
| D-OJ-conv-meta-inbox-bridge | new `runtime/surface-adapters/meta-inbox/` | new |
| D-OJ-conv-email-intake | new `runtime/surface-adapters/email/` | new |
| D-OJ-conv-voice-intake | new `runtime/surface-adapters/voice/` (consumes `runtime/intent/src/voice/` D-A7 contract) | new |
| D-OJ-conv-sms-intake | per `CUSTOMER-CONV-LOOP-PLAN.md` | per loop plan |
| D-OJ-conv-ai-participant | new `cartridges/oddjobz/brain/src/conversation/ai-participant-state-machine.ts` | new |
| D-OJ-conv-outbound-routing | new `cartridges/oddjobz/brain/src/conversation/outbound-router.ts` | new |
| D-OJ-conv-per-turn-compression | `runtime/intent/src/reducer/relation-pass.ts` | extends existing |
| D-OJ-conv-aggregate-sir | new `cartridges/oddjobz/brain/src/conversation/aggregate-sir.ts` | new (determinism vector) |

---

## Appendix C — matrix integration decision

The integration is **a new substrate row, U13 — Oddjobz Conversation
Engine**, NOT new adapter rows.

Rationale:

- The Oddjobz conversation engine sits on U12 (SCG) but isn't U12 —
  it's the entity-anchored conversation pipeline + multi-surface
  intake + AI-participant integration. That's a substrate row's
  worth of structure.
- The surface adapters (widget, meta-inbox, email, voice, sms,
  import) are NOT cartridges per `semantos_streams_shell_native`;
  they don't deserve adapter-row slots in the matrix (A1..A11 are
  cartridges and verticals). They are sub-deliverables of U13.
- Voice already has its own adapter row (A8) for the input-modality
  primitive (D-A7 stub). U13 consumes that primitive via the voice
  surface adapter; no new A* row.

U13's axes (see matrix update in this PR):

- A (identity): ✓ — turns carry `actorCertId` (cert-bound) and
  `identityHandle` (un-cert'd parties). AI agent cert shipped.
- B (storage): ✓ — turns are `sem_objects` rows of
  `oddjobz.conversation.turn` per D-ODDJOBZ-turns-as-sem-objects.
- C (transport): ✓ — turns ride the existing intake submission path;
  no new transport surface (per A3 Option-C, PROJECTION doc §3a).
- D-sub (substructural): ✓ — turns are append-only; corrections are
  new turns; ratifications are signed patches.
- D-lex (lexicon): ⚠ — `BELONGS_TO_ENTITY` /
  `REFERENCES_OBJECT` kinds added to `relationLexicon`;
  participantRole enum needs lexicon registration; status ⚠ until
  lexicon-injectivity test extended.
- D-form (formal): n/a — Lean proofs not required at this layer.
- D-cap (capability): ⚠ — AI participant's outbound-send capability
  scope is structurally enforced at SIR lowering (per §9.2 open
  question 13.3); status ⚠ until the SIR constraint kind decision
  lands.
- E (time): ✓ — turn patches carry timestamps; the conversation
  aggregate is deterministic over the patch stream.
- F (recovery): ⚠ — turns recover via the `sem_objects` recovery
  path; conversation-aggregate recovery (D-OJ-conv-aggregate-sir)
  not yet wired.
- G (metering): n/a — metering attaches at Phase-3
  (D-SCG-economic-port / D-SCG-wallet-integration) via
  `PAYS` / `GRANTS_ACCESS` relations on turns.

End of doc.
