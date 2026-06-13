---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/ODDJOBZ-OPERATOR-FIELD-ACTIVATION-TRACKING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.732516+00:00
---

# Oddjobz operator + field-app activation — tracking

> **Status:** design / tracker. The conversation substrate is **built**;
> this doc covers what's needed to make the **operator (`oddjobtodd`)
> and field app (`oddjobz-mobile`) actually use it** end-to-end so a
> tradesman on a job sees the canonical conversation thread, the
> operator works the unified inbox over Talk, and the per-entity
> intent pipeline surfaces open vs ratified items per job/site/customer.
>
> **Audience:** whoever picks up the operator-side rollout. Read
> alongside `ODDJOBZ-CONVERSATION-ARCHITECTURE.md` (§3.4 Talk render,
> §3.9 aggregate), `ODDJOBZ-CONVERSATION-AS-SUBSTRATE-PROJECTION.md`,
> and `docs/canon/deliverables.yml` (search `D-OJ-OP-*`, `D-OJ-FIELD-*`,
> `D-OJ-IP-*` — added with this doc).

---

## 1. Where we are vs. where we need to be

### What's already on main (the substrate is complete)

| Layer | Deliverable | PR |
|---|---|---|
| Turns as cells | `D-ODDJOBZ-turns-as-sem-objects` | #535 |
| Entity anchoring (`BELONGS_TO_ENTITY`) | `D-OJ-conv-entity-anchoring` | #539 |
| Multi-party identity | `D-OJ-conv-multiparty-identity` | #540 |
| Prompt versioning (content-addressed) | `D-OJ-conv-prompt-versioning` | #542 |
| Quoted-turn semantics (`quotedTurnId`) | `D-ODDJOBZ-quote-affordance` | #545 |
| SCG REPLIES_TO cutover | `D-SCG-oddjobz-consumer-cutover` | #547 |
| **Live Postgres sem_objects sink (keystone)** | `D-OJ-conv-sem-objects-sink-activation` | **#555** |
| Reply audit log (prompt-pin + decision + chain) | `D-OJ-conv-reply-audit-log` | #556 |
| Per-turn relation emission (10th reducer pass) | `D-OJ-conv-per-turn-compression` | #560 |
| Deterministic conversation aggregate | `D-OJ-conv-aggregate-sir` | #563 |
| Widget surface adapter + §6.1 contract | `D-OJ-conv-widget-intake` | #564 |
| Legacy-ingest bridge (ConversationTurnEvent → canonical) | `D-OJ-conv-legacy-ingest-bridge` | #566 |
| Email (RFC822) surface adapter | `D-OJ-conv-email-intake` | #569 |
| Meta fan-out sink (legacy-cli) | `D-OJ-conv-meta-inbox-bridge` | #570 |
| `legacy serve` connector | `D-OJ-conv-legacy-serve` | #572 |

So per turn: a canonical `oddjobz.conversation.turn` row lands in
Postgres, `BELONGS_TO_ENTITY` anchors it to the job/site/customer cell,
NL-detected SCG relations (`SUPPORTS`/`DISPUTES`/`CITES`/…) mint as
side-effects, the AI reply is logged with its prompt-version pin +
optional confidence, and `loadConversationAggregate(db, conversationId)`
folds it all into a deterministic per-entity descriptor.

### What's missing — the operator/field surfaces don't read any of it

A `grep` across `apps/` for `oddjobz.conversation.turn`,
`loadConversationAggregate`, `listObjectsByKind`, `BELONGS_TO_ENTITY`
returns **zero matches.** Every consumer of the new substrate today
lives brain-side. Specifically:

- **`apps/oddjobz-mobile/`** (Flutter, `package oddjobz_mobile`,
  ios/android/lib) — D-O5m mobile shell. Today it's a **helm / REPL
  client**: BRC-42 pairing, child cert + brain endpoints in
  flutter_secure_storage, helm UI over `POST /api/v1/repl`. It does
  not read canonical conversation cells, has no per-entity view, no
  sync cursor.
