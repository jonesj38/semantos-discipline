---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/OJT-UNIFIED-QUOTE-INVOICE-PLAN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.725255+00:00
---

# OJT — Unified Conversation → Quote → Invoice Pipeline

**Status:** Tracking document. Field-operations level (not substrate theory).
**Companion docs:**
- `ODDJOBZ-CONVERSATION-ARCHITECTURE.md` — canonical turn shape, SCG model, substrate deliverables
- `ODDJOBZ-OPERATOR-FIELD-ACTIVATION-TRACKING.md` — brain read-surface + operator/field app activation
- `CUSTOMER-CONV-LOOP-PLAN.md` — TDD loop for Twilio SMS adapter (W1–W8, complete)

**Audience:** Todd, and anyone picking up a quoting/invoicing/conversation work item.

> **What Todd asked for (verbatim, 2026-05-24):**
>
> "The ROM from the widget can get close to making a quote, but not the WOs.
> I could upload a photo of the receipt when I get it at Bunnings from within
> the job and OCR scrapes it and turns it into a line item. Even if I get a
> work order where I don't need to quote, it's already approved, I still need
> to go and take measurements and buy materials, so I want the same thing for
> the invoice. Approved WOs don't need quotes so go straight to invoice after
> scheduled/attended, but there needs to be a process from the quote to the
> invoice automatically as well but with variance at stuff added under
> instruction from the conversation. Plan the whole thing and create a
> tracking document to unify the conversation across all touchpoints."

---

## 1. The two job flows

Everything branches here. The FSM state and work type determine which path.

### 1A — Quote request (lead job, no prior authorisation)

```
Inbound contact (SMS/widget/email/DM)
        │
        ▼
  [lead] job minted
        │
  Dialogue with customer
    · Twilio SMS ↔ customer
    · Widget chat scoped to job
    · Operator captures voice notes
        │
  Site visit (often needed for scope)
    · Operator takes photos
    · Visits logged
        │
  Quote built from conversation
    · AI extraction from turns
    · Freehand text → line items
    · Catalogue-priced items
    · Quote document saved
        │
  Customer approval
    · Twilio SMS: "Approve $X?" → reply YES
    · Widget: approve button
        │
  [quoted] → [scheduled] → [attended] → [completed]
        │
  Invoice from quote baseline + variance
    · Quote items pre-populated
    · Materials added from receipt OCR
    · Extra labour from conversation
    · Delta documented
        │
  Invoice sent + paid
```

### 1B — Work Order (authorised, no quote needed)

```
Job sheet received (email, WO number present)
        │
        ▼
  [lead] job minted with WO# → DO tab: Schedule bucket
        │
  On-site: measure, see context
    · Operator voice notes
    · Photos of materials needed
        │
  Buy materials (Bunnings, etc.)
    · Receipt OCR → materials line items
        │
  [scheduled] → [attended] → [completed]
        │
  Invoice built directly
    · Materials from receipt OCR
    · Labour from site + conversation
    · WO# referenced
        │
  Invoice sent to REA/owner
```

Key difference: **WO jobs skip the quote step entirely** and go straight to invoice at completion. The attention-feed DO tab already routes these correctly (`isWorkOrderAuthorised → pending_schedule`).

---

## 2. Conversation touchpoints

Every surface that generates turns against a job's entityRef.

| Surface | Direction | Current status | Gap / Next step |
|---|---|---|---|
| **Gmail ingest** | Inbound (customer/REA email) | ✅ Writes email body as first ConversationTurn (P1a, commit e561abd) | Live for new ingest; historical 146 jobs have no turns |
| **Twilio SMS inbound** | Inbound (customer) | ✅ phone→customer→open-job→intake anchor (P1c, commit c2aa7e4) | Push+deploy pending; P4a twilio.json provisioning needed |
| **Twilio SMS outbound** | Outbound (operator→customer) | ✅ ContactConversationScreen + Approval request chip (P1b, P4c) | 503 until twilio.json provisioned |
| **Widget chat** | Inbound (customer types) | ✅ `?j=<cellId>` scopes widget to job (P1b, commit 5d32a37) | Live |
| **REPL** | Operator notes | ✅ `POST /api/v1/repl` → turns written with operator role | Live; no gap |
| **Thread screen send-bar** | Operator typed notes from field app | ✅ `POST /api/v1/voice-note` with transcript only (no audio) | New APK needed; supersedes broken REPL stopgap |
| **Visits** | Operator field notes | ✅ REPL-sourced notes from site visit context | Live (via REPL); no gap |
| **Voice notes** | Operator audio → text | ✅ Wired end-to-end (commit 2a84797) — brain POST /api/v1/voice-note, bun CLI, Flutter mic button + submitVoiceNote | Phase 5 complete |
| **Receipt OCR** | Operator photo → line items | ✅ ReceiptOcrService → QuoteLineItems (P2a/P2b, commit f5fd222) | Flutter only; needs new APK |
| **AI agent** | Drafted replies | ⚠ Agent cert provisioned; draft/approve state machine pending | Gated on `D-OJ-conv-ai-participant` |

