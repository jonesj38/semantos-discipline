---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/D-Reingest-Typed-Cells.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.662621+00:00
---

# D-Reingest-Typed-Cells — Gmail reingest producing properly-typed entity cells

**Version**: 0.1 (initial PRD)
**Date**: 2026-05-16
**Status**: Draft — ready for implementation scoping
**Duration**: ~2-3 weeks
**Prerequisites**:
- `runtime/legacy-ingest/` pipeline scaffold (existing — providers, oauth, blob-store, cell-writer, ratification, etc.)
- `extensions/oddjobz/` cartridge — lifted via DLO.3-5 (closing audit `a867901`)
- `runtime/semantos-brain/src/substrate_entity.zig` — typehash registry + entity-tag table + linearity class table (RM-110-113, concurrent session)
- `extensions/oddjobz/src/intake-handler.ts` + `lead-extract.ts` — existing LLM-based extraction surface

**Master document**: [`docs/design/WALLET-LEGACY-INGEST.md`](../design/WALLET-LEGACY-INGEST.md) (the LI1-LI6 ingest design)
**Branch prefix**: `reingest/typed-cells`

---

## Context

The legacy-ingest pipeline pulls jobs/customers/visits from Gmail through a Paskian ratification loop today (`runtime/legacy-ingest/src/{ingest-worker,refresh-worker,ratification,extractor}.ts`). It writes cells to disk. But the cells produced today are **structurally incomplete**:

1. **Half the job sheets are missing details** — the extractor's prompt + field schema doesn't reliably capture who/what/when/where/why/how. The LLM returns partial structured data; cells get written with empty fields.
2. **Image attachments fail to extract** — Gmail messages with photo attachments lose the photos entirely. No image bytes persisted, no `has_pictures` flag set on the parent job cell.
3. **Cells don't carry proper typehash** — written cells often don't match the `substrate_entity.SPEC_JOB / SPEC_CUSTOMER / SPEC_SITE` typehash slots. Downstream consumers (PWA chat resolver, oddjobz handlers) can't find cells by entity tag.
4. **People-of-contact aren't role-classified** — every contact gets created as a generic `customer` cell. Owner/tenant/agent/contractor/witness role distinctions lost.
5. **No site-indexing keystone** — the same physical address appears across multiple emails as 3 different sites; deduplication via fuzzy address match doesn't happen at ingest time.

The user-facing consequence: when the operator types in PWA chat *"quote 500 for the pergola job"*, the resolver can't find the right `job_cell` because (a) it might not exist, (b) it might exist with empty fields, or (c) it might exist but not be linked to the site_address that "pergola job" implicitly references via context.

## Goal

Reingest all Gmail-sourced operator state through an upgraded pipeline that produces **typed cells matching `substrate_entity.zig`'s registry**, with full who/what/when/where/why/how extraction, role-classified contacts, site-address keying, and attachment retention (PDFs verbatim, images extracted OR `has_pictures` boolean fallback).

After reingest, the chat-resolver use case works:
- Operator types "quote 500 for the pergola job" in PWA
- Resolver fuzzy-matches "pergola job" → exactly one `job_cell` via site description + customer context
- `quotes.draft` verb fires against that job_id with amount=500
- Quote cell links to the resolved job_cell

## Cell shape requirements

Every reingested entity must conform to `substrate_entity.zig`'s spec for its tag.

### Job cell (TAG_JOB = 0x06)

