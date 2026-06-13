---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.657588+00:00
---

# D-DOG.1.0c — Layer 1 Promotion + Cell-DAG Graph Materialisation

**Status**: ✅ **SHIPPED** 2026-05-06. 20 PRs across 5 phases (#367–#391). See `docs/prd/SESSION-HANDOFF-2026-05-06.md` §3 for the full per-phase PR map.
**Why**: Tier 1.7 (PR #366) made proposals rich. Today's ratify path collapses that richness into a flat JSONL view-store row. D-DOG.1.0c materialises the proposal as a proper cell-DAG graph (site + customer + job + attachment cells, signed and linked) so the helm/mobile views can finally render "all jobs at 13 Orealla Cr" / "all jobs for Jo-Anne Bisman" / "this job's source PDF + photos" — the type path that answers who/what/why/how/where/when through edges between cells, not fields on one row.

## §0 — Shipped phases (post-mortem checklist)

| Phase | PR(s) | Merge SHA(s) | Notes |
|---|---|---|---|
| Matrix doc | #368 | `194adb7` | This document. |
| 1 — Schemas | #367 | `6c6d7ee` | v2 cell types (job/customer/site/attachment) + type-hash registry. v1 backward-compat preserved. |
| 2A.1 — sites_store_fs | #369 | `276b077` | New view-store for site.v2 cells. |
| 2A.3 — jobs_store_fs v2 read path | #370 | `ab1e981` | Single struct + version discriminator (not tagged-union). |
| 2A.2 — customers + attachments v2 | #371 | `f2f539d` | Found + fixed pre-existing customers-store dangling-slice bug. |
| 2A.4 — handler graph-walk rewrite | #372 | `2dff1d3` | Centerpiece: SIRProgram → graph translator. UnsigneD cells written; sign retrofit in Phase 4. |
| 2B.1 — TS RPC + payload_hint | #373 | `8ff6b53` | Mixed snake/camel wire format casing tracked as follow-up. |
| 2B.2 — TS FS fallback graph rewrite | #374 | `6b5eae8` | TS-side dedupe simpler than Zig (exact match only). |
| 2B.3 — Cross-store query handler | #375 | `4f0d43c` | 9 new RPC verbs powering Phase 3 UI. |
| 2B.4 — TS↔Zig parity oracles | #376 | `ad614e4` | 35 fixtures, zero divergences. |
| 3 E.1 — helm JobList graph-aware | #377 | `0484ad5` | N+1 prevention via list_sites + list_customers bulk fetch. |
| 3 F.1 — mobile JobList graph-aware | #378 | `bc5b0a1` | Wired all 8 oddjobz.* verbs upfront — Wave 2 needed no client work. |
| 3 E.3 — helm customer-pivot | #379 | `bf5930f` | Confirmed loom-svelte is plain Vite (not SvelteKit) — no file-router. |
| 3 E.2 — helm site-pivot + hash router | #380 | `ab06b2b` | Built the hash router that E.3/E.4 piggyback on. |
| 3 F.2 — mobile site-pivot | #386 | `7f55bda` | Salvaged from credit-cap-stopped agent. |
| 3 F.4 — mobile attachment + PDF viewer | #387 | `552c3aa` | Salvaged. PDF inline rendering via pdfx. |
| 3 F.3 — mobile customer-pivot | #388 | `ec01e32` | Salvaged. Resolved sibling tap-handler conflicts. |
| 3 E.4 — helm job-detail attachments | #389 | `c98b2aa` | Salvaged. Resolved E.2/E.3 routing conflicts. |
| 4 — BKDS per-cell signing | #390 | `7c1d222` | HatBkds module + verifier + `brain resign-pending` admin verb. Production root swap-in deferred (gated on D-O5p). |
| 5 — migration + docs | #391 | `4a0d92f` | `legacy migrate-to-graph` verb + 3 operator runbooks + canon updates. |
| Bridget unblock | #392 | `5667c6b` | iOS Simulator Firebase stub (not part of D-DOG.1.0c proper but landed same day). |

## §1 — Why this matters (the type-path realisation, original scoping)

The cell-type schema in `extensions/oddjobz/src/cell-types/` already encodes the dimensions:

| Type | Dimension |
|---|---|
| `customer.v1` | WHO |
| `site.v1` | WHERE |
| `job.v1` | WHAT (with FSM = WHEN-states) |
| `attachment.v1` | HOW (evidence — PDFs, photos) |
| `message.v1` | WHY (communication) |
| `quote.v1` / `estimate.v1` | HOW MUCH |
| `invoice.v1` | HOW PAID |
| `visit.v1` | WHEN (scheduled) |

The dimensions live in **edges between cells**, not fields on one cell. A ratified proposal should produce a graph:

```
              site.v1                ← WHERE
                │
        ┌───────┼────────┐
        ▼       ▼        ▼
     customer customer customer       ← WHO (tenant×N + agent + owner)
        │       │        │
        └───────┼────────┘
                ▼
              job.v1                  ← WHAT (FSM + workOrderNumber + dueDate
                │                        + billingParty + photos-bool)
                │
                ▼
            attachment.v1             ← HOW (source PDF + photo metadata)
```

Today: ratify writes a single `job.v1` JSONL row with 6 flat fields. **95% of the proposal data is dropped.**

## §2 — Signing model (revised 2026-05-04)

Earlier scoping had a tiered hot-pocket / cold-multisig vault. **Operator clarified that's overkill for v0** because:

- No customer payments flow through oddjobz initially (Stripe may bolt on later)
- Customers don't have BSV — no near-term BSV-denominated invoicing
- Therefore no operator-held economic value at the cell layer that needs cold-tier protection

**v0 signing model (BRC-42 BKDS, per-cell rotation):**

- **One ROOT** key, encrypted at rest under wallet KEK
- **Per-cell deterministic derivation** via BRC-42 BKDS:
  - `protocolID = "oddjobz.cell-sign/v1"` (domain + version scoped)
  - `keyID = <cell-content-hash>` (so two-different-cells → two-different-derived-keys; same cell content → same derived key for idempotent re-signing)
  - `counterparty = <operator's domain identity>`
- Each cell is signed by a **freshly derived key**; the derived key is then **discarded** (not stored)
- All derived keys are **fully recoverable** from the root + the scope, so signature verification + audit + replay all work deterministically
- No multisig, no threshold-sig, no sweep policy, no cold tier in v0
- **Compromise blast radius**:
  - Compromise of a single derived signing key → compromises only that one cell
  - Compromise of the root → total (all derivable keys are forgeable)
  - Each cell's signature is by a **different pubkey**, so cells are **unlinkable by signature** (privacy property — third parties can't cluster cells by signing key without access to the root)

**Two separate things in this Tier 0 stance:**

| Item | Purpose | What's stored | Encumbrance |
|---|---|---|---|
| Hat-key root | Sign cells (each cell gets its own derived key via BKDS) | one root, encrypted under wallet KEK | KEK protection |
| BSV fee wallet | Pay L1 anchor tx fees IF/WHEN cells get anchored | <1M sats (pocket change), single-sig, no encumbrance | none — pure pocket change |

The BSV fee wallet is a future concern (anchoring is deferred — see §2.1 below). For D-DOG.1.0c proper, only the hat-key root matters; cells live in the encrypted slot-store at Layer 1 without needing on-chain anchors.

**Cold tier is explicitly deferred** to whenever operator-managed economic value enters the cell layer (e.g. when Stripe-paid invoices become signed cells, or when customer-facing receipts need cryptographic provenance to outsiders). At that point a Tier 1 / Tier 2 split (or full tiered-vault as originally scoped) gets re-introduced as its own deliverable.

### §2.1 — BSV anchoring (deferred)

L1 anchoring of the cell DAG to BSV is **out of scope for D-DOG.1.0c**. Cells are signed under the hot hat and stored in the local slot-store; no on-chain anchor tx fires. When anchoring becomes needed (operator wants verifiable history exportable to outsiders, or ships oddjobz cells to a third party), a separate deliverable adds:

- Hot fee wallet management (<1M sats, single-sig, refill semantics)
- Anchor tx submission path (per-cell? batched? cron-driven?)
- Anchor receipt + verification machinery

Track as `D-DOG.1.0e — BSV anchoring` (post-1.0c, post-Tier-3, no urgency).

## §3 — Phase plan & parallelisation

Dependency graph:

```
PHASE 1 ── A (schema) ───────────────────────┐
                                              │
PHASE 2 ── C (translator) ── D (view stores) ─┤── PHASE 3 ── E (helm UI)
            ↑                                 │              ‖
            └─ depends on A                   │              F (mobile UI)
                                              │
PHASE 4 ── B (hat-key vault) ─────────────────┴── retrofitted into C
                                                  
PHASE 5 ── G (migration) ── reads C+D
       ── H (docs) ── parallel throughout

✓ Parallel within phase wherever cells are file-disjoint.
✗ Phases are sequential (each depends on the prior).
```

**Two viable orderings:**

- **Option I (architectural purity)**: 1 → 2 → 4 → 3 → 5. Cells are signed before the UI renders them.
- **Option II (operator-value first, RECOMMENDED)**: 1 → 2 → 3 → 4 (retrofit signing) → 5. UI works against unsigned-but-graphed cells while the vault matures. Trust level matches today's Layer 2 until B lands.

**Recommend Option II** — it lets you actually look at the graph in helm/mobile within ~5 days wall-clock. Phase 4's signing retrofit is then a content-preserving upgrade. Operator's prior pattern ("ship the value, harden after") supports this.

## §4 — Tracking matrix

Format:
- `[ ]` = pending
- `[~]` = in flight
- `[x]` = shipped (link PR#)
- `parallel-with` = file-disjoint, can run concurrently
- `effort` = focused-dev-days estimate

### Phase 1 — Cell schema extensions (foundational)

| ID | Title | Files | Depends | Parallel-with | Effort | Status | PR |
|---|---|---|---|---|---|---|---|
| A.1 | Extend `oddjobz.job.v1` schema with workOrderNumber, dueDate, issuanceDate, billingParty, hasPhotos, photoCount, propertyKey, customerRefs[], siteRef, attachmentRefs[] | `extensions/oddjobz/src/cell-types/job.ts` | — | A.2, A.3, H | 1d | [ ] | — |
| A.2 | Bump type hashes (`oddjobz.job.v2`, `oddjobz.customer.v2`, `oddjobz.site.v2`, `oddjobz.attachment.v2`) and register in typeHashRegistry | `core/cell-ops/src/typeHashRegistry.ts`, related test vectors | — | A.1, A.3, H | 0.5d | [ ] | — |
| A.3 | Backward-compat aliases — old field names + v1 type hashes still resolve; helm + mobile renderers can read either shape | `extensions/oddjobz/src/cell-types/index.ts`, helm + mobile shape-readers | A.1 | A.2, H | 0.5d | [ ] | — |
| A.4 | Extend `customer.v1` with role enum (tenant/agent/owner/pm/sub-tradie/other), normalisedPhone, sourceProvenance | `extensions/oddjobz/src/cell-types/customer.ts` | — | A.1, A.2, A.3, H | 0.5d | [ ] | — |
| A.5 | Extend `site.v1` with normalisedAddress (canonical), keyNumber, lookupKey | `extensions/oddjobz/src/cell-types/site.ts` | — | A.1-4, H | 0.5d | [ ] | — |
| A.6 | Extend `attachment.v1` with sourceBlobKey, mimeType, pageCount, photoCount, has_photos | `extensions/oddjobz/src/cell-types/attachment.ts` | — | A.1-5, H | 0.5d | [ ] | — |

**Phase 1 wall-clock**: ~1.5 days with 3-4 parallel agents on A.1, A.4-A.6. A.3 sequences after A.1.

### Phase 2 — Brain translator + view stores

| ID | Title | Files | Depends | Parallel-with | Effort | Status | PR |
|---|---|---|---|---|---|---|---|
| C.1 | Refactor `oddjobz_ratify_handler.zig` to walk SIRProgram → graph: site+customers+job+attachments | `runtime/semantos-brain/src/oddjobz_ratify_handler.zig` (rewrite) | A.1-A.6 | C.5 | 1d | [ ] | — |
| C.2 | Site lookup-or-mint by normalisedAddress | `runtime/semantos-brain/src/sites_store_fs.zig` (extend; create if absent) | A.5 | C.3, C.4, C.5 | 0.5d | [ ] | — |
| C.3 | Customer lookup-or-mint by (normalisedPhone OR email OR name+role+site) | `runtime/semantos-brain/src/customers_store_fs.zig` (extend) | A.4 | C.2, C.4, C.5 | 0.5d | [ ] | — |
| C.4 | Job mint with all rich fields + refs to site + customers | `runtime/semantos-brain/src/jobs_store_fs.zig` (extend) | A.1, C.1 | C.2, C.3, C.5 | 0.5d | [ ] | — |
| C.5 | Attachment mint per source PDF; ref blob-store key; ref job | `runtime/semantos-brain/src/attachments_store_fs.zig` (new file) | A.6, C.1 | C.2, C.3, C.4 | 0.5d | [ ] | — |
| C.6 | RPC contract update: `oddjobz.ratify_proposal` returns `{cellIds: { site, customers[], job, attachments[] }}` (graph IDs, not flat array) | `runtime/semantos-brain/src/oddjobz_ratify_handler.zig`, `runtime/legacy-ingest/src/cell-writer/brain-rpc.ts` (TS shape) | C.1-C.5 | D.1, D.2 | 0.5d | [ ] | — |
| D.1 | New cross-store query RPC: `oddjobz.find_jobs_at_site(siteId)`, `oddjobz.find_jobs_for_customer(customerId)` | new `runtime/semantos-brain/src/oddjobz_query_handler.zig` | C.6 | D.2, D.3 | 1d | [ ] | — |
| D.2 | Backward-compat reads — old flat JSONL rows still serve helm/mobile until migration runs | `runtime/semantos-brain/src/jobs_store_fs.zig` (read path) | C.6 | D.1, D.3 | 0.5d | [ ] | — |
| D.3 | FS fallback in `BrainRpcCellWriter` (TS) writes graph instead of single row when receiving the new RPC shape | `runtime/legacy-ingest/src/cell-writer/brain-rpc.ts` | C.6 | D.1, D.2 | 0.5d | [ ] | — |

**Phase 2 wall-clock**: ~3 days. C.1 first (translator skeleton), then C.2-C.5 in parallel, then C.6, then D.1+D.2+D.3 in parallel.

### Phase 3 — Helm + Mobile graph-aware UI

| ID | Title | Files | Depends | Parallel-with | Effort | Status | PR |
|---|---|---|---|---|---|---|---|
| E.1 | Helm JobList renders site address + primary customer name + due date + has-photos badge | `apps/loom-svelte/src/lib/components/JobList.svelte` | A, D.1 | E.2-4, F | 1d | [ ] | — |
| E.2 | Helm site-pivot route — all jobs at this address | `apps/loom-svelte/src/routes/sites/[id]/+page.svelte` (new) | A, D.1 | E.1, E.3, E.4, F | 1d | [ ] | — |
| E.3 | Helm customer-pivot route — all jobs for this person | `apps/loom-svelte/src/routes/customers/[id]/+page.svelte` (new) | A, D.1 | E.1, E.2, E.4, F | 1d | [ ] | — |
| E.4 | Helm job-detail with linked attachments view (download PDF, render embedded photos) | `apps/loom-svelte/src/routes/jobs/[id]/+page.svelte` (extend) | A, D.1 | E.1-3, F | 0.5d | [ ] | — |
| F.1 | Mobile JobList renders site + primary customer + due date + has-photos icon | `apps/oddjobz-mobile/lib/src/helm/job_list.dart` | A, D.1 | F.2-4, E | 1d | [ ] | — |
| F.2 | Mobile site-pivot screen | `apps/oddjobz-mobile/lib/src/helm/site_screen.dart` (new) | A, D.1 | F.1, F.3, F.4, E | 1d | [ ] | — |
| F.3 | Mobile customer-pivot screen | `apps/oddjobz-mobile/lib/src/helm/customer_screen.dart` (new) | A, D.1 | F.1, F.2, F.4, E | 1d | [ ] | — |
| F.4 | Mobile attachment screen with PDF viewer (use `pdfx` or `flutter_pdfview` package) | `apps/oddjobz-mobile/lib/src/helm/attachment_screen.dart` (new) + `pubspec.yaml` | A, D.1 | F.1-3, E | 0.5d | [ ] | — |

**Phase 3 wall-clock**: ~1.5 days with E×4 + F×4 in parallel. The platform split (Svelte vs Flutter) means E and F never conflict.

### Phase 4 — BKDS per-cell signing (v0)

Per §2 revision: BRC-42 BKDS with per-cell key derivation; one root (KEK-encrypted), each cell gets its own derived signing key. No static keys, no cold tier, no sweep policy.

| ID | Title | Files | Depends | Parallel-with | Effort | Status | PR |
|---|---|---|---|---|---|---|---|
| B.1 | Hat-key root storage + BKDS derivation primitive — `derive(root, "oddjobz.cell-sign/v1", cellContentHash) → signingKey`. Reuse the existing BCA / BRC-42 derivation code at `core/cell-engine/src/bca.zig` + TS mirror at `core/protocol-types/src/bca.ts`. | new `runtime/semantos-brain/src/hat_bkds.zig` (thin wrapper that holds the encrypted root + exposes `signCell(cellPayload, header) → sig`) + tests covering recoverable derivation | — | H | 1d | [ ] | — |
| B.2 | Wire derive-then-sign into Phase 2's translator — every cell-write call computes content hash → derives → signs → discards key | `runtime/semantos-brain/src/oddjobz_ratify_handler.zig` (extend) | B.1, C.6 | H | 0.5d | [ ] | — |
| B.3 | Verifier — given a cell with `signedBy: <derived pubkey>` and a signature, verify by re-deriving the expected pubkey from the root + scope + cellID and comparing | new `runtime/semantos-brain/src/hat_bkds_verifier.zig` + tests | B.1 | B.2, H | 0.5d | [ ] | — |
| B.4 | Backward-compat — Phase-2 unsigned cells get re-signed in place via a `brain resign-pending` admin verb | new admin verb in `runtime/semantos-brain/src/cli.zig` | B.2 | H | 0.5d | [ ] | — |
| ~~B.5~~ | ~~Cold tier threshold-sig~~ | DEFERRED until operator-held economic value enters the cell layer (post-Stripe integration era). Will likely be implemented as a SEPARATE root with multi-component unlock — derivation pattern unchanged. | — | — | — | DROPPED for v0 | — |
| ~~B.6~~ | ~~Sweep policy DSL~~ | DEFERRED — no value sweeps in v0 | — | — | — | DROPPED for v0 | — |

**Phase 4 wall-clock (revised)**: ~2 days. Cold tier + sweep policy deferred to a future Tier 7 / Stripe-integration deliverable.

**Notes for the implementer:**

- The derivation scope is **`protocolID = "oddjobz.cell-sign/v1"`**. Bumping versions is a coordinated change across all live cells (every previously-signed cell stays verifiable under v1; new cells under v2 get a new derivation).
- The `keyID` is the **content hash of the cell payload** (canonical-JSON-ed, hashed with SHA-256). This means: idempotent re-signing of identical content yields identical signatures, and any payload mutation invalidates the signature deterministically.
- The **derived public key is what's recorded in the cell's `signedBy` field** — not the root pubkey. This is what gives the unlinkability property: a third party verifying the cell sees a unique pubkey per cell, with no cross-cell correlation possible without the root.
- **Recovery**: any party who has the root + the scope + the cellID can re-derive the signing key and re-sign. This is the operator's recovery path if the brain disk is lost (root is also separately escrowed via BRC-42 BKDS recovery enrolment per the existing BRC-52 cert-flow — out of scope for D-DOG.1.0c, but the property is preserved).

### Phase 5 — Migration + Docs

| ID | Title | Files | Depends | Parallel-with | Effort | Status | PR |
|---|---|---|---|---|---|---|---|
| G.1 | `legacy migrate-to-graph` verb — walks existing flat `jobs.jsonl` rows, matches each to its source proposal in proposal-store, ratifies as graph (best-effort; un-matchable rows flagged legacy) | `runtime/legacy-ingest/src/verb.ts` (extend) | C, D | G.2, H | 1d | [ ] | — |
| G.2 | Helm + mobile renderers display "legacy unmigrated" badge on flat rows; operator can manually correct | UI extension across E.1, F.1 | G.1 | H | 0.5d | [ ] | — |
| H.1 | Tiered hat-key vault runbook | new `docs/operator-runbooks/hat-vault.md` | — | (all) | 0.5d | [ ] | — |
| H.2 | Cell-DAG graph navigation guide for operators | new `docs/operator-runbooks/job-graph.md` | — | (all) | 0.5d | [ ] | — |
| H.3 | Update `docs/canon/unification-matrix.yml` + `docs/canon/deliverables.yml` | edits | — | (all) | 0.5d | [ ] | — |
| H.4 | Update `docs/operator-runbooks/dogfood-gmail.md` to mention graph-aware ratification | edit | C, D | (all) | 0.25d | [ ] | — |
| H.5 | Sovereignty implications doc — what hot-key compromise means; cold-key recovery story | new `docs/canon/sovereignty-tiered-vault.md` | B | (all) | 0.5d | [ ] | — |

**Phase 5 wall-clock**: ~1 day with G in parallel with H.

## §5 — Wall-clock total (revised)

With aggressive parallelisation:

| Phase | Sequential days | Parallel days | Notes |
|---|---|---|---|
| 1 | 3.5 | 1.5 | A.1 + A.4 + A.5 + A.6 + A.2 in parallel; A.3 sequences after A.1 |
| 2 | 4.5 | 3 | C.1 first, then C.2-C.5 parallel, then C.6, then D.1+D.2+D.3 parallel |
| 3 | 6.5 | 1.5 | E×4 ‖ F×4; platform-split means zero conflict |
| 4 | 2.5 | 1.5 | BKDS per-cell derivation; cold tier + sweep policy deferred (§2 revision) |
| 5 | 2.75 | 1 | G ‖ H |
| **Total** | **19.5 dev-days** | **8.5 wall-clock days** |

Caveat: wall-clock estimate assumes 4-5 parallel agents at peak. If single-agent serial (no parallelism), you get the 19-day number.

## §6 — Risks & open questions

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | Cold-tier multisig coordination is genuinely hard — operator needs to physically interact with two devices at minimum to release a cold cell. UX matters. | High | Phase B.2 includes mobile-side approval UI; assess UX after first cold sign in dogfood; iterate |
| R2 | Customer lookup-or-mint dedupe heuristic (phone OR email OR name+role+site) may produce false matches across genuinely-different customers with similar contact info | Medium | Lookup match must be confirmable by the operator on first use; helm/mobile prompts "is this the same Sarah Liu as the one at 13 Orealla Cr?" before linking |
| R3 | Site lookup-or-mint by normalised address — two distinct units at the same building may collapse if address normalisation is too aggressive (e.g. `4/5 Hygieta` vs `5 Hygieta` vs `Unit 4, 5 Hygieta`) | Medium | Normalisation rules tested against operator's historical address list; "key #N" suffix preserved when present (it's a stable disambiguator from CP) |
| R4 | Phase 3 UI work depends on Phase 2 D.1 query RPC being stable; if RPC contract churns mid-Phase-3, both helm + mobile rework | Low | Lock the RPC contract at end of Phase 2; treat any change to it as a versioned breaking change |
| R5 | Migration (G.1) of existing 72 flat cells may not have proposal-store matches for all of them (the operator's first dogfood may have lost some pre-extraction blobs) | Low | Un-matchable rows stay flat with the `legacy_unsigned` badge; operator can re-extract or manually correct as desired |
| R6 | Helm + mobile renderer changes in Phase 3 conflict with any pending PR on the same files (jam-room work, smoke-test fix-pass-2 work) | Low | Coordinate at Phase 3 firing time; rebase as needed |

## §7 — Decision points (operator input needed)

1. **Confirm Option I vs Option II ordering** (architectural purity vs operator-value first). RECOMMEND Option II.
2. ~~Cold-tier signing scheme~~ — RESOLVED 2026-05-04: deferred entirely (no economic value in v0 cells). See §2 revision. v0 = single hot hat key.
3. ~~Cold-tier value threshold~~ — RESOLVED 2026-05-04: same.
4. **Migration scope**: just promote forward (existing 72 cells stay flat with badge), or attempt full migration (re-ratify each through the graph translator)?
5. **Phase 3 UI breadth**: minimal pivot views (site + customer pivots) or full graph navigation (drill into attachment from job; navigate from customer to other jobs at their other sites; etc.)?