### 2.1 The entityRef linkage problem — RESOLVED (P1a/P1b/P1c)

All turns are now anchored to a job's cellId via `BELONGS_TO_ENTITY`:

- **Gmail ingest** ✅ P1a: writes email body + sender as first ConversationTurn, `entityRef={kind:'job', cellHash:jobCellId}`.
- **Twilio inbound** ✅ P1c: phone→customer→open-job lookup in brain; `entity_cell_hash` forwarded to intake handler; turn written with `entityRef`.
- **Widget** ✅ P1b: `?j=<cellId>` query param → intake handler reads `entity_cell_hash` from stdin → all widget turns anchor to that job.

Remaining: 146 pre-existing jobs have zero turns (written before P1a). Historical backfill is a separate ops task (not scheduled).

Approval loop: P4b auto-authorises a `quoted` job when customer replies YES via Twilio. P4c adds the "Approval request" chip in ContactConversationScreen.

---

## 3. Quote building from conversation

### 3.1 What's already built (2026-05-24)

| Component | File | Status |
|---|---|---|
| `QuoteCatalogueService` | `helm/quote_catalogue.dart` | ✅ Built — 14 default QLD 2025 trade items; stored in HatEntityRepository; loaded/persisted per hat |
| `QuoteExtractorService` | `helm/quote_extractor.dart` | ✅ Built — claude-haiku-4-5; `fromConversation(job, turnsRepo)` + `fromText(text)` |
| `QuoteEditorSheet` | `helm/quote_editor_sheet.dart` | ✅ Built — line items CRUD, totals, notes, AI generate card, freehand text parser |
| `QuoteDocRepository` | `helm/quote_editor_sheet.dart` | ✅ Built — saves QuoteDocument to HatEntityRepository per job |
| DO tab wiring | `helm/do_node.dart` | ✅ Built — _doQuote() builds catalogue + extractor, calls showQuoteEditor |
| Attention feed buckets | brain `jobs_handler.zig` | ✅ Built — WO jobs → Schedule, outbound emails filtered, lead+WO → Schedule |
| Full job payload in attention | brain `jobs_handler.zig` | ✅ Built — `writeJobAttentionJson` now calls `writeJobJson` (full payload) |

### 3.2 "Generate from conversation" — gap closed ✅

`QuoteExtractorService.fromConversation()` calls `turnsRepo.fetchTurns(entityRef: job.cellId)`. All three anchor paths that previously returned empty are now wired:

1. ✅ Gmail ingest writes ConversationTurn on job creation (P1a, commit e561abd)
2. ✅ Widget sessions scoped to job cellId via `?j=<cellId>` (P1b, commit 5d32a37)
3. ✅ Twilio resolves phone→customer→job and writes turn (P1c, commit c2aa7e4)
4. ✅ Voice notes submitted to `POST /api/v1/voice-note` land as operator turns (Phase 5, commit 2a84797)

The extractor still falls back to job metadata only when no turns exist (new jobs, WO jobs before first voice note). Receipt OCR + voice note capture are the fastest way to populate context on-site.

### 3.3 Two-mode extraction (both live)

```
Mode A — fromConversation
  Reads all turns for job.cellId (limit 40)
  Formats as "Customer: ...\nOperator: ..." text block
  Sends to claude-haiku-4-5 with catalogue pricing context
  Returns { items: QuoteLineItem[], notes: string }

Mode B — fromText
  Operator types: "2hrs labour, replace tap washer, silicone bath"
  Same model + catalogue context
  Items appended to draft (does not replace existing)
```

