---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/BRAIN-GENERIC-MINT-VERB.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.734464+00:00
---

# Brain Generic Mint Verb

**Status:** Design record — pre-implementation
**Date:** 2026-05-26
**Authors:** Todd Price, drafted by Claude
**Related:** `docs/design/STRUCTURED-TYPEHASH-CANONICAL.md` (the substrate this builds on); `docs/STRUCTURED-TYPEHASH-TRACKER.md` (where T7.b's stub SelfFlowMinter is documented); `runtime/semantos-brain/src/repl.zig` (current dispatch); `runtime/semantos-brain/src/events_stream_handler.zig` (the fan-out target)

---

## 1. Context

After PR #666 lands, the substrate has end-to-end identity infrastructure: cartridges declare `cellTypes[]` in their manifests, kernel `buildTypeHash` produces the structured `|8|8|8|8|` hash at load time, TS + Zig validators agree, the Flutter shell renders practice flows for the `self` cartridge, and the AttentionEngine knows how to score `self.*` signals.

**What's missing:** a path from "user completes a flow in the PWA" → "cell is persisted on the brain."

Today the brain only has cartridge-specific mint paths:
- `ratify lead <id>` (oddjobz `RatificationQueueClient`)
- attachment upload via `attachments_upload_http.zig`
- voice-extract via `voice_extract_http.zig`
- jobs / customers via per-resource handlers under `runtime/semantos-brain/src/resources/`

Each new cellType needs its own brain Zig handler, REPL verb, capability mint, and Dart shim. This is the **fourth pipeline** of the wrong abstraction problem we fixed in the typehash migration — typeHash registry was unified by D11 (one `cellTypes[]` per cartridge), but the *minting* path is still per-cartridge bespoke.

The Flutter `SelfFlowMinter` in `apps/oddjobz-mobile/lib/src/helm/home_screen.dart` is a `debugPrint` stub because no generic mint endpoint exists. Without this verb, the entire self cartridge is decorative — flows render, "Sealed." banners fire, but no cells persist.

---

## 2. Decision

**One generic mint primitive** that works for any cartridge's cellType, gated by the cartridge's declared capability, validated against the cellType's declared payloadSchema, persisted to the brain's cell store, and fan-out via the NATS event spine.

```
Client (PWA / CLI / federated peer)
   │
   ▼
  POST /api/v1/cells
  Body: { typeHashHex, payload, capabilityProof }
   │
   ▼
─────────────────────────────────────────────────────────────
  brain mint handler (new — runtime/semantos-brain/src/cells_mint_http.zig)
─────────────────────────────────────────────────────────────
  1. Authenticate (existing bearer + capability check)
  2. Look up typeHash in cartridge registry — reject if unknown
  3. Validate payload against cellType.payloadSchema
  4. Wrap in 256-byte cell header (linearity + ownerId + timestamp +
     content-hash + the typeHash bytes at offset 30)
  5. Persist to LMDB cell store under namespace-prefixed key
  6. Publish to NATS subject `cells.<cartridge-id>.minted`
  7. Return { cellId, persistedAt } as 201 Created
─────────────────────────────────────────────────────────────
   │
   ▼
  Fan-out (existing infrastructure):
   - /api/v1/events WSS → PWA live updates
   - AttentionEngine → re-score, surface in helm
   - Future federation gossip → paired devices sync
```

The handler is **cartridge-agnostic** — it looks up the typeHash in the manifest-driven registry (built by T2.a) and delegates everything that varies per cartridge (capability, payloadSchema, linearity) to the registered metadata.

---

## 3. Open questions

Five real design decisions before code. Each has options and a recommended default; lock them with Todd before any Zig.

### Q-mint-1 — Transport: REPL verb or dedicated HTTP endpoint?

| Option | Shape | Pros | Cons |
|---|---|---|---|
| A | REPL verb `mint <typeHashHex> <jsonPayload>` via `/api/v1/repl` | Reuses existing bearer-gated reactor path; matches `ratify lead <id>` shape | JSON-in-REPL-line awkward (escaping); REPL line buffer caps payload size |
| **B (recommended)** | Dedicated `POST /api/v1/cells` endpoint | Proper content-type handling; payload size scales; REST-natural; matches `attachments_upload_http.zig` pattern | New endpoint to maintain |
| C | Both: B as primary, A as a thin REPL wrapper that calls B's handler for CLI use | Substrate via B; CLI convenience via A | Two surfaces to keep aligned |

**Recommendation: C** — endpoint is the substrate, REPL wrapper preserves operator CLI ergonomics. Handler lives once at `runtime/semantos-brain/src/cells_mint_http.zig`; `repl.zig` adds a `mint` verb that synthesises an HTTP request to the same handler in-process.

---

### Q-mint-2 — Validation: how does Zig validate TS-defined payload schemas?

Brain is Zig. The validators we shipped in T7.a (`releaseCellType.validate(...)`) are TS code in `@semantos/self`. Four options:

| Option | Approach | Per-mint cost | Risk |
|---|---|---|---|
| A | No payload validation in brain — accept everything | 0 | Garbage cells persist |
| B | Out-of-process bun validator subprocess (mirrors `voice_extract_http.zig` shell-out pattern) | ~30-50 ms cold start, ~5 ms warm with a pool | Bun must be installed alongside brain on production hosts |
| **C (recommended for v0.1.0)** | Structural-only check in Zig — required fields present, enum values in allowed set, types match | <0.1 ms | Doesn't catch semantic errors (negative quantities, malformed dates) |
| D | Code-gen Zig validators from `cartridge.json` `payloadSchema` at build time | <0.1 ms | Build complexity; needs canonical payloadSchema spec |

**Recommendation: C for v0.1.0, D for v1.0.**

C is ~150 LOC of Zig: iterate the cell-type's declared schema, walk the payload JSON, assert each required field is present + type-matched + enum-constrained. Catches ~80% of bad mints; sufficient for self-cartridge personal-practice cells where the source-of-truth is a single user.

D is the right long-term answer. Defer until either (a) the payloadSchema format is properly canonicalised (today's `{type: 'string', tier: 'core'}` shape is informal) OR (b) a multi-tenant cartridge demands the rigour.

A is rejected — too much trust delegated to clients.
B is rejected for v0.1.0 — operational complexity (bun-on-server) outweighs the benefit while there's only one cartridge minting.

---

### Q-mint-3 — Capability check: what gates a mint?

Per the `brain_auth_model_intent` memory, Todd's intended model is BRC-52 cert + capability + Plexus-challenge satisfaction. Current implementation is simple bearer. Generic mint forces a decision on how much of the real model to enforce.

| Option | Granularity | What the brain checks |
|---|---|---|
| A | Per-cellType | Each `cellTypes[].mintCapability` declares required cap; brain verifies cert holds it |
| **B (recommended for v0.1.0)** | Per-cartridge | One capability per cartridge (we already declared `SELF_INQUIRY` for self); cert must hold the cartridge's capability set to mint any of its cellTypes |
| C | Per-instance with Plexus-challenge | Full T7 model — cert + capability + challenge satisfaction proven per mint |

**Recommendation: B for v0.1.0.** Simplest, matches what we already wrote in `cartridges/self/cartridge.json` `capabilities[]` (single `SELF_INQUIRY` entry). Move to A if any cartridge ever needs differentiated mint permissions (e.g. read-only viewer cert can mint annotations but not core records). C is the right ceiling but lives behind the parked Phase-1b BCA/cert identity work; revisit when that lands.

**Wildcard exception:** the reserved `0x00 × 8` namespace prefix (per decision record §2.2 / Q5) requires a special `MINT_WILDCARD` capability that only substrate cartridges' operator-issued certs hold. Domain cartridges that want promiscuous fan-out need explicit operator opt-in.

---

### Q-mint-4 — Cell store: where do self.* cells persist?

Brain currently uses LMDB for the existing per-cartridge resource tables (jobs, customers, leads — see `cartridge_boot.zig`). For generic mint:

| Option | Layout | Pros | Cons |
|---|---|---|---|
| A | Single shared cell store — one LMDB env, one `cellsByHash` table for all cartridges | Simplest schema | No per-cartridge isolation; one cartridge's growth bloats everyone's read amplification |
| B | Per-cartridge LMDB env, brain dispatches by cartridge-id | Strong isolation | Many env handles to manage; per-cartridge boot overhead |
| **C (recommended)** | Single LMDB env, namespace-prefixed table keys (`<typeHash[0:8]>:<cellId>` → cell bytes) plus `<cellId>` → typeHash index for lookups | One env; prefix scan exploits the structured-typeHash routing property for "all cells in oddjobz.*" queries; single backup path | Slightly more complex key schema |

**Recommendation: C.** The structured `|8|8|8|8|` typeHash was designed for this — bytes 0:8 ARE the namespace, so an LMDB cursor seek to `c4cf2fd44009863e:` returns all oddjobz cells. No separate index needed.

**Octave note:** cells <1KB go to LMDB hot path. Per memory `octave_escalation_unification`, larger cells escalate to filesystem (octave 1) and S3 (octave 2). Self cells are all <1KB (practice payloads are short text + a few numbers) — LMDB only for v0.1.0. The mint handler trusts the octave layer to handle escalation transparently when payloads ever exceed 1KB.

---

### Q-mint-5 — Fan-out: what fires after persist?

Per the `brain_reactor_v1_recovery_complete` memory, the NATS-canonical event spine landed in 2026-05-13. So fan-out is "publish once, subscribers fan out from there."

| Option | Approach |
|---|---|
| A | Direct calls — handler invokes each subscriber inline | Tight coupling; new subscribers require handler edit |
| **B (recommended)** | Single NATS publish to `cells.<cartridge-id>.minted` with `{typeHash, cellId, persistedAt}` payload — let downstream subscribers (events WSS, AttentionEngine, future federation, ratification queue if relevant) fan out from there | Existing pattern; new subscribers wire to NATS, not the handler |

**Recommendation: B.** Single NATS publish at the end of the mint handler. Downstream:
- `/api/v1/events` WSS handler already forwards NATS → operator subscribers
- `AttentionEngine` extends to subscribe to `cells.*.minted` and re-score on the minted typeHash
- Federation gossip (Phase U.2+) subscribes to the same subjects with namespace-prefix filtering
- Per-cartridge custom hooks (e.g. self-cartridge wants to fire an `evening-review.deadline` re-check after a `morning-intention` mint) can subscribe selectively

**Per-cartridge hook declarations:** cartridge.json could declare `onMint: ['<hook-name>']` per cellType for cartridge-specific reactions. Defer this; v0.1.0 publishes to NATS and lets generic subscribers handle it. Add `onMint` if a cartridge needs synchronous post-mint logic.

---

## 4. Proposed migration plan

Four steps, each its own PR; total estimate 3-5 days focused.

### M1 — Handler skeleton + happy path (1-2 days)

- New: `runtime/semantos-brain/src/cells_mint_http.zig` — handler that wires Q-mint-1 (the HTTP endpoint), Q-mint-3-B (per-cartridge capability check), Q-mint-4-C (namespace-prefixed LMDB key), Q-mint-5-B (NATS publish)
- Add cartridge-registry lookup helper — given a typeHash hex, return `{cartridgeId, cellType, capability, linearity, payloadSchema}` (mirror of the TS `cartridgeRegistry.cellTypeByHash` we shipped in T2.c, ported to Zig)
- Skip Q-mint-2 validation in M1 — accept any well-formed JSON; structural-check lands in M2
- Wire as `POST /api/v1/cells` in `site_server/reactor.zig` dispatch
- Tests: known-good payload → 201 + cellId; unknown typeHash → 404; bearer missing → 401

### M2 — Structural payload validation in Zig (0.5-1 day)

- Read `payloadSchema` from the cartridge's loaded manifest at brain boot
- Walk the inbound payload JSON, assert each required field present + type matched + enum constrained
- 400 with field-level error on validation failure
- Tests: missing required field → 400; bad enum → 400; happy path → 201

### M3 — REPL `mint` verb wrapper (0.5 day)

- `repl.zig`: add `mint <typeHashHex> <jsonPayloadEscaped>` to dispatch
- Synthesise an HTTP request to the M1 handler in-process (mirror oddjobz REPL verb pattern)
- Tests: REPL `mint` succeeds with same result as HTTP POST

### M4 — Dart shim + wire into Flutter (0.5 day)

- New: `apps/oddjobz-mobile/lib/src/self/self_flow_minter.dart` — concrete `SelfFlowMinter` that POSTs to `/api/v1/cells` with bearer auth, returns cellId or throws typed error (mirrors `RatificationQueueClient` shape)
- Update `apps/oddjobz-mobile/lib/src/helm/home_screen.dart`: replace the `debugPrint` stub with the real minter
- Tests: synthetic mint POST returns cellId, SnackBar shows success; bad cap returns 403, SnackBar shows error

---

## 5. What this unblocks

- **Self cartridge end-to-end**: Flutter flow → real persisted `self.practice.*` cell → shows in AttentionEngine attention feed → AttentionSignals fire (T7.c) → next-day morning-intention overdue surfaces correctly
- **Future cartridge mints**: any cartridge that ships a `cellTypes[]` manifest entry can mint without writing a single Zig handler — the generic verb covers it
- **Federation foundation**: cells minted via this path immediately publish to NATS; when federation gossip ships (Phase U.2+), it subscribes to the same subject with namespace-prefix filter and propagates to paired devices automatically
- **Ratification queue generalisation**: if a cellType's linearity is AFFINE or LINEAR and the cartridge declares `ratificationRequired: true`, the NATS fan-out can push to the ratification queue without per-cartridge wiring (deferred follow-up — most v0.1.0 self cells are LINEAR consumed-locally, don't need ratification)
- **Wallet-side cell minting**: the wallet-headers cartridge currently mints anchors via bespoke code; could migrate to the generic verb once BSV anchor metadata fits the cellType shape

---

## 6. What does NOT change

- Existing per-cartridge resource verbs (`ratify lead`, `find jobs`, etc.) stay — this is **additive**, not a deprecation. Migration of legacy verbs to use the generic path is a separate, later concern.
- Cell header wire format — still 256-byte header at offset 0, typeHash at offset 30. No change.
- Cartridge.json schema — already has everything the handler needs (cellTypes[], capabilities[], triple, linearity, payloadSchema). No new fields required for v0.1.0.
- The cell store's octave-tiering behaviour — mint just writes to LMDB hot path; existing octave layer escalates to filesystem/S3 on size.
- The bearer auth path — same `Authorization: Bearer <token>` pre-flight as every other `/api/v1/*` endpoint. The capability check is layered ON TOP, not a replacement.

---

## 7. Open items deferred to implementation

| # | Item | Resolve by |
|---|---|---|
| OI-1 | Exact JSON shape of the capability proof in the POST body — for v0.1.0 the bearer token + cartridge-capability lookup is enough, but the eventual cert+capability+challenge proof needs a structured field | M1 design |
| OI-2 | Idempotency — should mint accept an `idempotencyKey` so the client can retry a flaky POST without double-minting? | M1 |
| OI-3 | Code-gen Zig validators (Q-mint-2 option D) — when payloadSchema is canonicalised, set up the build step that emits Zig | Post-v1.0 |
| OI-4 | Per-cartridge `onMint` hook declarations in cartridge.json — if a cartridge needs synchronous post-mint logic that NATS-async doesn't satisfy | When first cartridge needs it |
| OI-5 | Cross-cartridge `cells.*.minted` aggregation — should AttentionEngine subscribe to one wildcard subject or per-cartridge? | M2 wiring |

---

## 8. Out of scope

- Cell deletion / revocation — separate verb shape (`revoke <cellId>` or soft-revoke pattern per memory `soft_revoke_folded_patches`)
- Cell update — substrate is content-addressed; updates are new mints with `prevStateHash` chaining, not in-place edits
- Multi-cell atomic transactions — single-cell mints only for v0.1.0; if a flow needs to mint N cells atomically, that's a future `mintBatch` verb
- BSV on-chain anchoring — orthogonal; `anchorProtocolHash` machinery (per T5.c) handles this and stays unchanged
- Federation gossip protocol — handler publishes to NATS; gossip subscribes; the gossip protocol itself is Phase U.2+ work
- The Phase-1b BCA/cert identity work (parked per memory `semantos_parked_identity_phase1b`) — when it lands, generic mint upgrades from per-cartridge capability (Q-mint-3-B) to per-instance cert+challenge (Q-mint-3-C) with no shape change to the handler interface