- **`apps/oddjobtodd/`** — Vite + React 19 SPA. Scaffolded
  (`index.html`, `src/`, `vite.config.ts`) but not wired to any
  canonical-cell read surface.
- **`apps/semantos/web/`** — the PWA shell (manifest + icons).
- **Brain HTTP** (`runtime/semantos-brain/src/`) exposes raw cells
  (`cell_raw_http.zig` — D-LC1 `GET /api/v1/cell/<sha256hex>`), prev-state
  walks (D-LC4 `since/`), owner index (D-LC3 `cells_by_owner`),
  anchor-txid index (D-LC5), chat/intake/repl/info verbs — but **no
  endpoint that returns the canonical conversation for an entity**
  (the data is in *external Postgres*, not in the brain's LMDB).

The four gaps below are what the rollout has to fill.

---

## 2. Architectural choice — where does the read-surface live?

`sem_objects.{oddjobz.conversation.turn, oddjobz.conversation.reply_audit}`
+ the SCG relations live in **external Postgres** (the `DATABASE_URL`
the live sinks write to, #555). The brain reactor is Zig single-thread
and does not (today) speak Postgres.

But the surface the operator and field app need is **multi-action,
not read-only**. The same operator session that renders Talk also has
to ratify a below-threshold AI reply, draft + send outbound, trigger
intent re-extraction on a quoted turn, advance the job state machine
— and every one of those writes already goes through the brain's
bearer-gated **`POST /api/v1/repl`** (the existing `agent-cert-provider.ts`
BRC-52 cert + capability stack). The conversation is **brain-native**:
intent extraction runs there, the REPL is there, the cert binding the
field app already carries (`flutter_secure_storage` per `oddjobz-mobile`'s
D-O5m) is the brain's. Putting reads on a separate service makes the
apps speak to **two endpoints with two auth handshakes** when every
write stays brain-side regardless — an artificial seam.

| Option | Where it lives | Pros | Cons |
|---|---|---|---|
| **A. Separate `conversation-api` bun process** | New bun service or `apps/legacy-cli` subcommand reading Postgres directly | Direct `drizzle(postgres())` via cartridge primitives; isolated from reactor | Two endpoints + two auth handshakes (apps already need brain for REPL/verbs); cross-process trust for ratify/outbound; duplicate cert validation |
| **B-naive. Brain Zig → bun spawn per request** | Brain HTTP handler spawns a bun child per read | Single endpoint + cert | Cold-start cost per request; bad for Talk render + streaming — anti-pattern, do NOT do this |
| **B-refined. Brain HTTP + persistent bun reader-worker** (recommended) | New `runtime/semantos-brain/src/conversation_read_http.zig` handlers proxy to a **persistent bun child** the brain spawns at startup, which imports the cartridge + holds the Postgres connection, communicated with over stdio pipes — **same poll-handle pattern `intake_http.zig` already uses today**, just long-lived rather than per-request | One cert, one bearer, one endpoint, REPL co-tenant — read + ratify + outbound + extract all on the same operator session; cartridge primitives reused via the persistent child; no Zig↔Postgres bridge; no reactor I/O blocking; no cold-start cost | Slightly more glue than A: a persistent child + a bidirectional pipe protocol (mitigated: the pattern is already proven in the reactor) |

**Recommendation: Option B-refined.** The single self-call deadlock
rule (`semantos_brain_single_threaded_reactor`) prohibits the
*upstream* direction (intake child sync-calling back into brain
HTTP/REPL); the *downstream* direction the brain reading from a
child it spawned over pipes is already proven safe and ships today
in `intake_http.zig`. B-refined puts every read on the same brain
endpoint the apps already hit for the REPL, with the same BRC-52
cert + capability stack — keeping the conversation surface
coherent.

The deliverables below are written against **Option B-refined**
(brain HTTP + persistent bun reader-worker proxied via pipes).

---

## 3. The four sections + their deliverables

### 3.1 Brain read-surface — `D-OJ-OP-read-*`

Brain HTTP endpoints under `/api/v1/conversation/*` (bearer-gated by
the existing BRC-52 cert + capability stack), implemented as
`runtime/semantos-brain/src/conversation_read_http.zig` handlers that
proxy to a **persistent bun reader-worker child** (managed by the
reactor, communicated with over stdio pipes — same poll-handle pattern
as `intake_http.zig`, just long-lived).

- **`D-OJ-OP-reader-worker`** — Spawn + supervise a persistent bun
  child at brain startup: it imports `@semantos/oddjobz` (cartridge),
  opens the Postgres handle via `getDatabaseOrNull()` (#555), and
  exposes a tiny request/response protocol over stdin/stdout
  (line-delimited JSON or framed binary — pick one and document).
  Zig side: register the child's fds with the reactor's poll() loop;
  proxy a request when an HTTP handler asks for one; handle child
  death + restart. **Foundation for the next four — pick the proto
  shape here.** **Ungated** (the cartridge primitives + Postgres
  handle are all on main).
- **`D-OJ-OP-read-turns-by-entity`** — `GET /api/v1/conversation/entity/<cellHash>/turns?since=<cursor>&surface=<surface?>` —
  returns canonical `OddjobzConversationTurnPayload[]` for an entity
  (filtered by `BELONGS_TO_ENTITY`, ordered by `(timestamp, turnId)`,
  with the cursor for incremental sync). Reader-worker calls
  `listObjectsByKind(db, 'oddjobz.conversation.turn')` (#563) +
  filters by the relation; Zig handler proxies. Deps:
  `D-OJ-OP-reader-worker`. **Ungated.**
- **`D-OJ-OP-read-aggregate`** — `GET /api/v1/conversation/entity/<cellHash>/aggregate` —
  returns `ConversationAggregate` (the deterministic fold from #563:
  participants, open intents, state-machine snapshot). Reader-worker
  calls `loadConversationAggregate(db, conversationId)`. Deps:
  `D-OJ-OP-reader-worker`. **Ungated.**
- **`D-OJ-OP-read-turn-by-id`** — `GET /api/v1/conversation/turn/<turnId>`
  (+ optional `?include=audit`) — single turn + the linked
  `oddjobz.conversation.reply_audit` row (#556 — prompt-version pin
  + decision + chain). Used by the audit-display flow. Deps:
  `D-OJ-OP-reader-worker`. **Ungated.**
- **`D-OJ-OP-read-stream`** — SSE on
  `GET /api/v1/conversation/entity/<cellHash>/stream` (cursor-based
  resumption). Zig handler holds the response open + proxies a
  long-running pipe channel from the reader-worker, which polls (or
  ideally `LISTEN/NOTIFY`s) Postgres for new rows + emits. Deps:
  `D-OJ-OP-read-turns-by-entity`. **Ungated.**

All five share the persistent reader-worker. Simplest first slice =
reader-worker + the two by-entity endpoints + by-id; the stream is
a follow-up.

**REPL co-tenancy.** Because reads live on the brain, the existing
REPL surface naturally handles the *writes* alongside them: ratify
a reply audit, dispatch an outbound verb, trigger intent
re-extraction. The operator's bearer covers both directions — no
cross-process trust, no second auth handshake.

### 3.2 Operator UI (`oddjobtodd`) — `D-OJ-OP-todd-*`

Consume the read-surface in the React SPA. Per architecture §3.4:
"Talk renders the unified thread" — one stream per entity, with
`REPLIES_TO` nesting, participant colouring, surface metadata.

- **`D-OJ-OP-todd-talk`** — Talk render for an entity: header (the
  job/site/customer cell), unified turn stream from
  `D-OJ-OP-read-turns-by-entity`, `REPLIES_TO` nesting from the
  SCG relations, per-turn surface + participant chips. Deps:
  `D-OJ-OP-read-turns-by-entity`, `D-OJ-OP-read-stream`. **Ungated.**
- **`D-OJ-OP-todd-aggregate-panel`** — sidebar that surfaces the
  conversation aggregate (#563): participants set, open intents,
  ratified, state-machine snapshot (`lastActionType`, `closed`,
  `needsSiteVisit`, etc.). Deps: `D-OJ-OP-read-aggregate`.
  **Ungated.**
- **`D-OJ-OP-todd-audit-drawer`** — click any AI-generated turn →
  reveal the `oddjobz.conversation.reply_audit` row: prompt id +
  version + content hash + the operator decision (if ratified) +
  cell chain. Deps: `D-OJ-OP-read-turn-by-id`. **Ungated.**
- **`D-OJ-OP-todd-ratification-queue`** — the queue of below-threshold
  AI replies that need operator ratify/reject. Surfaces
  `replyConfidence` (already an optional field on the reply audit per
  #556) once it's populated. **Gated on `D-OJ-conv-ai-participant`
  + `D-OJ-conv-confidence-threshold`** (both Todd-blocked).
- **`D-OJ-OP-todd-auth`** — operator BRC-52 cert binding for the SPA
  (the same cert model `agent-cert-provider.ts` uses for the AI
  child cert). **Partly gated on `D-OJ-conv-ai-participant`** (the
  cert model itself); the bearer/cookie wiring is the SPA's own
  scaffolding and can ship first.

### 3.3 Field app (`oddjobz-mobile`) — `D-OJ-FIELD-*`

The tradesman on a job opens the field app and sees the canonical
conversation thread for that site/job offline-first, syncing the
delta when back online. The deterministic aggregate (#563) is the
load-bearing primitive — same patch sequence → same projection — so
offline replay is safe.

- **`D-OJ-FIELD-canonical-client`** — replace today's helm/REPL focus
  with a per-entity canonical-cell client: hit
  `D-OJ-OP-read-turns-by-entity` + `D-OJ-OP-read-aggregate`, render in
  the existing Flutter UI. Reuses the BRC-42 cert already in
  `flutter_secure_storage`. Deps: `D-OJ-OP-read-turns-by-entity`,
  `D-OJ-OP-read-aggregate`. **Ungated** (existing cert is sufficient
  for L2 operator access; tradesman-specific cert is a separate
  identity question — below).
- **`D-OJ-FIELD-offline-replay`** — local persistence of the turn
  patch stream + the projected aggregate; on reconnect, pull from
  `since=<cursor>` and re-project. The aggregate's determinism (#563
  vector test) is the correctness guarantee. Deps:
  `D-OJ-FIELD-canonical-client`, `D-OJ-OP-read-stream` (for the live
  delta). **Ungated.**
- **`D-OJ-FIELD-tradesman-identity`** — distinct `participantRole` +
  identity binding for an on-site tradesman vs the operator. Today
  the cert model assumes operator. The architecture doc §5.6 covers
  "external"; tradesman is a sibling role. **Gated on
  `D-OJ-conv-ai-participant`** (which canonicalises the broader
  cert-binding rules per role).
- **`D-OJ-FIELD-outbound-from-field`** — letting a tradesman post a
  turn from the field (e.g. status update, attachment, voice note).
  Hits the §6.1 surface-adapter / submit path. **Gated on
  `D-OJ-conv-outbound-routing` defaults** + `D-OJ-FIELD-tradesman-identity`.

### 3.4 Per-entity intent pipeline activation — `D-OJ-IP-*`

The compression gradient (NL → Intent → SIR → IR → cells) and the
10th reducer pass (SCG relation emission) already run per turn in
production via #560 / `runtime/intent/`. What's missing is **surfacing
their output per entity in the operator UI** and acting on it.

- **`D-OJ-IP-open-intents-view`** — the aggregate's `openIntents` list
  (from #563) rendered in `oddjobtodd` per entity, grouped by intent
  kind, with the source turn linked. Read-only first. Deps:
  `D-OJ-OP-todd-aggregate-panel`. **Ungated.**
- **`D-OJ-IP-decision-tree-trace`** — for any AI-replied turn, show
  the reduction trace: the assembled prompt (already on the canonical
  turn payload), the reducer-pass outputs (per #560), the SIR
  constraints, the resulting cell chain (already in the reply-audit
  payload from #556). Deps: `D-OJ-OP-todd-audit-drawer`. **Ungated**
  (data already collected; this just renders it).
- **`D-OJ-IP-ratify-action`** — operator action that flips a
  below-threshold proposal to ratified, persisting the decision back
  to the reply audit. **Gated on `D-OJ-conv-confidence-threshold`**.

---

## 4. Dependency graph (Mermaid-ish)

```
                                  [substrate: merged]
                                          │
                          D-OJ-OP-reader-worker          (persistent bun child + pipe proto; Q-5 lean: line-delimited JSON)
                            ┌─────────────┼─────────────┐
                            │             │             │
        D-OJ-OP-read-turns  │   D-OJ-OP-read-aggregate   │  D-OJ-OP-read-turn-by-id
                            │             │             │
                            └────┬────────┼──────┬──────┘
                                 │        │      │
                  D-OJ-OP-read-stream     │      │
                                 │        │      │
        ┌────────────────────────┤        │      └──────────┐
        │                        │        │                 │
   D-OJ-OP-todd-talk       D-OJ-OP-todd-aggregate-panel  D-OJ-OP-todd-audit-drawer
                                 │                                │
                          D-OJ-IP-open-intents-view        D-OJ-IP-decision-tree-trace
                                 │
                          D-OJ-OP-todd-ratification-queue   ── gated on ai-participant + confidence-threshold
                          D-OJ-IP-ratify-action             ── gated on confidence-threshold

        D-OJ-FIELD-canonical-client  ──┐
        D-OJ-FIELD-offline-replay     ─┴── consume the read-surface
        D-OJ-FIELD-tradesman-identity     ── gated on ai-participant
        D-OJ-FIELD-outbound-from-field    ── gated on outbound-routing + tradesman-identity
```

---

## 5. Ungated vs Todd-gated — what can ship without further input

**Ungated** (Q-1/Q-2 resolved per §6; only Q-5 reader-worker proto
remains, and Q-3 cursor wire-encoding is a small confirm — neither
blocks scoping):

- `D-OJ-OP-reader-worker` *(Q-5: confirm line-delimited JSON; Q-3:
  confirm `(timestamp,turnId)` cursor encoding)*
- `D-OJ-OP-read-turns-by-entity`
- `D-OJ-OP-read-aggregate`
- `D-OJ-OP-read-turn-by-id`
- `D-OJ-OP-read-stream`
- `D-OJ-OP-todd-talk`
- `D-OJ-OP-todd-aggregate-panel`
- `D-OJ-OP-todd-audit-drawer`
- `D-OJ-FIELD-canonical-client`
- `D-OJ-FIELD-offline-replay`
- `D-OJ-IP-open-intents-view`
- `D-OJ-IP-decision-tree-trace`

**Gated on existing parked items**:

- `D-OJ-OP-todd-ratification-queue` — needs `D-OJ-conv-ai-participant`
  + `D-OJ-conv-confidence-threshold`.
- `D-OJ-OP-todd-auth` — partly gated on `D-OJ-conv-ai-participant`
  (the cert model); the SPA scaffolding (bearer/cookie wiring) can
  ship first.
- `D-OJ-FIELD-tradesman-identity` — needs `D-OJ-conv-ai-participant`
  (broader cert rules per role).
- `D-OJ-FIELD-outbound-from-field` — needs
  `D-OJ-conv-outbound-routing` + tradesman-identity.
- `D-OJ-IP-ratify-action` — needs `D-OJ-conv-confidence-threshold`.

---

## 6. Open questions for Todd

- **Q-1 — read-surface host (§2). RESOLVED 2026-05-23.** Recommendation
  flipped to **Option B-refined**: brain HTTP `/api/v1/conversation/*`
  proxied to a persistent bun reader-worker child (same poll-handle
  pattern as `intake_http.zig`). One cert, one bearer, one endpoint —
  REPL co-tenant for ratify/outbound/extract actions. The single
  self-call rule only forbids the upstream direction (intake child →
  brain HTTP); `brain → reader-worker child → Postgres` is the
  downstream direction the reactor already ships.
- **Q-2 — path prefix + auth. RESOLVED.** Path: `/api/v1/conversation/*`
  (siblings of the existing `/api/v1/cell/*`, `/api/v1/repl`).
  Auth: the existing BRC-52 cert + capability stack the brain
  already runs (`agent-cert-provider.ts` model); same bearer the
  field app carries in `flutter_secure_storage` today.
- **Q-3 — pagination shape.** Cursor-by-`(timestamp,turnId)` (the
  canonical sort key from #563). Confirm + pick the wire encoding
  (base64-packed `(u64 ms, ULID)` is the obvious default).
- **Q-4 — field-app outbound (§3.3, `D-OJ-FIELD-outbound-from-field`).**
  Is a tradesman's outbound turn an *operator-cert delegated*
  submission, or a tradesman's own L2 cert? Related: where this lands
  vs Plexus identity layer.
- **Q-5 — reader-worker proto.** Line-delimited JSON over stdin/stdout
  (simple, debuggable) vs a small framed binary protocol (tighter,
  faster). Lean: **line-delimited JSON** to start — the surface is
  small, requests are infrequent at operator-UI scale, and matching
  the cartridge's existing JSON shapes minimises serialisation glue.
  Confirm before `D-OJ-OP-reader-worker` is spawned.

---

## 7. Sequencing (proposed)

Q-1 (Option B-refined) and Q-2 (path + auth) resolved 2026-05-23.
Q-3 (cursor encoding) and Q-5 (reader-worker proto) confirm in the
same pass as the first PR.

1. **Read-surface foundation** — `D-OJ-OP-reader-worker` (persistent
   bun child + pipe proto + Zig poll integration) → first proxied
   endpoint as the smoke test. Then `D-OJ-OP-read-turns-by-entity` +
   `D-OJ-OP-read-aggregate` + `D-OJ-OP-read-turn-by-id` (one PR or
   three small ones; same worker, same pipe channel).
2. **`oddjobtodd` Talk** — `D-OJ-OP-todd-talk` +
   `D-OJ-OP-todd-aggregate-panel` + `D-OJ-OP-todd-audit-drawer`
   (one PR each; SPA wiring).
3. **Stream** — `D-OJ-OP-read-stream` enables near-real-time updates
   in oddjobtodd + field app.
4. **Field app canonical client** — `D-OJ-FIELD-canonical-client`
   then `D-OJ-FIELD-offline-replay`.
5. **Intent surface** — `D-OJ-IP-open-intents-view` +
   `D-OJ-IP-decision-tree-trace`.
6. **Ratification + outbound + tradesman identity** — *waits on the
   parked ai-participant + outbound-routing + confidence-threshold
   work*.

Each step is bounded, additive, and shippable behind a feature flag
in the apps.

---

## 8. Acceptance criteria (end-to-end)

The activation is "done" when:

- The operator opens `oddjobtodd` against a known job cell, sees the
  full unified conversation thread for that job (every turn from
  widget/meta/email — all canonical, all from Postgres), the
  aggregate's open intents in the sidebar, and the audit drawer for
  any AI reply.
- A tradesman opens `oddjobz-mobile` for that same job (offline-first),
  sees the same thread + aggregate projected locally, then on
  reconnect pulls only the delta via the cursor.
- A new inbound Meta DM (once Todd's account is unblocked + the
  Meta pipeline is live) appears in both surfaces within seconds via
  `D-OJ-OP-read-stream`.
- The reply audit drawer shows the exact prompt version + decision +
  cell chain that produced a given AI reply — closing the
  "auditable bot, not opaque context window" loop the architecture
  doc set out.