---

## 4. Receipt OCR pipeline

**Status: Not built. Self-contained, high-value.**

### 4.1 Concept

Operator is at Bunnings. Buys materials. Photos the receipt on the field app. Claude Vision reads it and outputs structured line items which are appended to the draft invoice (or quote).

### 4.2 Implementation plan

```
Camera button in QuoteEditorSheet / InvoiceEditorSheet
        │
        ▼
ImagePicker → file:// bytes (JPEG/PNG)
        │
        ▼
Claude Vision API call
  model: claude-haiku-4-5
  message: [
    { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: <b64> } },
    { type: 'text', text: 'Extract line items from this receipt...' }
  ]
  system: see §4.3
        │
        ▼
Parse JSON response → QuoteLineItem[]
  description: item name from receipt
  quantity: qty on receipt
  unit_cents: price in cents (convert from receipt $price)
        │
        ▼
_addItems(newItems)  — same method used by fromText
```

### 4.3 System prompt for receipt OCR

```
You are helping a Queensland tradesman log material purchases from receipts.

Extract each line item from the receipt and return ONLY a JSON array:
[
  { "description": "string", "quantity": 1.0, "unit_cents": 0 }
]

Rules:
- description: item name as it appears on the receipt (keep brand/model)
- quantity: amount purchased
- unit_cents: price per unit in Australian CENTS (divide receipt price by 100)
  e.g. $12.50 = 1250
- If a line is a subtotal, tax, or total — skip it, don't include it
- If quantity is not shown, assume 1
- Return an empty array if no items are readable
```

### 4.4 Files to create/modify

| File | Change |
|---|---|
| `helm/receipt_ocr_service.dart` | New — `ReceiptOcrService.fromPhoto(XFile photo)` → `List<QuoteLineItem>` |
| `helm/quote_editor_sheet.dart` | Add camera IconButton beside the AI generate card; on tap → ReceiptOcrService → _addItems |
| `pubspec.yaml` | Add `image_picker: ^1.0.0` if not already present |

### 4.5 Where it shows up

- **Quote flow:** operator visits site first, can't fully quote, but snaps a photo of any visible materials (e.g. the broken fitting) — Claude Vision describes the item and estimates cost
- **Invoice flow (primary use case):** operator is at Bunnings, photos the receipt → materials appended to draft invoice
- **WO flow:** same — no quote needed, but need to track materials for invoice

---

## 5. Quote → Invoice with variance

**Status: Invoice generation not built. Depends on Quote flow being live.**

### 5.1 The model

```
Approved Quote Document (QuoteDocument)
  · Line items: what was scoped
  · Total: agreed price baseline
        │
        ▼
Attended the job
        │
  Variances captured from conversation + field:
    · Extra work discussed on-site → REPL note / voice note → ConversationTurn
    · Additional materials → Receipt OCR → QuoteLineItem
    · Scope reduction (didn't do X) → note
        │
        ▼
Draft Invoice Document (InvoiceDocument)
  · Quote items pre-populated (baseline)
  · Variance items added (+ or -)
  · Total = baseline ± variances
  · Notes field: "per quote [ref], plus [extra work]"
        │
        ▼
Invoice sent to customer (Twilio / widget / email)
```

### 5.2 Delta tracking

Each variance item carries `source: 'quote' | 'receipt_ocr' | 'operator_note' | 'customer_request'`. This lets the invoice document be self-explaining — both operator and customer can see what was scoped vs what changed and why.

### 5.3 Implementation plan

| Step | What | Where |
|---|---|---|
| 5a | `InvoiceDocument` — mirror of `QuoteDocument` but with `baselineFromQuoteId` + `variances: List<InvoiceVariance>` | `helm/invoice_document.dart` (new) |
| 5b | `InvoiceDocRepository` — save/load per job (same pattern as `QuoteDocRepository`) | same file |
| 5c | `InvoiceEditorSheet` — fork of `QuoteEditorSheet`; opens with quote items pre-populated; receipt OCR button; AI "Generate from conversation" pulls post-quote turns only | `helm/invoice_editor_sheet.dart` (new) |
| 5d | `_doInvoice()` in `do_node.dart` — show InvoiceEditorSheet before `invoiceJob()` FSM call | `helm/do_node.dart` (modify `_doInvoice`) |
| 5e | Brain: create invoice record with total before FSM transition | `jobs_handler.zig` (modify `handleInvoice`) |