| Aspect | Source | Cell field | Mapping |
|---|---|---|---|
| **WHO** — site owner | Email recipient / `from:` of inbound enquiry | `owner_customer_id` (Customer cell ref) | Site → owner customer (LINEAR ref) |
| **WHO** — point of contact | Email reply-to / contact mentioned in body | `contact_customer_id` (Customer cell ref) | Job → POC customer (optional) |
| **WHO** — operator | Always Todd / hat-rooted | `owner_identity` cert id | Hat-based authority |
| **WHAT** — job summary | LLM-extracted summary (e.g. "deck rebuild + pergola") | `summary: []const u8` | Free text, ≤256 bytes |
| **WHAT** — services | LLM-extracted list (e.g. "demo", "rebuild", "paint") | `service_tags: [N]u32` | Tag IDs from oddjobz taxonomy |
| **WHEN** — first contact | Email `Date:` header of initial inquiry | `first_contact_ms: i64` | Unix ms |
| **WHEN** — scheduled | Operator-set later (not at ingest) | `scheduled_ms: ?i64` | Optional |
| **WHEN** — completed | Operator-set later | `completed_ms: ?i64` | Optional |
| **WHERE** — site | Address from email body (most reliable) or signature | `site_id` (Site cell ref) | **Keystone** — site_id is the primary join key |
| **WHY** — customer intent | LLM-extracted ("renovating before sale", "tenant request", "broken X") | `intent: []const u8` | Free text |
| **HOW** — pricing model | LLM-extracted ("fixed", "T&M", "quote pending") | `pricing_model: enum` | Enum: fixed / time_materials / pending |
| **STATUS** — FSM state | Always `lead` at ingest | `state: JobFsmState` | Per `extensions/oddjobz/zig/src/job_fsm.zig` |
| **EVIDENCE** — source email | Email message-id + cell ref to raw email blob | `source_msg_id` + `source_email_cell_id` | Backreference; never overwritten |

### Site cell (TAG_SITE = 0x07)

Indexed by **normalized address** (lowercase, whitespace-collapsed, street-name-canonical). Lookup happens at ingest: if a job mentions an address matching an existing site_cell (within fuzzy threshold), link; else create new.

| Aspect | Cell field |
|---|---|
| `address_full` (verbatim as given) | `[]const u8` |
| `address_normalized` (lookup key) | `[]const u8` |
| `suburb` | `[]const u8` |
| `state` | `[]const u8` |
| `postcode` | `[]const u8` |
| `key_dropoff_location_hint` (e.g. "under mat", "front-left planter") | `?[]const u8` |
| `notes` | `?[]const u8` |

### Customer cell (TAG_CUSTOMER = 0x01)

Classified by role per the People-of-contact mapping.

