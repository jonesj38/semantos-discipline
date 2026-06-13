---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/ODDJOBZ-CUSTOMER-CONVERSATIONS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.726113+00:00
---

# Oddjobz Customer Conversations + Lead Marketplace

**Status:** Design (2026-05-13, revised). No code yet.
**Audience:** Todd; downstream implementers.
**Outcome:** Lets customers submit leads via chat (with photos, measurements, structured fields), supports operator-initiated outreach via SMS, and produces **really well-structured job sheets** that gate quoting decisions.

> **Scope refinement (2026-05-13 evening):** the *lead-resale marketplace*
> originally specified in §11 is **deferred to a future workstream**.
> The immediate goal is structured job sheets — phases α + β + δ. The
> marketplace cell types and capabilities are kept in this doc as
> "future" so the substrate decisions made now don't preclude it.

---

## 1. Why this exists

Two problems the current substrate doesn't solve (one previously-listed marketplace concern is deferred — see scope note above):

1. **Lead capture from cold prospects.** Today, photos can only attach to a `visit` in `in_progress` state — operator-side, phone PWA only. A customer hitting `oddjobtodd.info` has no way to upload a photo, no way to describe what's broken in a structured form, no way for the operator to triage before driving out.
2. **Operator-initiated info requests.** Todd gets work orders from REAs with no photos. He wants to text the tenant with a URL, the tenant uploads on the phone, Todd never has to drive to size a part.