### 5.4 WO invoice path

WO jobs skip the quote entirely. `_doInvoice()` opens InvoiceEditorSheet with NO pre-populated items (empty baseline from quote). Operator adds materials (receipt OCR) + labour. Same experience, no quote baseline.

---

## 6. Customer approval loop

**Status: Not built. Depends on Twilio being provisioned.**

### 6.1 Quote approval via SMS

After quote is built and submitted:
1. Brain/operator sends SMS: "Hi [name], your quote for [job address] is $[total]. Reply YES to approve."
2. Customer replies "YES" → Twilio webhook → ConversationTurn (role: tenant, body: "YES") → brain detects approval intent → FSM: `lead → quoted`
3. Or customer replies with questions → more dialogue → revised quote

### 6.2 Invoice sent via SMS / widget

After invoice finalised:
1. SMS: "Your invoice for [job] is $[total]. Pay here: [payment link]"
2. Widget (if they have the link): shows invoice PDF

---

## 7. Implementation phases

Ordered by value and dependency. Each phase is independently shippable.

### Phase 1 — Wire turns to jobs (enables AI quote extraction to actually work)

| Task | Why first | Effort |
|---|---|---|
| **P1a** ✅ Gmail reingest writes email body as first ConversationTurn (entityRef=job.cellId) | 146 existing jobs get their initial context for free. "Generate from conversation" works on re-quote. | ~1 day — modify `reingest-worker` to call `submitTurn` after minting job cell |
| **P1b** ✅ Widget URL scheme `?j=<cellId>` — scopes widget session to job | Customer chat turns anchor to the right job. SMS → widget link = the hand-off that makes it work. | ~1 day — brain: read `?j=` query param → set entityRef; SMS includes the link |
| **P1c** ✅ Twilio incoming SMS: phone→customer→job lookup + turn write | Inbound customer replies anchor to the right job | Committed c2aa7e4 — deploy pending |

**Unlock:** After P1, "Generate from conversation" becomes genuinely useful for Quote requests that have had any customer dialogue.

### Phase 2 — Receipt OCR (standalone, high-value)

| Task | Effort |
|---|---|
| **P2a** ✅ `ReceiptOcrService` (Claude Vision → line items) | ~0.5 day |
| **P2b** ✅ Camera button in QuoteEditorSheet | ~0.5 day |
| **P2c** ✅ Camera/receipt scan button in InvoiceEditorSheet | ~0.5 day |

**Unlock:** Operator can photograph any receipt at any point and get materials line items. WO jobs especially benefit — full invoice becomes practical from the phone.

### Phase 3 — Invoice from Quote + Variance

| Task | Effort |
|---|---|
| **P3a** ✅ `InvoiceDocument` + `InvoiceDocRepository` | ~0.5 day |
| **P3b** ✅ `InvoiceEditorSheet` (fork of QuoteEditorSheet with quote pre-population) | ~1 day |
| **P3c** ✅ Wire `_doInvoice()` in `do_node.dart` to show InvoiceEditorSheet first | ~0.5 day |
| **P3d** ✅ Brain: record invoice total before FSM transition | ~0.5 day |

**Unlock:** Full invoice workflow from the field app. WO invoices + quote-variance invoices both land.

### Phase 4 — Customer approval loop (depends on Twilio provisioning)

| Task | Effort |
|---|---|
| **P4a** Provision `/var/lib/semantos/twilio.json` on rbs | ~1hr — just credentials |
| **P4b** ✅ Brain: YES-like reply from customer → job `quoted → authorized` | Committed fcc5ece |
| **P4c** ✅ "Approval request" chip in ContactConversationScreen for quoted jobs | Committed fcc5ece |

**Unlock:** Full customer-facing approval flow. Customer replies YES → job auto-authorised → operator schedules.

### Phase 5 — Voice notes ✅ (complete — commit 2a84797)

| Task | Status |
|---|---|
| Brain `voice_note_http.zig` + `voice-note-intake.ts` bun CLI | ✅ Committed |
| `POST /api/v1/voice-note` reactor route + `--oddjobz-voice-note-script` flag | ✅ Committed |
| Flutter `ConversationTurnsRepository.submitVoiceNote()` | ✅ Committed |
| `VoiceCommandSheet`: optional `jobCellId` + `turnsRepository` + anchor call | ✅ Committed |
| `JobDetailScreen`: mic button in AppBar + `openVoiceNote` callback chain | ✅ Committed |