| Aspect | Cell field |
|---|---|
| `name` | `[]const u8` |
| `email` (canonical, normalized) | `[]const u8` |
| `phone` (E.164 if extractable) | `?[]const u8` |
| `role` | `enum { site_owner, tenant, property_manager, agent, contractor, witness, unknown }` |
| `linked_site_id` (the site they're associated with) | `?SiteId` |
| `notes` (LLM-summarized — e.g. "prefers SMS, weekdays only") | `?[]const u8` |

### Attachment cell (TAG_ATTACHMENT = 0x05)

| Aspect | Cell field |
|---|---|
| `mime_type` | `[]const u8` |
| `filename` | `[]const u8` |
| `blob_sha256` (content-addressed; bytes in blob-store) | `[32]u8` |
| `parent_cell_id` (the job/customer cell this attaches to) | `CellId` |
| `extraction_status` | `enum { stored_verbatim, image_extracted, pdf_text_extracted, failed }` |
| `has_pictures` (set on PARENT job cell, mirrored here for indexing) | `bool` |

PDFs: stored verbatim. The byte stream goes through `runtime/legacy-ingest/src/blob-store.ts` as today.
Images: extracted from MIME multipart, stored as separate Attachment cells linked to parent job. If extraction fails (corrupt MIME, unknown encoding), set `extraction_status=failed` + flip parent's `has_pictures=true` so the operator at least knows pictures EXISTED even if we couldn't read them.

## Pipeline shape

```
Gmail message arrives
   ↓
[1. Raw blob persistence — EXISTING]
   raw email bytes → blob-store via SHA-256 content addressing
   ↓
[2. Provider parsing — EXISTING but needs hardening]
   gmail provider extracts: from, to, subject, date, body, attachments
   ↓
[3. Extraction — EXISTING, needs prompt + field-schema upgrade]
   LLM extracts: site address, contact name+email+phone+role, job summary,
   services, intent, attachments-metadata.
   Output: structured proposal matching cell schemas above.
   ↓
[4. Site dedupe — NEW]
   normalize address; query site_store for fuzzy match (per oddjobz_query_handler
   pattern); if match: link; if not: enqueue new site_cell proposal.
   ↓
[5. Customer dedupe + role classification — NEW]
   normalize email; query customer_store; resolve role from email body context
   (e.g. signature blocks, salutation, replies thread context).
   ↓
[6. Cell encoding — NEW (use substrate_entity)]
   build Job cell via substrate_entity.encodeCell with SPEC_JOB,
   Site cell with SPEC_SITE, Customer cell with SPEC_CUSTOMER.
   Each cell carries proper typehash + linearity class.
   ↓
[7. Attachment handling — NEW for images]
   PDFs: blob_sha256 → stored, Attachment cell created.
   Images: extract from multipart, store as blob, Attachment cell created,
   parent has_pictures=true.
   Failed extraction: parent has_pictures=true, Attachment cell with
   extraction_status=failed.
   ↓
[8. Ratification queue — EXISTING]
   proposals enter `runtime/legacy-ingest/src/ratification/` queue.
   Operator reviews; on accept, cells get signed + persisted to
   extensions/oddjobz/zig/src/lmdb/ entity stores via the lifted cartridge.
   ↓
[9. Audit log — EXISTING]
   every reingest action records: source_email_msg_id, target_cell_ids
   (jobs/sites/customers/attachments), operator_decision.
```

Steps 1-3 + 8-9 EXIST. Steps 4-7 are the new work.

## Source Files / References

| Alias | Path | What to read |
|---|---|---|
| `INGEST:WORKER` | `runtime/legacy-ingest/src/ingest-worker.ts` | Current ingest loop entry point |
| `INGEST:GMAIL` | `runtime/legacy-ingest/src/providers/` | Gmail provider — list, fetch, attachment handling |
| `INGEST:EXTRACTOR` | `runtime/legacy-ingest/src/extractor/` | LLM-driven extraction — prompts + field schemas |
| `INGEST:BLOB` | `runtime/legacy-ingest/src/blob-store.ts` | SHA-256 content-addressed blob storage |
| `INGEST:RATIFY` | `runtime/legacy-ingest/src/ratification/` | Proposal → ratified cell queue |
| `INGEST:CELL-WRITER` | `runtime/legacy-ingest/src/cell-writer/` | Cell-writing surface — needs substrate_entity integration |
| `BRAIN:SUBSTRATE-ENTITY` | `runtime/semantos-brain/src/substrate_entity.zig` | Typehash registry + entity specs (TAGs + LinearityClass + SPEC_*) |
| `BRAIN:CELL-ENGINE` | `core/cell-engine/` | 1024-byte cell format + magic + linearity enforcement |
| `ODDJOBZ:STORES` | `extensions/oddjobz/zig/src/{jobs,quotes,invoices,customers,leads,visits}_store_lmdb.zig` | Entity stores (carved into cartridge) — receive ratified cells |
| `ODDJOBZ:INTAKE` | `extensions/oddjobz/src/intake-handler.ts` | Existing conversation-driven intake (will share LLM scaffolding) |
| `ODDJOBZ:LEAD-EXTRACT` | `extensions/oddjobz/src/lead-extract.ts` | Existing lead extraction (will share prompt scaffolding) |
| `DESIGN:LEGACY-INGEST` | `docs/design/WALLET-LEGACY-INGEST.md` | LI1-LI6 design — the parent ingest workstream |
| `RESOLVER:CHAT` | (new — TBD) | PWA chat → cell resolver. Built post-reingest; reingest must produce cells the resolver can match against. |

## Deliverables

### D-RTC.1 — Address normalizer + site-dedupe pass (~3 days)

**Files**:
- New: `runtime/legacy-ingest/src/address-normalize.ts` — canonicalize to lowercase / trim / collapse whitespace / handle common Australian address suffixes ("st" / "street" / "rd" / "road" / etc.)
- New: `runtime/legacy-ingest/src/site-dedupe.ts` — given a normalized address, query the lifted `sites_store_lmdb` via dispatcher; return existing site_id if match; else propose new site_cell
- Test fixture: 30 OJT-realistic addresses from current production data, half deduped, half new

**Acceptance gate**: feed test fixture through normalizer + dedupe; expect 15 existing site refs + 15 new site proposals; zero false-positive dedupes (different addresses incorrectly merged).

### D-RTC.2 — Contact role classifier (~3 days)

**Files**:
- New: `runtime/legacy-ingest/src/role-classifier.ts` — heuristic + LLM-assisted classifier mapping (email-body-context, signature block, reply-thread position) → role enum
- Role enum: `site_owner | tenant | property_manager | agent | contractor | witness | unknown`
- Fallback: when ambiguous, `unknown` + flag for operator review

**Acceptance gate**: 50 hand-labeled email contexts; classifier achieves ≥80% precision per role; `unknown` rate ≤15%.

### D-RTC.3 — Extraction prompt + field-schema upgrade (~4 days)

**Files**:
- Modified: `runtime/legacy-ingest/src/extractor/` — upgrade prompt to elicit all who/what/when/where/why/how fields per the cell-shape table above
- New: `runtime/legacy-ingest/src/extractor/cell-schema.json` — JSON schema the LLM is constrained to produce
- LLM output validated against `core/protocol-types/src/extension-grammar.ts` shape (Phase 36A schema)

**Acceptance gate**: against 100 OJT emails, schema-conformant rate ≥95%; field-population rate (per field) ≥80% for required fields.

### D-RTC.4 — Cell encoding via substrate_entity (~3 days)

**Files**:
- Modified: `runtime/legacy-ingest/src/cell-writer/` — replace ad-hoc cell construction with calls into `substrate_entity.encodeCell(SPEC_*, payload_json)` via brain-side dispatcher OR direct TS port of the encoder
- Each cell carries correct typehash from `substrate_entity.SPEC_JOB / SPEC_SITE / SPEC_CUSTOMER / SPEC_ATTACHMENT`
- Linearity class enforced per spec (LINEAR for site_cells, AFFINE for customers, etc. — see substrate_entity.zig SPEC_* definitions)

**Acceptance gate**: every cell produced by reingest passes `substrate_entity.validateCellTypeHash(cell, expected_spec)` brain-side. Drift detector (already in `runtime/semantos-brain/src/lmdb/drift_detector.zig`) reports zero drift events.

### D-RTC.5 — Attachment pipeline (PDF + image) (~3 days)

**Files**:
- New: `runtime/legacy-ingest/src/attachment-extractor.ts` — parse MIME multipart from raw email bytes; extract attachment streams; classify by MIME type
- Modified: `runtime/legacy-ingest/src/blob-store.ts` — already content-addresses; now invoked per-attachment + per-image
- New: image extraction logic — for `image/*` MIME types, store verbatim; flip parent `has_pictures=true`
- New: PDF retention — `application/pdf` stored verbatim + linked to parent job_cell

**Acceptance gate**: against 30 OJT emails containing attachments, every PDF survives the round-trip byte-identical (sha256 match); every image is either extracted or `has_pictures=true` + `extraction_status=failed` recorded.

### D-RTC.6 — Reingest worker (~2 days)

**Files**:
- New: `runtime/legacy-ingest/src/reingest-worker.ts` — re-runs the upgraded pipeline against the existing Gmail history (resumable via gmail cursor-store)
- Idempotent: cells with matching `source_msg_id` are skipped or upgraded-in-place (operator policy)
- Audit log: every reingest event records source + result + (if upgrade) before/after diff

**Acceptance gate**: dry-run reingest of 1000 OJT emails completes without crashing; produces structured ratification queue ≥95% schema-conformant per D-RTC.3 gate.

### D-RTC.7 — Operator-side reingest CLI (~1 day)

**Files**:
- New brain CLI: `brain reingest <gmail-account> [--dry-run] [--since <date>] [--upgrade-existing]`
- Drives the reingest worker; reports progress + queue depth

**Acceptance gate**: `brain reingest todd@oddjobtodd.info --dry-run --since 2025-01-01` reports projected ratification counts without writing.

## TDD Gate

Per-deliverable acceptance gates above. End-to-end:
- T1: Address normalize round-trip on 30 fixtures
- T2: Role classifier ≥80% precision
- T3: Schema conformance ≥95% over 100 emails
- T4: Cell typehash + linearity validation (zero drift) over reingest
- T5: PDF byte-identical round-trip over 30 attachments
- T6: Image extraction OR has_pictures fallback over 30 attachments
- T7: Reingest worker stable over 1000-email dry-run
- T8: Operator CLI surface works end-to-end
- T9: **Chat resolver integration** (separate deliverable post-reingest): "quote 500 for the pergola job" disambiguates to single job_cell

T9 is the user-acceptance gate — proves the cells produced by D-RTC.1-7 are queryable by natural-language context.

## What NOT to Do

- **Don't write cells without typehash** — every cell goes through substrate_entity.encodeCell with the correct SPEC_*. If a path skips this, it doesn't ship.
- **Don't drop PDFs** — verbatim retention via blob-store is mandatory. Operator references the original PDF for ground truth.
- **Don't silently lose images** — if extraction fails, set `has_pictures=true` + `extraction_status=failed` so the operator at minimum knows pictures existed.
- **Don't auto-ratify** — every reingested cell enters the ratification queue. Operator approves. Future automation possible but not in scope.
- **Don't overwrite operator-edited cells** — if a cell exists with operator-set fields (e.g. operator added a phone number after first ingest), don't blow it away. Upgrade-in-place merges with operator data winning on conflict.
- **Don't drift from extension-grammar schema** — the cell shapes in this PRD must match `core/protocol-types/src/extension-grammar.ts` + `core/protocol-types/src/extension-manifest.ts` shapes. If they don't align, surface a DECISION-PENDING.

## Resolved decisions (2026-05-16, Todd: "go with recommended")

- **DECISION-10 — Dispatcher-invocation for substrate_entity.encodeCell** ✓ resolved.
  Brain-side encoder is the single source of truth for typehash; every cell-write hits the audit log. TS cell-writer in `runtime/legacy-ingest/src/cell-writer/` issues JSON-RPC calls into the brain dispatcher (`entity.encode` verb — to be registered via verb_dispatcher in D-RTC.4) rather than reimplementing the encoder in TypeScript.

- **DECISION-11 — Accept Haiku LLM costs** ✓ resolved.
  ~$0.001/email × ~1000 OJT emails = ~$1 per reingest. Acceptable for V1. Revisit if reingest scales to 50k+ emails. Per-iteration cost included in audit log entries for budget tracking.

- **DECISION-12 — Chain new cell on conflict (prevStateHash)** ✓ resolved.
  When reingest re-extracts a source_msg_id with different fields than the existing cell, a new cell is written with `prevStateHash` pointing at the prior version. Operator-visible history preserved; auditable. The previous cell stays addressable for any consumers that haven't followed the chain yet. Cartridge-side store-LMDB lookups follow the chain to current head by default.

## Next Phase

After this reingest completes:
- **D-Chat-Resolver** — PWA chat surface that resolves natural-language references ("the pergola job") to entity cells via context-window fuzzy matching. Depends on the typed cells this PRD produces.
- **D-Quote-Increment** — `quotes.draft` verb dispatch from chat ("quote 500 for ...") that writes a quote_cell linked to the resolved job_cell. Mostly already exists via `extensions/oddjobz/zig/src/quotes_store_lmdb.zig` + `quote_fsm.zig` (carved DLO.3-5); the new bit is the chat→verb routing.
- **D-Reingest-Multi-Source** — extend the same pipeline to Meta/WhatsApp/Google Calendar/Xero per LI4-LI6.

## References

- `docs/design/WALLET-LEGACY-INGEST.md` (parent design)
- `docs/guides/LEGACY-INGEST-GMAIL-SETUP.md` (operator setup)
- `runtime/legacy-ingest/src/` (existing pipeline scaffold)
- `runtime/semantos-brain/src/substrate_entity.zig` (typehash + linearity registry; RM-110-113)
- `extensions/oddjobz/src/{intake-handler,lead-extract,ratification-queue}.ts`
- `extensions/oddjobz/zig/src/{jobs,customers,visits,quotes,invoices,leads}_store_lmdb.zig` (carved entity stores)
- `core/protocol-types/src/extension-grammar.ts` (Phase 36A schema)
- Memory `voice_notes_workflow.md` (intent-grammar capture pattern — companion to chat resolver)
- Memory `v1_production_is_test_data.md` (reingest unblocks real cutover; current production data is throwaway)