This doc unifies both under one substrate primitive: a **conversation cell** that ties a customer (identified by phone OR by name+address, per §3.5 intake-agent posture) to a job, with extracted structured fields. The conversation produces a *job sheet* (the operator's load-bearing artifact for quoting decisions); the operator can gate quoting on sheet completeness.

---

## 2. Identity model — phone + Twilio

Customers are NOT BRC-52 cert holders. They have no Semantos install, no Plexus account. Their identity is their phone number, verified via Twilio one-time-code.

### 2.1 Verified-session contract

```
1. Customer arrives at oddjobtodd.info chat widget
2. Widget collects phone number (E.164 format, validated client-side)
3. Brain issues Twilio Verify code (5min TTL, 5/hour rate-limit per number)
4. Customer enters code in widget
5. Brain verifies code via Twilio API
6. On success: mint customer_session cell (LINEAR, 24h TTL, refreshable)
7. Session token returned to widget; stored in browser sessionStorage
8. Every subsequent widget action carries the session token in a header
```

The session token IS the BRC-103-equivalent for unidentified actors. It binds the widget's actions to the verified phone number for its lifetime.

### 2.2 Session refresh / return-to-conversation

- **Within 24h of original verify**: session cookie still valid; widget reopens to the existing conversation, no re-verification needed.
- **>24h or different device**: customer enters phone number → fresh code → fresh session, attached to the existing conversation (looked up by phone_hash).

### 2.3 Privacy

Phone numbers are PII. Storage rules:
- `oddjobz.conversation.v1.phone_hash` = HMAC-SHA256(phone, brain_secret). Used for indexing.
- `oddjobz.conversation.v1.phone_encrypted` = AES-GCM-encrypted with the operator's DEK. Used only when sending SMS.
- Plaintext phone NEVER touches cell payload outside of the encrypted blob.
- GDPR / right-to-erasure: deleting a conversation cell triggers cascade-delete of its messages + visit cells + attachments. Operator can also export everything tied to a phone hash on request.

---

## 3. Cell types

All new cells extend the existing `extensions/oddjobz/` lexicon. Existing types (`oddjobz.job.v1`, `oddjobz.visit.v1`, `oddjobz.customer.v1`, etc.) keep their wire shape; new fields are additive.

### 3.1 `oddjobz.conversation.v1` (RELEVANT)

| Field | Type | Description |
|---|---|---|
| `id` | UUIDv4 | Stable conversation identifier (URL slug) |
| `phone_hash` | bytes(32) | HMAC-SHA256(phone, brain_secret) — for indexing |
| `phone_encrypted` | bytes(variable) | AES-GCM(phone, operator_dek) — for SMS send |
| `created_at` | u64 ms | First inbound message timestamp |
| `last_activity_at` | u64 ms | Updated on every message / attachment |
| `state` | enum | `open` / `closed` / `quarantined` |
| `current_job_id` | UUIDv4? | nullable; latest associated job |
| `tenant_domain` | string | Operator scope (e.g. `oddjobtodd.info`) |
| `entrypoint` | enum | `widget` / `sms_link` / `qr_code` / `walkin` |
| `referrer` | string? | Marketing channel hint (Meta ad id, REA name) |

**Linearity = RELEVANT** because:
- Conversations should not be silently dropped (we want a paper trail).
- Multiple jobs can reference the same conversation over time (returning customer with new problem).
- `closed` state is a write-once terminal; closed conversations remain queryable.

### 3.2 `oddjobz.customer_message.v1` (AFFINE)

| Field | Type |
|---|---|
| `conversation_id` | UUIDv4 |
| `seq` | u32 (monotonic per conversation) |
| `actor` | enum: `customer` / `intake_agent` / `operator` |
| `body` | string (≤16KB) |
| `body_kind` | enum: `text` / `voice_transcription` / `system_event` |
| `attachments` | array of visit_id references |
| `ts_ms` | u64 |

**Linearity = AFFINE** because individual messages can be dropped if a customer abandons mid-conversation; we don't need every keystroke. But once a message lands, it's immutable (K7).

### 3.3 `oddjobz.customer_session.v1` (LINEAR)

| Field | Type |
|---|---|
| `id` | UUIDv4 |
| `conversation_id` | UUIDv4 |
| `phone_hash` | bytes(32) |
| `token` | bytes(32) — random, stored hashed |
| `issued_at` | u64 ms |
| `expires_at` | u64 ms (24h from issue, or 7d for SMS-link tokens) |
| `last_seen_at` | u64 ms |
| `origin` | enum: `widget_verify` / `sms_link` |
| `consumed` | bool (becomes true on logout/expire/revoke) |

**Linearity = LINEAR** because:
- Single-use lifecycle (spend = revoke).
- Anti-replay via the K15 capability-UTXO binding (forward-looking spec shipped today).
- Each operator action that ratifies on the customer's behalf consumes the session token.

### 3.4 `oddjobz.visit.v1` — schema bump (additive)

Existing fields kept. Add:

| Field | Type | Description |
|---|---|---|
| `visit_type` | enum | `customer_submission` / `quote_visit` / `work_visit` (default `work_visit` for back-compat) |
| `conversation_id` | UUIDv4? | nullable; linked when this visit was minted from a conversation |
| `authored_by_kind` | enum | `operator_cert` / `customer_session` |
| `authored_by_id` | bytes(16) | cert_id or session_id |

`visit_type` discriminates:
- **`customer_submission`** — minted from the chat widget. Holds customer-uploaded photos, descriptions, measurements. No on-site time.
- **`quote_visit`** — operator goes on-site to assess. Optional in the FSM (some quotes are desk-only based on customer_submission visit content).
- **`work_visit`** — operator goes on-site to do the work. Can be multi-day via multiple `work_visit` cells, each with its own scheduled/in_progress/complete FSM.

### 3.5 Intake agent conversation posture

The LLM-backed intake agent runs each customer message through the extraction pipeline (§9) AND drives the conversation. Its posture is load-bearing for product quality and is captured here as the design contract.

#### 3.5.1 Core principles

1. **Anonymous chat is allowed.** The widget never blocks typing or photo uploads on identity verification. Tyre-kickers can browse and get general info.
2. **Identity capture is the primary subgoal.** The agent does NOT consider extraction "complete" until it has *a way to reference the customer for a follow-up* — either:
   - **Verified phone number** (via Twilio Verify), OR
   - **Unverified name + property address** (sufficient for a return visit / written quote / SMS lookup later)
3. **Posture is gentle, not aggressive.** The agent asks for identity opportunistically (e.g. after the customer describes a problem in enough detail that a quote becomes useful). It does *not* gate every reply on capturing identity. If the customer ignores 3 identity nudges, the agent backs off and continues providing general info until the customer is ready.
4. **No hourly rates.** The agent NEVER quotes hourly rates. Customer asks "what's your hourly rate?" → agent deflects to fixed-quote-after-assessment.
5. **Order-of-magnitude estimates are OK.** The agent can say *"this kind of job is usually 2-4 hours and around $300-600 in materials"* when the customer's description matches a known job archetype. Specific quotes require an operator-issued formal quote.

#### 3.5.2 Extraction-completeness predicate

The intake agent computes an `extraction_complete` boolean per message. It is `true` iff:

```
  ( verified_phone_present
    OR (unverified_name_present AND address_present_with_postcode) )
AND service_category != "unclassified"
AND description.length >= 50 chars
AND ( has_photos OR has_measurements OR description_unambiguous )
```

This is *separate* from the `qualification_score` of §10. `qualification_score` is the operator's gating signal (does this lead deserve a quote). `extraction_complete` is the intake agent's "did I get enough to refer back" signal — used to decide whether to keep nudging for more info or close the conversation.

#### 3.5.3 Identity-capture playbook

The agent uses a graduated approach:

| Trigger | Agent action |
|---|---|
| Customer first message | Greet, ask "what needs fixing?" — no identity ask yet |
| Customer describes problem | Ask 1-2 clarifying questions about the problem itself |
| Customer asks "how much?" or "when can you come?" | First identity nudge: "happy to give you a rough estimate — what's your suburb?" |
| Customer gives suburb but not address | Second nudge: "if you want to lock in a time I'll need a street address + a way to reach you" |
| Customer still anonymous after substantive problem detail | Third nudge: "if I send a follow-up I can text you a link to upload more photos — what's the best mobile?" |
| Customer declines 3 identity nudges | Stop nudging. Provide rough order-of-magnitude estimate. Add note in conversation: "tyre-kicker, declined identity capture" |
| Customer provides phone | Twilio Verify flow kicks in (optional — agent says "I can send a code so you can resume this chat later") |
| Customer provides name + address | Marked sufficient even without phone; operator can reach out manually |

#### 3.5.4 Rate / cost guardrails

The agent has a service-category-keyed catalog of typical-job archetypes with time + cost ranges. Stored in `/var/lib/semantos/oddjobz/rough_estimates.yaml` (operator-edited; see §9.3 for format).

When a customer asks for cost, the agent:
1. Maps the description to the nearest archetype (LLM-classified, e.g., "leaky tap" → archetype `plumbing.tap_replacement`)
2. Looks up the archetype's range (e.g., 1-2 hours, $150-300 incl. parts)
3. Replies with the range PLUS an explicit caveat: *"That's a rough order of magnitude — actual quote depends on what I see on-site / from your photos."*
4. Never says a single number (always a range)
5. Never says an hourly rate

If the customer pushes for an hourly rate explicitly:
- *"I don't quote by the hour — fixed price after a quick look. Want to upload a photo or get me out for a quick assessment?"*

If the description doesn't match any archetype (e.g., "I need 17 things done to my rental"), the agent says:
- *"That's a bigger job than I can rough-estimate — I'd need to see the list. Want to upload a list of what's needed?"*

### 3.6 `oddjobz.job_sheet.v1` (LINEAR; new)

The structured extraction of a conversation. The operator's primary artifact for the lead → qualified → quoted gating decision.

| Field | Type | Description |
|---|---|---|
| `id` | UUIDv4 | |
| `conversation_id` | UUIDv4 | Origin conversation |
| `job_id` | UUIDv4 | The job this sheet pertains to |
| `service_category` | enum | carpentry / general / handyman / multi / unclassified / out_of_scope (when customer-described work is electrical or plumbing — per operator's unlicensed scope) |
| `property_kind` | enum | residential / commercial / rental |
| `address` | encrypted bytes | Per the same DEK pattern as phone_encrypted |
| `description` | string | Operator/customer-extracted free text (LLM-summarized OK) |
| `photos` | array of visit_attachment refs | |
| `measurements` | structured key/value blob | e.g. `{cupboard_height_mm: 600, cupboard_width_mm: 400}` |
| `access` | structured | `{tenant_present: bool, work_hours: "9-5"|null, lockbox_code: encrypted?}` |
| `urgency` | enum | emergency / this_week / scheduled / flexible |
| `budget_ceiling_cents` | i64? | Customer-stated budget, nullable |
| `tenant_phone_hash` | bytes(32)? | Distinct from customer when REA work order |
| `qualification_score` | f32 | 0.0–1.0; how complete the sheet is (see §10) |
| `qualified_at` | u64 ms? | When the operator flipped this to qualified |
| `transferable` | bool | False if sheet contains operator-specific notes; true if scrubbed |

**Linearity = LINEAR** because:
- One operator owns the qualified lead.
- Selling it = spending the UTXO (per K15 capability-UTXO binding).
- The buyer mints a new sheet referencing the original; the seller's sheet is consumed.

### 3.7 `oddjobz.lead_offer.v1` (LINEAR; **FUTURE** — deferred per 2026-05-13 scope refinement)

> **Not in immediate scope.** Kept in the doc so the cell-type registry doesn't grow ad-hoc when the marketplace lands later. Implementation gated on D-Dcap-engine + operator demand.

The "for sale" listing in the lead marketplace.

| Field | Type |
|---|---|
| `id` | UUIDv4 |
| `job_sheet_id` | UUIDv4 — the sheet for sale |
| `seller_cert_id` | bytes(16) |
| `service_category` | enum (mirrors sheet) — for marketplace search |
| `geographic_postcode` | string — for marketplace search |
| `asking_price_cents` | i64 |
| `revenue_share_pct` | f32? | nullable; alternative to flat fee |
| `expires_at` | u64 ms |
| `state` | enum | `listed` / `accepted` / `expired` / `withdrawn` |

Riding the `extensions/dispatch/` envelope per chapter 29 for cross-operator federation.

---

## 4. Job FSM rework

Per the user's redesign:

```
lead → qualified → quoted → scheduled → finished → invoiced → paid
                      │
                      └─ withdrawn (terminal, scrubbed sheet listable in marketplace)
```

7 states (collapsed from the user's 9 because `quote_scheduled` and `job_scheduled` are absorbed by visit-typed Visits).

### 4.1 Transitions

- `lead → qualified` — operator (or intake_agent) flips. Requires `qualification_score >= threshold` (operator-configurable, default 0.7). See §10.
- `lead → withdrawn` — operator decides not to take it. Sheet can be listed in marketplace.
- `qualified → quoted` — quote sent to customer (price + scope + line items).
- `quoted → scheduled` — customer accepts. Spawns a `work_visit` cell (or many, multi-day).
- `scheduled → finished` — all `work_visit` cells for this job reach `complete`. Job-level transition.
- `finished → invoiced` — invoice issued (existing `oddjobz.invoice.v1`).
- `invoiced → paid` — payment confirmed.

### 4.2 Per-state photo CTAs

| Job state | Photo CTA on JobDetailScreen | Underlying mechanism |
|---|---|---|
| `lead` | "Request photos from customer" (sends SMS with URL) | Mints fresh `customer_session` token, sends Twilio SMS |
| `qualified` | "Add operator photos" | Mints `quote_visit` if not present, attaches photo |
| `quoted` | (read-only — quote already sent) | n/a |
| `scheduled` | "Schedule visit" → opens visit creator | Spawns `work_visit` |
| In `work_visit` (visit-scoped) | "Capture photo" / "GPS pin" / "Voice memo" | Existing — already wired |
| `finished` | (read-only) | n/a |

The photo CTA *moves up* in the navigation tree: customers see one in the chat widget, operators see one on the Job detail screen and a per-visit one inside each work_visit.

---

## 5. Capabilities

All in §8 Q2 partition (per `core/protocol-types/src/namespace.ts` shipped today).

### 5.1 Customer-side (Tier 3: 0x00021000–0x00021FFF — new subrange for `customer.*`)

| Cap ID | Name | Scope |
|---|---|---|
| `0x00021001` | `cap.customer.message` | Send messages in a specific conversation |
| `0x00021002` | `cap.customer.attach.photo` | Attach photos to a customer_submission visit |
| `0x00021003` | `cap.customer.attach.voice` | Attach voice transcriptions |
| `0x00021004` | `cap.customer.fill_measurement` | Set measurement fields on the job sheet |
| `0x00021005` | `cap.customer.amend_existing` | Edit messages still in `open` conversation |

These are bound to a `customer_session` LINEAR cell. Spending the session consumes the cap.

### 5.2 Operator-side (Tier 3: 0x00012000–0x00012FFF)

| Cap ID | Name | Scope |
|---|---|---|
| `0x00012001` | `cap.operator.request_customer_input` | Send SMS-link to customer for upload |
| `0x00012002` | `cap.operator.qualify_lead` | Flip job from lead → qualified |
| `0x00012003` | `cap.operator.list_marketplace` | Mint a `lead_offer` cell |
| `0x00012004` | `cap.operator.purchase_marketplace` | Accept another operator's `lead_offer` |
| `0x00012005` | `cap.operator.scrub_sheet_for_transfer` | Mark sheet as transferable after PII redaction |

### 5.3 Brain-internal

`cap.twilio.send` (Tier 1 Plexus-reserved or Tier 2 — TBD based on §11.6 GD9 audit). Bound to the operator's Twilio credentials in `/var/lib/semantos/twilio.json`.

---

## 6. Twilio adapter

New module: `runtime/semantos-brain/src/twilio_adapter.zig` (~200 LOC).

### 6.1 Capabilities

1. **Send SMS** — POST to `https://api.twilio.com/2010-04-01/Accounts/<SID>/Messages.json`
2. **Verify Start** — POST to `https://verify.twilio.com/v2/Services/<VA>/Verifications` (sends OTP)
3. **Verify Check** — POST to `https://verify.twilio.com/v2/Services/<VA>/VerificationCheck` (validates OTP)

Twilio Verify API handles rate-limiting, fraud detection, and code generation. We don't roll our own.

### 6.2 Config

`/var/lib/semantos/twilio.json`:

```json
{
  "account_sid": "ACxxx",
  "auth_token": "xxx",
  "verify_service_sid": "VAxxx",
  "sender_phone": "+61xxx",
  "default_country_code": "+61"
}
```

Loaded on `brain serve` startup. Absent → SMS/verify endpoints return 503 with `{"error":"twilio_not_configured"}`.

### 6.3 Cost model (AU pricing, 2026 estimates)

- Verify: ~$0.05 per attempt
- SMS outbound: ~$0.0075 per message
- 100 qualified leads/month × 2 verifications + 3 SMS each = ~$12.25/month per operator

Worth budgeting as a per-operator opex line.

---

## 7. Privacy / PII

### 7.1 Phone numbers

- Plaintext only in flight (over TLS to/from Twilio) and at rest in `phone_encrypted` blob (AES-GCM with operator DEK).
- All indexes / queries use `phone_hash` (HMAC-SHA256, brain_secret).
- Right-to-erasure: deleting a conversation cascade-deletes related cells AND removes plaintext from logs (audit log retains hash only).

### 7.2 Addresses

Same pattern. `phone_encrypted` + `address_encrypted` in the job_sheet; never in audit logs or marketplace listings.

### 7.3 Marketplace privacy

When a `job_sheet` is listed for sale (`lead_offer.v1`), the seller MUST call `cap.operator.scrub_sheet_for_transfer` first. Scrubbing:
- Replaces customer phone with a brokered call-forward identifier (Twilio Proxy session — buyer can call without seeing the real number until purchase completes)
- Replaces address with postcode + suburb only
- Strips operator-specific notes
- Preserves photos, measurements, service category, urgency, budget hints

Buyer sees enough to bid; full PII only released on purchase confirmation.

---

## 8. UI surfaces

### 8.1 Customer chat widget (NEW — at `oddjobtodd.info/chat`)

Existing capability `cap.oddjobz.public_chat_serve` indicates the widget is partially scaffolded. This design assumes it needs major rework.

Web UI (HTML/JS, served by brain via existing site config; no Flutter):

```
┌───────────────────────────────────────────┐
│ Odd Job Todd                              │
│                                           │
│ Hi! What needs fixing?                    │
│ ┌─────────────────────────────────────┐   │
│ │ (customer types here)               │   │
│ └─────────────────────────────────────┘   │
│ [📷 Add photo] [📍 Share location] [🎤]   │
│                                           │
│ Your number: +61___ ___ ___    [Verify]   │
│                                           │
│ ┌─ Existing conversation? ─────────────┐  │
│ │ Resume an earlier chat               │  │
│ └──────────────────────────────────────┘  │
└───────────────────────────────────────────┘
```

State machine:
1. Anonymous — typing + photo upload allowed; can't submit
2. Phone entered → Verify clicked → Twilio code sent
3. Code entered → session minted → submit becomes available
4. Submitted → conversation cell minted → URL bookmarkable (?conv=<uuid>) for return

### 8.2 Operator Flutter — JobDetailScreen update

Add CTAs scoped by current job state:

- `lead`: "Request more from customer" button (mints SMS-link session, sends Twilio SMS with URL)
- `lead` or `qualified`: "Schedule quote visit" button (creates quote_visit Visit)
- `qualified`: "Send quote" button (existing)
- `scheduled`: "Schedule work visit" button (creates work_visit Visit; can repeat for multi-day)
- All states: "Conversation" tab showing the message log + photos from customer side

### 8.3 Operator Flutter — Marketplace screen (NEW)

- "My listings" tab: my `lead_offer` cells, their states
- "Browse" tab: other operators' listings filtered by my service category + geo
- "List a lead" flow: pick a job in `withdrawn` state → scrub → set price → publish

---

## 9. Structured job sheet — extraction pipeline

The conversation produces structured fields that fill `oddjobz.job_sheet.v1`. Extraction happens via the intake_agent (LLM-based) running on the brain when the customer's session is active.

### 9.1 Extraction stages

Each customer_message triggers an extraction pass:

1. **Phone+address parsing** (regex + libphonenumber) — fills `phone_*` and `address_*` fields when matched
2. **Service category classifier** (LLM, structured-output) — maps free-text description → service_category enum
3. **Measurement parser** (regex + LLM disambiguation) — "the cupboard is 600 tall and 400 wide" → `{cupboard_height_mm: 600, cupboard_width_mm: 400}`
4. **Urgency classifier** (LLM keyword extraction + structured output) — "asap please" → `emergency`
5. **Budget extractor** (regex + LLM) — "$500 max" → `budget_ceiling_cents: 50000`
6. **Access constraint parser** (LLM structured output) — "tenant home weekdays" → `{tenant_present: true, work_hours: "9-5 weekdays"}`

All stages run in sequence on each new message; results overwrite the corresponding field in the job_sheet. Customer can amend via subsequent messages.

### 9.2 Extraction-completeness predicate

After each pass, the intake agent computes `extraction_complete` per the predicate defined in §3.5.2:

```
  ( verified_phone_present
    OR (unverified_name_present AND address_present_with_postcode) )
AND service_category != "unclassified"
AND description.length >= 50 chars
AND ( has_photos OR has_measurements OR description_unambiguous )
```

This drives the intake agent's conversation behaviour:
- **`false`** → agent applies the §3.5.3 identity-capture playbook (graduated nudges, gentle posture, backs off after 3 declines)
- **`true`** → agent stops nudging; signals to operator-side UI that the sheet is ready for triage

Note this is *separate* from §10's `qualification_score`:
- `extraction_complete` is the intake agent's "did I get enough to refer back" signal.
- `qualification_score` is the operator's "does this lead deserve a quote" signal.
- A conversation can be `extraction_complete = true` but `qualification_score = 0.4` if (say) the customer's job is outside the operator's service categories.

### 9.3 Rough-estimate catalog

When the customer asks for cost or duration, the agent uses a service-category-keyed catalog rather than computing per-customer:

**Operator's licensed scope drives the seed catalog.** Todd's
operator profile (2026-05-14) explicitly excludes electrical and
plumbing — he is not licensed for either, and the agent must not
quote those categories under any circumstance. The seed catalog
covers carpentry, handyman, and general only. If a customer
describes electrical or plumbing work, §3.5.4 applies: the agent
declines the quote path and either (a) refers out (if a referral
partner is configured) or (b) closes the conversation politely
without a price range.

```yaml
# /var/lib/semantos/oddjobz/rough_estimates.yaml — operator-edited
service_category: carpentry
archetypes:
  - name: cupboard_door_replacement
    keywords: ["cupboard door", "kitchen door", "wardrobe door"]
    hours_low: 1.0
    hours_high: 2.0
    materials_low_cents: 8000   # $80
    materials_high_cents: 20000 # $200
    notes: "standard hinge, customer-supplied or off-the-shelf door"
  - name: shelving_install
    keywords: ["shelf", "shelving", "bracket"]
    hours_low: 1.0
    hours_high: 2.5
    materials_low_cents: 4000   # $40
    materials_high_cents: 15000 # $150
    notes: "wall-fixed; customer-supplied or off-the-shelf shelf"

service_category: general
archetypes:
  - name: door_adjustment
    keywords: ["door sticks", "door won't close", "hinge"]
    hours_low: 0.5
    hours_high: 1.0
    materials_low_cents: 0
    materials_high_cents: 3000  # $30
    notes: "plane / shim / re-screw; no door replacement"

service_category: handyman
archetypes:
  - name: tv_wall_mount
    keywords: ["tv mount", "wall mount", "tv bracket"]
    hours_low: 1.0
    hours_high: 2.0
    materials_low_cents: 0      # customer supplies bracket typically
    materials_high_cents: 8000  # $80
    notes: "stud-finder + 4 anchors; customer supplies TV bracket"
```

(Painting + flooring archetypes land as a follow-up once Todd
confirms the per-square-metre rate-card model fits.)

When the customer asks "how much?", the agent:
1. Maps description → nearest archetype (LLM classifier with `keywords` as hints)
2. Replies: *"That's usually a {hours_low}-{hours_high}-hour job, around ${materials_low_dollars}-{materials_high_dollars} in materials. **Rough estimate only — actual quote depends on what I see on-site or from photos.**"*
3. Uploads the archetype reference into the job_sheet's `extracted_archetype` field (for operator review)

Hard rule per §3.5.4: no hourly rate ever appears in the response.

### 9.4 Auditability (BRC-122 ARIA binding)

Per §11.6 of the unification roadmap, the LLM extraction layer binds to BRC-122 ARIA:

- `EPOCH_OPEN` commits the LLM model version on-chain at brain startup
- Each extraction call hashes (input, output) into a Merkle tree
- `EPOCH_CLOSE` seals the batch every ~1.5s
- Cost: ~$2/year continuous

This gives every extracted field a cryptographic provenance: "this measurement was extracted from message-id X by model M at timestamp T". Important when the lead is sold (buyer can verify the seller didn't fabricate measurements) — relevant when the marketplace lands as a future workstream.

---

## 10. Qualification gating

The operator (Todd) configures a qualification rubric. The intake_agent applies it; the operator can override.

### 10.1 Default rubric (configurable per-operator)

```yaml
qualification:
  required_fields:
    - service_category
    - description
    - address.postcode  # geo for routing
    - at_least_one_photo OR at_least_one_measurement
  scoring:
    has_phone_verified: 0.30
    has_address: 0.20
    has_service_category: 0.15
    has_photos: 0.15
    has_measurements: 0.10
    has_budget: 0.05
    has_urgency: 0.05
  threshold: 0.70  # min score to qualify
  geo_filter:
    operator_home: "-37.8136,144.9631"  # operator's coords
    max_distance_km: 50  # outside = auto-withdraw
  service_category_filter:
    accepted: [carpentry, general, handyman]
    rejected: [electrical, plumbing]  # operator not licensed for either
```

Stored as `oddjobz.qualification_rubric.v1` (PERSISTENT cell — long-lived, edited via REPL or settings UI).

### 10.2 Gating flow

```
Customer submits conversation → intake_agent fills job_sheet
intake_agent computes qualification_score
  If score >= threshold AND in geo + service filter:
    Job auto-transitions: lead → qualified
    Operator gets notified via push (T6 hooks up!)
  Else:
    Job stays in `lead`
    Operator sees "Needs more info" badge
    Operator can: send follow-up SMS (cap.operator.request_customer_input)
                  OR withdraw + list in marketplace
                  OR manually override + qualify anyway
```

---

## 11. Lead resale marketplace (FUTURE — deferred)

> **Status:** Deferred per 2026-05-13 scope refinement. This section
> remains in the design doc so the cell types (§3.7 lead_offer), the
> capabilities (`cap.operator.list_marketplace`, `purchase_marketplace`,
> `scrub_sheet_for_transfer`), and the federation transport choice
> are pinned now and don't drift. Implementation gated on (a) the
> immediate phases α/β/δ landing and (b) operator demand for resale.

The economic layer on top of withdrawn-but-clean job sheets.

### 11.1 Flow

```
Operator A:
  Has job in `lead` state, qualified by intake_agent (score 0.82)
  Decides not to take (wrong service, too far, etc.)
  Triggers: job → withdrawn
  Calls cap.operator.scrub_sheet_for_transfer
    → PII redacted; address → postcode only
    → Customer phone → Twilio Proxy session token
  Calls cap.operator.list_marketplace
    → Mints oddjobz.lead_offer.v1
    → Listing rides extensions/dispatch envelope to federation peers
    → Asking price: $25 (configurable)

Operator B:
  Browses marketplace, sees the offer
  Calls cap.operator.purchase_marketplace(offer_id)
    → Spends a payment cell (BRC-120 x402 settlement — per §11.6 axis G)
    → Receives the scrubbed job_sheet + Twilio Proxy session
    → Mints a NEW oddjobz.job.v1 in `qualified` state on their brain
    → Calls customer via the Proxy session (Twilio hides A's number from B and vice versa)

Customer:
  Receives the call from Operator B
  Doesn't see operator B's real number (Proxy hides)
  Doesn't know they were "sold" — it's a referral from their perspective
  Books work with B
```

### 11.2 Why this works on the substrate

- **K15 capability-UTXO binding** (forward-looking spec from today): the job_sheet IS a capability UTXO. Spending it = transferring ownership.
- **K1 linearity**: a job_sheet can be spent exactly once. Two operators can't buy the same lead.
- **Chapter 29 dispatch envelope**: cross-operator transfer is the federation primitive.
- **BRC-79 (Token Exchange Protocol)**: the marketplace listing/bidding is BRC-79 over the federation transport.
- **BRC-120 (x402)**: the payment is BRC-120-gated — Operator B's purchase is settlement-confirmed before the sheet transfers.
- **BRC-122 (ARIA)**: the LLM extractions in the sheet have on-chain provenance — Operator B can verify the measurements weren't fabricated.

### 11.3 Revenue share (alternative to flat fee)

Operator A can list with `asking_price_cents: 0` + `revenue_share_pct: 0.15`. Operator B pays nothing upfront; if the job completes (`finished → invoiced → paid`), 15% of revenue routes back to A via MFP metered channel (existing `extensions/metering/`). Lower friction for B, aligned incentives.

---

## 12. Build plan / phases

Realistic phasing. Each phase ships a working slice. Marketplace (phase γ) is **deferred**; phases α + β + δ produce well-structured job sheets, which is the immediate goal.

### Phase α — Conversation substrate

Goal: customer-side photo upload via chat widget; operator sees photos on job detail. Identity capture optional but recommended by the intake agent.

- α.1 — `oddjobz.conversation.v1` + `customer_message.v1` + `customer_session.v1` cells defined and tested
- α.2 — `oddjobz.visit.v1` schema bump (additive: `visit_type`, `conversation_id`, `authored_by_*`)
- α.3 — `twilio_adapter.zig` with Verify + SMS (~200 LOC + tests)
- α.4 — Brain endpoints: `POST /api/v1/customer-conversation/start` + `POST /api/v1/customer-conversation/verify` + `POST /api/v1/customer-conversation/<id>/message` + `POST /api/v1/customer-conversation/<id>/attach`
- α.5 — Customer chat widget HTML+JS, served by brain via site config. **Allows anonymous browsing.** Identity capture is opportunistic (per §3.5).
- α.6 — JobDetailScreen update: "Conversation" tab + "Request more from customer" button

Estimate: 3 weeks.

### Phase β — Structured extraction + qualification

Goal: conversations produce filled job_sheets; intake agent applies §3.5 conversation posture (gentle identity capture, no hourly rates, archetype-based rough estimates); operator sees a complete sheet ready for the quote decision.

- β.1 — `oddjobz.job_sheet.v1` + `qualification_rubric.v1` cells defined
- β.2 — Extraction pipeline: regex stages + LLM stages over each customer_message (per §9.1)
- β.3 — Intake agent posture engine implementing §3.5 (identity-capture playbook, no hourly rates, archetype-based estimates from §9.3)
- β.4 — `rough_estimates.yaml` catalog format + initial seed for electrical/plumbing/carpentry/general
- β.5 — `extraction_complete` predicate computation per message (§9.2)
- β.6 — BRC-122 ARIA binding for LLM extraction provenance
- β.7 — Qualification scorer + auto-transition logic (§10)
- β.8 — JobDetailScreen: extraction-complete badge + qualification-score badge + "Needs more info" CTA

Estimate: 4-5 weeks (added 1w buffer for the intake agent posture work — it's the load-bearing UX piece).

### Phase δ — REA work-order flow

Goal: Todd messages a tenant directly with an SMS-link to upload photos. Can run in parallel with α.

- δ.1 — `oddjobz.job.v1` schema: `tenant_phone_hash` field (REA work-order pattern)
- δ.2 — Operator-side "Request from tenant" button mints sms_link session (7d TTL)
- δ.3 — SMS template: "Hey {tenant_name}, {operator_name} here — upload photos: {url}"
- δ.4 — Widget supports landing directly into a specific conversation with pre-filled context

Estimate: 1 week.

### Phase γ — Marketplace (DEFERRED)

> Not in immediate scope. Kept in this doc (§11) as a future workstream so the substrate decisions made now don't preclude it. Will land when α/β/δ are in production AND operator demand surfaces.

### Total immediate scope

α + β + δ = **8-9 weeks** to a substrate that produces really well-structured job sheets, with a chat widget that allows anonymous browsing but steers toward identity capture, and operator-initiated SMS outreach.

---

## 13. Open questions

### Resolved (2026-05-13 evening)

- **R1. Anonymous browsing allowed?** ✅ Yes. The widget never blocks typing or photo uploads on identity verification. Tyre-kickers can browse and get rough-estimate info without verifying. (Original Q4 — resolved by Todd's product call: "they can chat anonymously but it should really try to get a phone number or name and address out of them".)
- **R2. Identity capture posture?** ✅ Gentle, not aggressive. §3.5.3 playbook: 3 graduated nudges, then back off. The agent's `extraction_complete` predicate (§9.2) is the internal "got enough to refer back" signal — phone-verified OR (name + address).
- **R3. Hourly rates?** ✅ Never. The agent declines hourly-rate questions and deflects to fixed-quote-after-assessment. Order-of-magnitude ranges per §9.3 archetype catalog ARE allowed.
- **R4. Marketplace in immediate scope?** ❌ Deferred. Phase γ moves to "future workstream"; cell types kept in §3.7 + §11 so the substrate decisions don't drift when it lands later. (Original Q3 — resolved by scope refinement.)

### Still open

1. **Twilio number per operator vs. shared sender?** Per-operator is cleaner identity-wise (the customer sees Todd's brand) but adds setup friction. Shared sender (`+61...`) is simpler but blurs operator identity. **Recommendation:** per-operator from day one; setup is just paste a number+SID during onboarding.

2. **Customer "logged out" UX:** if a customer's 24h session expires while typing, do we save the draft? **Recommendation:** yes — draft state in `customer_message.v1` with `state: draft` until a verified session ratifies it.

3. **Voice path:** customers leaving voice notes via the widget. **Recommendation:** Phase α handles text + photo only; voice as a Phase α.2 follow-up. The brain's existing `voice-extract` endpoint can serve here unchanged.

4. **Multi-tenancy edge case:** what if a customer's number is associated with conversations across multiple operators (e.g., Todd AND another tradie)? **Recommendation:** `phone_hash` is HMAC'd with each operator's brain_secret, so cross-operator linkage is impossible — each operator sees their own conversations only.

5. **Archetype catalog ownership:** does the operator hand-curate `rough_estimates.yaml` or is there a seed catalog per service category? **Recommendation:** ship a seed catalog (electrical / plumbing / carpentry / general) with ~10 archetypes each in §9.3 format; operator edits via REPL or a future settings UI.

6. **What if customer asks for an hourly rate AND tries to negotiate?** Per §3.5.4 the agent says *"I don't quote by the hour — fixed price after a quick look."* but customers may persist. **Recommendation:** the agent has a "deflection ceiling" of 2 attempts; after that, it offers to text the operator directly with the customer's question. Avoids the LLM getting argumentative.

---

## 14. Dependencies on other §11 deliverables

This design composes with the §11 unification work:

- **K15 capability-UTXO binding** (forward-looking Lean+TLA+ spec shipped today) — job_sheets, lead_offers, customer_sessions are all LINEAR cells riding K15.
- **BRC-122 ARIA** (§11.6 binding) — LLM extraction provenance.
- **BRC-120 x402** (§11.6 OD-BRC-2) — marketplace payment settlement.
- **BRC-79 Token Exchange** (§11.6 Tier 3) — marketplace listing/bidding wire format.
- **extensions/dispatch** (chapter 29) — cross-operator transfer transport.
- **§8 Q2 namespace** (`core/protocol-types/src/namespace.ts` shipped today) — Tier 3 capability allocations for the new `cap.customer.*` and `cap.operator.*` families.
- **D-Dlex-voice** (§11.2 deliverable) — when the intent pipeline lands, the conversation → job_sheet extraction sits naturally on the NL→SIR path.

---

## 15. Sources referenced

- `extensions/oddjobz/` — existing job + visit + customer cell types
- `extensions/oddjobz/README.md` — eight canonical cell types
- `extensions/dispatch/` — federation envelope (chapter 29)
- `extensions/metering/` — MFP channels for revenue share
- `core/protocol-types/src/namespace.ts` — Tier 1/2/3 capability partition
- `docs/prd/UNIFICATION-ROADMAP.md` §11.2 (D-Dcap-engine, K15, K17 forward-looking specs)
- `docs/prd/UNIFICATION-ROADMAP.md` §11.6 (BRC-108/115/120/122 bindings)
- `docs/operator-runbooks/pwa-v1-pilot-checklist.md` §V1 Test 2 (post-correction)
- Memory `brain_auth_model_intent.md` (BRC-52 cert+capability+Plexus-challenge model; this design extends it to phone+Twilio for unidentified customers)
- Memory `shell_cartridges_hats_model.md` (PWA shell-cartridges-hats; the chat widget is a web-side cartridge, customers wear no hat)