Capture-time-bound path: operator taps mic in job view → VoiceCommandSheet records + transcribes → submitVoiceNote anchors transcript to job entityRef as ConversationTurn → appears in Thread tab.

---

## 8. What's live today (2026-05-25)

Brain deployed on `rbs` at `5de67f8f` (built 16:03 AEST, `llm complete` + `llm vision` REPL verbs live).  APK built at 16:12 AEST (90.2 MB) — **installed on device**.
All bun script flags active: `--oddjobz-voice-note-script`, `--oddjobz-conv-turns-query-script`, `--oddjobz-approve-script`.
Desktop operator console deployed at `https://oddjobtodd.info/helm/` (loom-svelte shell, attention navigation + conversation thread build).

**Brain LLM route (2026-05-25):**  
All AI calls route through the brain on `rbs`, not directly from the phone or helm.  
- Brain LLM adapter enabled: `anthropic` backend, model `claude-haiku-4-5`, `api_key_env=ANTHROPIC_API_KEY`.  
- Config at `/var/lib/semantos/llm-config.json` (owned by `semantos`, mode 640).  
- REPL verb `llm complete <scope> <b64-args>` live — verified: `POST /api/v1/repl {"cmd":"llm complete oddjobz-internal <b64>"}` → `{"text":"PONG","model":"claude-haiku-4-5-20251001","tokens_used":22}`.  
- REPL verb `llm vision <scope> <b64-args>` live — verified: `POST /api/v1/repl {"cmd":"llm vision oddjobz-internal <b64>"}` → `{"text":"I see a very small...","model":"claude-haiku-4-5-20251001","tokens_used":27}`.  
- **Flutter `QuoteExtractorService`** still calls Anthropic directly (compile-time `ANTHROPIC_API_KEY` in APK) — see remaining gap below.

| Feature | Status |
|---|---|
| DO tab — attention buckets (quote/schedule/invoice) | ✅ Live |
| DO tab — WO jobs → Schedule; outbound emails filtered | ✅ Live |
| DO tab — subtitle (address + description under each row) | ✅ Live |
| DO tab — full job payload in attention feed | ✅ Live |
| QuoteEditorSheet with line items CRUD | ✅ Live |
| AI quote generation (fromConversation + fromText) | ✅ Live |
| QuoteCatalogueService (14 default items) | ✅ Live |
| ConversationTurnsRepository (`GET /api/v1/conversation/turns`) | ✅ Live |
| Twilio SMS adapter (formatE164, sendSms, config loader) | ✅ Built — config not provisioned |
| ContactConversationScreen (operator → customer SMS) | ✅ Live — 503 until twilio.json |
| TalkDirectSearchScreen | ✅ Live |
| JobDetailScreen (full — visits, conversation, contacts) | ✅ Live |
| Gmail reingest writes email body as initial ConversationTurn (P1a) | ✅ Live |
| Widget URL `?j=<cellId>` → entityRef on turn; ContactConversationScreen pre-fills link (P1b) | ✅ Live |
| POST /api/v1/twilio/inbound: phone→customer→open-job→intake anchor (P1c, c2aa7e4) | ✅ Live |
| Brain: YES-like customer reply → quoted→authorized (P4b, fcc5ece) | ✅ Live |
| "Approval request" chip in ContactConversationScreen for quoted jobs (P4c) | ✅ Live (APK installed) |
| ReceiptOcrService — Claude Vision → QuoteLineItem list (P2a) | ✅ Live (APK installed) |
| Receipt scan card in QuoteEditorSheet edit tab — amber accent (P2b) | ✅ Live (APK installed) |
| InvoiceDocument + InvoiceDocRepository — entity_tag invoice_doc.v1 (P3a) | ✅ Live (APK installed) |
| InvoiceEditorSheet — TAX INVOICE, source chips (quote/receipt/manual), receipt OCR (P3b) | ✅ Live (APK installed) |
| InvoiceEditorSheet — AI "Generate from invoice context" pulls post-quote turns (P3b AI gen) | ✅ Live (APK installed) |
| do_node.dart _doInvoice() — seed from approved quote, show InvoiceEditorSheet, save + FSM (P3c) | ✅ Live (APK installed) |
| Brain invoice transition accepts + echoes total_cents; REPL invoice job accepts total_cents arg (P3d) | ✅ Live |
| turnsRepository + replClient threaded through CalendarScreen, SiteScreen, CustomerScreen | ✅ Live (APK installed) |
| Phase 5 — voice note → ConversationTurn: brain POST /api/v1/voice-note + bun CLI + Flutter mic button | ✅ Live |
| REPL jobs born as canonical cells: cellId = SHA-256 of cell bytes (bd727c1) | ✅ Live |
| ConversationTurn.fromJson reads identityHandle.value as identityValue (86ac094) | ✅ Live |
| Thread screen send-bar: typed operator notes → POST /api/v1/voice-note (e51cd8a) | ✅ Live (APK installed) |
| Desktop operator console at oddjobtodd.info/helm/ — jobs/customers/quotes/invoices/attention | ✅ Live |
| **Helm: attention item tap navigates to job detail (1d1f34e)** | ✅ Live — was broken (no onItemTap wired) |
| **Helm: `getById` v≠2 filter removed — ingest jobs load in JobDetailV2 (1d1f34e)** | ✅ Live — was "not found" |
| **Helm: JobDetailV2 bearer from hat-session not legacy helm.bearer key (9384811)** | ✅ Live — was silent no-bearer error post-migration |
| **Helm: per-job ConversationThread in JobDetailV2 — inbound/outbound feed + note composer (9384811)** | ✅ Live — was missing entirely |
| **Helm: auth stub has bearer paste fallback (wallet.semantos.app DNS dead) (1d1f34e)** | ✅ Live |
| **Helm: QuoteEditorInline in JobDetailV2 — list quotes + FSM actions + new-quote line-items editor with NL parser + conversation context panel (61002f0)** | ✅ Live — was Flutter-only |
| **Helm: InvoiceEditorInline in JobDetailV2 — list invoices + FSM actions + new-invoice line-items editor; auto-seeds from accepted quote draft; TAX INVOICE header; source chips (5994317)** | ✅ Live — was Flutter-only |
| **Brain LLM: `llm complete <scope> <b64-args>` REPL verb in brain; anthropic backend; `claude-haiku-4-5`; rate-limited 100 req/hr + 100K tokens/day per scope (5de67f8f, live 16:03 AEST)** | ✅ Live — smoke: `{"text":"PONG","tokens_used":22}` |
| **Helm: `QuoteEditorInline` "✨ Generate from conversation (AI)" button — loads turns on demand, builds Operator/Customer transcript, b64-encodes promptArgs, calls `llm complete oddjobz-internal`, parses `{items:[{description,quantity,unit_dollars}]}`, appends LineItems to draft (94140de)** | ✅ Live on `feat/helm-contacts-panel` — was a stub comment only |
| **Helm: `InvoiceEditorInline` same AI generation button — change-order-aware system prompt targets completed items + extra work agreed during job (94140de)** | ✅ Live on `feat/helm-contacts-panel` |
| **Flutter: `QuoteExtractorService` routes through brain `llm complete` via `ReplClient` — no ANTHROPIC_API_KEY in APK (6ea151c on feat/cell-handler-policy-runtime)** | ✅ Live — was direct Anthropic call |
| **Brain LLM: `llm vision <scope> <b64-args>` REPL verb — `VisionRequest`, `buildVisionAnthropicBody()` (multipart image+text content), `handleVision` with rate-limit + 8 MiB image cap; Anthropic-only (5de67f8f, live 16:03 AEST)** | ✅ Live — smoke: `{"text":"I see a very small...","tokens_used":27}` |
| **Flutter: `ReceiptOcrService` routes through brain `llm vision` via `ReplClient` — no ANTHROPIC_API_KEY in APK (12c4525, merged to main)** | ✅ Live (APK installed) |
| **Helm: job list `propertyAddress` for ingest v1 rows — `parseJobs` now extracts `propertyAddress`/`description` from REPL JSON; `enrichJobs` v1 path uses them as fallback (dfb6b6e on feat/helm-contacts-panel)** | ✅ Live — was showing `—` for address on ingest jobs |
| **Flutter field bugs (cb5bd67, fix/do-tab-field-bugs)**: (1) `ReplClient.send()` optional `receiveTimeout` — LLM calls 90 s, voice-note/voice-extract 60 s; fixes mic exclamation + "network error" on extract. (2) `_CommitRow` long-press → "Skip to…" bottom sheet: Quote→{Schedule,Invoice,Complete,Close}, Schedule→{Invoice,Complete,Close}, Invoice→{Complete,Close} | ✅ APK installed |

**Remaining ops tasks (not code gaps):**
- P4a: Provision `/var/lib/semantos/twilio.json` on rbs to enable outbound SMS (503 until done)

**Remaining code gaps:**
- ~~**Brain `llm vision` REPL verb**~~ — **closed + live (5de67f8f)**: `buildVisionAnthropicBody()` + `handleVision` + `llm vision <scope> <b64>` deployed on rbs 16:03 AEST.
- ~~**Flutter `ReceiptOcrService`**~~ — **closed (12c4525 on feat/cell-handler-policy-runtime)**: now calls `llm vision oddjobz-internal <b64>` via `ReplClient`; no ANTHROPIC_API_KEY in APK.
- ~~**Flutter `QuoteExtractorService`**~~ — **closed (6ea151c)**: now calls `llm complete oddjobz-internal <b64>` via `ReplClient`; no API key in APK.
- ~~**Field bug: Dio 10s timeout kills voice transcription + LLM calls**~~ — **closed (cb5bd67)**: `ReplClient.send()` now accepts optional `receiveTimeout`; LLM paths pass 90s, voice-note/voice-extract pass 60s. APK installed.
- ~~**Field bug: Do-tab over-classifies — no way to skip-ahead FSM**~~ — **closed (cb5bd67)**: long-press on any `_CommitRow` shows "Skip to…" bottom sheet; Quote bucket → Schedule/Invoice/Complete/Close; Schedule → Invoice/Complete/Close; Invoice → Complete/Close. APK installed.
- Direct "Send to customer" from the conversation thread — requires Twilio provisioning (P4a) plus wiring to `POST /api/v1/conversation/<id>/send`.
- ~~Helm job list enrichment for ingest jobs~~ — **closed (dfb6b6e)**: brain already emits `propertyAddress` in `find jobs` JSON; helm was discarding it. Now surfaces inline for v1 rows (no site-pivot link, just address text).

---

## 9. Cross-references

- **`ODDJOBZ-CONVERSATION-ARCHITECTURE.md`** — canonical turn shape (`OddjobzConversationTurn`), participant roles, surface adapter contract, SCG relation catalog, substrate deliverables (D-OJ-conv-*)
- **`ODDJOBZ-OPERATOR-FIELD-ACTIVATION-TRACKING.md`** — brain read-surface (D-OJ-OP-*), field app canonical client (D-OJ-FIELD-*), operator UI (`oddjobtodd`) activation
- **`CUSTOMER-CONV-LOOP-PLAN.md`** — Twilio adapter TDD loop (W1–W8, complete on main); Twilio config provisioning is the only remaining gap
- **`HELM-ATTENTION-SURFACE.md`** — DO tab design + FSM state → bucket mapping

---

## 10. Open decisions

| # | Question | Current default |
|---|---|---|
| OD-1 | Widget URL scheme: `/w?j=<cellId>` vs `/w/<cellId>` | `/w?j=<cellId>` (query param, easier Caddy routing) |
| OD-2 | Quote approval SMS body template — who drafts it? | Operator manually sends from ContactConversationScreen in Phase 4; auto-template is Phase 4b |
| OD-3 | Receipt OCR: single photo or multi-photo (long receipt)? | Single photo first; multi-photo is Phase 2 follow-up |
| OD-4 | Invoice variance tracking: separate `variances` list vs just another QuoteLineItem with a `source` field? | `source` field on QuoteLineItem (simpler, reuses existing type) |
| OD-5 | When does InvoiceEditorSheet auto-populate from quote? At `_doInvoice()` call, or when the invoice is first saved? | At `_doInvoice()` call — operator sees quote items pre-populated before they can edit |
| OD-6 | Twilio incoming SMS entity resolution when phone matches multiple open jobs? | Surface all open jobs to operator in ContactConversationScreen to manually anchor |
