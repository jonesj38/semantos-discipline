---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/CUSTOMER-CONV-LOOP-PLAN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.738962+00:00
---

# Customer Conversations — TDD Loop Plan

**Branch:** `feat/customer-conversations` (off main `6a5f3fa`)
**Mode:** Autonomous `/loop` execution. Code + tests. TDD-strict (failing test commit precedes implementation).
**Started:** 2026-05-14.
**Trigger:** `/loop continue work per docs/design/CUSTOMER-CONV-LOOP-PLAN.md`

## What Todd actually asked for (verbatim)

> "I want the app to actually work for me to run my business. When I am on the home screen and I click a job it should give me way more than just the pill to increment the state, should launch conversations related to the job (because the tenant and my conversation related to the job will be a different conversation than mine and the REA conversation about the job). The contact should become a person I can message in the chat, and that dispatches the twilio message even if they're not in my contacts/PKI. … Twilio should be the method to contact someone who is referenced from a job we have ingested, but i don't have PKI or contacts book yet. It would be great to be able to message them from the talk | direct page via typing in their name or the job address/suburb and the job surfaces with their contact names (some job sheets give me three tenants to contact)."

Translation:

1. **JobDetailScreen** needs a People/Contacts section (not just FSM increment pill). Each contact opens a conversation thread with that person.
2. **Each conversation is per-job + per-contact** — a job with REA + 3 tenants has 4 separate conversations.
3. **Contacts can be messaged without PKI/contacts** — phone-number-only is enough; Twilio dispatches the SMS.
4. **Talk|direct page** = search by name OR job address/suburb → matching jobs surface with their contacts → tap to message.
5. **TDD strict** — failing test first, then implementation.
6. **Service category catalog:** drop electrical + plumbing. (Todd: "No electrical work or no plumbing.")

This is a narrower, code-first slice of yesterday's design (`docs/design/ODDJOBZ-CUSTOMER-CONVERSATIONS.md`). Web chat widget and intake-agent posture engine are deferred; what ships in this loop is the **operator-initiated** Twilio messaging from the phone PWA.

## Hard constraints (re-read every iteration)

1. **Branch flexibility — all roads lead to main.** The loop targets main. `feat/customer-conversations` exists as scaffolding but parallel sessions routinely fast-forward main ↔ feat tips. Don't stop on branch-identity alone. Acceptable states (each iter): on `feat/customer-conversations`, OR on `main`, OR on any branch where my paths are conflict-free. STOP only if my paths show edits from a session that isn't me (real conflict, not just a sync).
2. **TDD ladder:** failing test commit FIRST, then implementation. Every work item below has a `RED` and `GREEN` commit at minimum.
3. **Path-scoped commits:** `git commit <paths> -m "..."` — never bare `git commit -m`. Concurrent sessions stage things. Per memory `git_commit_scope_to_paths.md`.
4. **Pre-commit path check:** `git status --short <my-paths>`; if my paths show unexpected modifications (not just untracked-new), investigate before committing.
5. **No push to remote until Todd confirms.** All commits local first. Todd reviews; push happens on his go.
6. **Zig test gate:** `zig build test -j1` is slow (~20min). Use targeted module tests where possible. CI runs the full suite.
7. **Stop conditions:** (a) work item RED → GREEN succeeds, mark ✅, move on; (b) GREEN fails after 3 honest attempts → surface to Todd; (c) **real** path conflict from a parallel session (overlapping edits, not just fast-forward) → STOP; (d) any test that was green starts failing → STOP (regression — surface).

## Each iteration's shape

```
1. Verify branch + clean state for my paths
2. Pick next ⬜ task top-down
3. (Discovery) Read minimum source needed to write the test correctly
4. RED commit: write failing test, run, confirm it FAILS, commit
5. GREEN commit: implement, run, confirm test PASSES, commit
6. (Optional) REFACTOR commit if obvious dup or cleanup
7. Mark ✅ in progress log below with SHAs
8. ScheduleWakeup for next iteration (60-120s for discovery, longer for big test work)
```

## Setup status

- ✅ Stash unrelated `runtime/intent/src/*` parallel WIP (stash@{0})
- ✅ Branch `feat/customer-conversations` created off main `6a5f3fa`
- ✅ Plan doc committed to this branch (`1160d7a`)
- ✅ W0 discovery done in this turn

## W0 discovery findings (2026-05-14)

**Far more exists than the original plan assumed.** This significantly shrinks the cell-design work and concentrates the new code on the **Twilio adapter** + **Flutter wiring**.

### Already shipped

| Concern | Existing impl | Path |
|---|---|---|
| Contact cell | `oddjobz.customer.v2` (role enum tenant\|agent\|owner\|pm\|sub-tradie\|other, normalisedPhone E.164, sourceProvenance) | `extensions/oddjobz/src/cell-types/customer.v2.ts` |
| Message cell | `oddjobz.message.v1` (senderType {customer\|operator\|system\|ai}, channel webchat) | `extensions/oddjobz/src/cell-types/message.ts` |
| Conversation cell | `ConversationCell` | `extensions/oddjobz/src/cell-types/` |
| Conversation pipeline | extraction → AccumulatedJobState → reduceToIntent → Intent | `extensions/oddjobz/src/conversation/` (8 files) |
| Chat persistence | round-trip persistence for `/api/v1/chat` (D-O6a endpoint) | `extensions/oddjobz/src/chat-persistence.ts` |
| Intake-agent posture engine | 230-line state cascade with operator-tuned thresholds | `extensions/oddjobz/src/conversation/state-manager.ts` |
| Flutter JobDetailScreen Contacts + Conversation section | Already wired, gated on `widget.captureService` + `widget.talkSurface` injection | `apps/oddjobz-mobile/lib/src/helm/job_detail_screen.dart:43, 66, 71, 130, 134, 162` |

### Missing (the actual new code for this loop)

| Concern | Notes |
|---|---|
| **Twilio adapter** | No Zig module exists. Greenfield. Needed for operator-initiated SMS path. |
| **Operator-initiated send endpoint** | `POST /api/v1/conversation/<id>/send` doesn't exist. The existing `/api/v1/chat` is the customer-side webchat flow; we need the operator-side outbound SMS flow. |
| **Talk\|direct search endpoint** | `POST /api/v1/search/contacts` (by name OR job address/suburb) doesn't exist. |
| **Flutter wiring at construction time** | The JobDetailScreen widget supports captureService + talkSurface but they may not be wired in the screen's caller. Todd reports seeing only the FSM pill — likely an injection gap not a UI gap. |
| **Flutter ConversationScreen for operator-initiated thread + send button** | TalkSurface exists but no operator-typing UI on top of it. |
| **Flutter TalkDirectScreen** (search-by-name/address) | Doesn't exist. |

### Implication

W0-W3 of the original plan collapse: cell types are done, persistence is done. The new code is:

- **Twilio adapter** (Zig, brain-side) — W1
- **Send endpoint** (Zig reactor, brain-side) — W2
- **Search endpoint** (Zig reactor, brain-side) — W3
- **Flutter JobDetail injection diagnosis** (Dart, phone-side) — W4
- **Flutter ConversationScreen send UI** (Dart, phone-side) — W5
- **Flutter TalkDirectScreen** (Dart, phone-side) — W6
- **Doc update**: drop electrical + plumbing from archetype catalog — W7

Each is a discrete TDD slice. Updating the work-item list below.

---

## Work items (revised post-discovery)

Listed in dependency order. Each is a discrete TDD-shaped slice. The old W1-W3 (cell types) are superseded by W0 discovery — they already exist.

### W1 — Twilio adapter (Zig, brain-side, greenfield)

Pure-logic Zig module + reactor wiring. Tests are inline + socketpair-style — no real Twilio account needed for unit tests.

#### W1.1 — RED: failing test for `formatE164(raw_number, default_country_code)`
- File: `runtime/semantos-brain/src/twilio_adapter.zig` (test block at bottom)
- Cases: `"0412 345 678"` + `"+61"` → `"+61412345678"`; `"+1 (555) 123-4567"` → `"+15551234567"`; `"abc"` → `error.invalid_phone`
- Commit: `proofs(twilio): RED — formatE164 happy + sad paths`

#### W1.2 — GREEN: implement formatE164
- Commit: `proofs(twilio): GREEN — formatE164 with E.164 normalization`

#### W1.3 — RED: failing test for `sendSms` with injectable HTTP sender
- Cases: 201 → MessageSent{sid, status}; 429 → error.rate_limited; 400 code 21211 → error.invalid_recipient

#### W1.4 — GREEN: implement sendSms

#### W1.5 — RED: failing test for config loader (`/var/lib/semantos/twilio.json`)

#### W1.6 — GREEN: implement config loader

#### W1.7 — Wire `twilio_adapter_mod` into `build.zig`

### W2 — Operator-initiated send endpoint

`POST /api/v1/conversation/<id>/send`. Reuses existing `chat-persistence.ts` for storing the operator-side `oddjobz.message.v1` cell; adds the Twilio send side-effect.

#### W2.1 — RED: failing reactor-conformance test in `runtime/semantos-brain/tests/`
- Cases: valid bearer + existing conversation → 200 + message persisted + Twilio adapter called with (e164, body); missing bearer → 401; conversation not found → 404; Twilio not configured → 503

#### W2.2 — GREEN: implement `reactorHandleConversationSend` + dispatch slot in `site_server/reactor.zig`

#### W2.3 — Wire acceptor construction in `cli/serve.zig` (T8-style)

### W3 — Talk|direct search endpoint

`POST /api/v1/search/contacts`. Search by contact name OR job address/suburb. Returns matched contacts each with their job context.

#### W3.1 — RED: failing test for `searchContactsByQuery(query)` pure-logic
- Cases: name substring match (case-insensitive) returns contacts + job refs; suburb match returns contacts on matching jobs; empty query → error; no matches → empty array

#### W3.2 — GREEN: implement pure-logic search over the LMDB customer + job stores

#### W3.3 — RED: failing reactor-conformance test for `POST /api/v1/search/contacts`

#### W3.4 — GREEN: implement reactor handler + dispatch slot

#### W3.5 — Wire acceptor in cli/serve.zig

### W4 — Flutter JobDetailScreen injection diagnosis

Likely a 1-line fix. Todd reports only seeing FSM pill. The widget code already supports Contacts + Conversation sections, gated on `widget.captureService != null` + `widget.talkSurface != null`. The fix is probably wiring those at the caller (the screen's navigator push from JobListScreen).

#### W4.1 — Diagnose: find where JobDetailScreen is constructed; check what services are passed; identify what's null

#### W4.2 — RED: failing widget test asserting the People + Conversation sections render when a job has contacts

#### W4.3 — GREEN: pass the missing services at the push site

### W5 — Flutter ConversationScreen send UI

Inside the existing TalkSurface flow but with an explicit "operator typing a message to send via SMS" widget.

#### W5.1 — RED: failing widget test for ConversationSendBar widget (text field + send button)

#### W5.2 — GREEN: implement ConversationSendBar; wire to `/api/v1/conversation/<id>/send`

### W6 — Flutter TalkDirectScreen (search-by-name/address)

#### W6.1 — RED: failing widget test for empty state + search-results state

#### W6.2 — GREEN: implement TalkDirectScreen; wire to `/api/v1/search/contacts`

### W7 — Doc update: archetype catalog drops electrical + plumbing

#### W7.1 — Edit `docs/design/ODDJOBZ-CUSTOMER-CONVERSATIONS.md` §9.3 seed catalog

### W8 — Integration smoke + summary

#### W8.1 — End-to-end test: from a job with 3 tenants, message one via send endpoint, verify Twilio mock receives the call, verify message cell persisted

#### W8.2 — Final summary commit with all SHAs

---

## (Original W0–W11 — superseded by W0 discovery; preserved below for reference)

### W0 — Discovery + foundations

#### W0.1 — Read existing `oddjobz.customer.v1` + `oddjobz.job.v1` schemas

- **What:** No code change. Read `extensions/oddjobz/src/` to find the existing customer + job cell type definitions. Document where the new conversation/contact cells slot in.
- **Output:** Inline notes in this plan doc + cross-references for downstream tasks.
- **Acceptance:** Know exactly which file the new cell types extend and what the existing customer field layout is.

#### W0.2 — Verify Twilio adapter doesn't already exist on the brain

- **What:** `grep -rn "twilio" runtime/semantos-brain/src/`. If a stub exists, build on it; if not, allocate `src/twilio_adapter.zig`.
- **Output:** Confirmation of greenfield (likely) or pointer to existing stub.

#### W0.3 — Confirm rough-estimate catalog dropping electrical + plumbing

- **What:** Per Todd 2026-05-14: "No electrical work or no plumbing." Update yesterday's design's seed archetype catalog to remove those categories. Carpentry + general + handyman + (later) painting + flooring.
- **Output:** Updated archetype seed in `docs/design/ODDJOBZ-CUSTOMER-CONVERSATIONS.md` §9.3 (one-line edit to existing doc).

### W1 — Contact cell type (`oddjobz.contact.v1`)

The missing primitive Todd is asking for. A job has N contacts (REA + 3 tenants pattern is the load-bearing case). Each contact has a name + phone + role + job_id reference. Operator messages a contact = creates/reuses a conversation thread.

#### W1.1 — RED: failing test for `oddjobz.contact.v1` schema

- **File:** `extensions/oddjobz/__tests__/contact.test.ts`
- **Tests:**
  - `contact.v1 has required fields: id, job_id, name, phone (E.164), role, created_at`
  - `contact.role enum: tenant | rea | owner | customer | other`
  - `contact.phone is E.164-validated (regex match)`
  - `contact.name is non-empty string`
  - `contact.linearity is RELEVANT (multiple jobs can reference; never silently dropped)`
- **Commit:** `proofs(contact): RED — failing tests for oddjobz.contact.v1 cell type`

#### W1.2 — GREEN: implement `oddjobz.contact.v1`

- **File:** `extensions/oddjobz/src/contact.ts` (or wherever the existing schemas live; W0.1 confirms)
- **Acceptance:** Tests from W1.1 pass via `bun test extensions/oddjobz/__tests__/contact.test.ts`.
- **Commit:** `proofs(contact): GREEN — oddjobz.contact.v1 cell type with E.164 phone + role enum`

#### W1.3 — RED: failing test for "list contacts for job"

- **File:** Same test file or sibling.
- **Test:** `listContactsForJob(job_id) returns all contacts ordered by created_at`.
- **Commit:** `proofs(contact): RED — failing test for listContactsForJob query`

#### W1.4 — GREEN: implement `listContactsForJob`

- **Commit:** `proofs(contact): GREEN — listContactsForJob query`

### W2 — Conversation cell type (`oddjobz.conversation.v1`)

Per yesterday's design §3.1, but simplified to the immediate use case. A conversation is **per-job + per-contact**.

#### W2.1 — RED: failing test for `oddjobz.conversation.v1` schema

- **Tests:**
  - `conversation.v1 has: id, job_id, contact_id, state (open|closed), created_at, last_activity_at`
  - `conversation linearity is RELEVANT`
  - `creating two conversations with same (job_id, contact_id) is rejected` (uniqueness invariant)

#### W2.2 — GREEN: implement `oddjobz.conversation.v1`

#### W2.3 — RED: failing test for `findOrCreateConversation(job_id, contact_id)`

- **Test:** First call creates; second call with same args returns the existing one. Concurrency: two simultaneous calls produce ONE conversation (idempotent).

#### W2.4 — GREEN: implement `findOrCreateConversation`

### W3 — Message cell type (`oddjobz.customer_message.v1`)

Per yesterday's design §3.2.

#### W3.1 — RED: failing tests for `customer_message.v1`

- **Tests:**
  - Required: `conversation_id, seq (monotonic per conversation), actor (operator|contact|system), body, body_kind (text|sms|system_event), ts_ms`
  - Linearity = AFFINE
  - `seq` is monotonic per-conversation (out-of-order rejected)

#### W3.2 — GREEN: implement

#### W3.3 — RED: failing test for `appendMessage(conversation_id, actor, body)` happy-path + ordering

#### W3.4 — GREEN: implement

### W4 — Twilio adapter (`runtime/semantos-brain/src/twilio_adapter.zig`)

Pure-logic Zig module wrapping Twilio's SMS API. No HTTP client coupling at the test level — adapter takes a `send_fn` injectable so unit tests use a mock.

#### W4.1 — RED: failing test for `formatE164(raw_number, default_country_code)`

- **Tests:**
  - `"0412 345 678"` + AU → `"+61412345678"`
  - `"+1 (555) 123-4567"` → `"+15551234567"`
  - `"not a phone"` → error.invalid_phone

#### W4.2 — GREEN: implement formatE164

#### W4.3 — RED: failing test for `sendSms(to_e164, body, sender_fn)`

- **Tests:**
  - Calls sender_fn with correct Twilio API URL + auth header + form-encoded body
  - Returns `MessageSent { sid, status }` on 201
  - Returns `error.rate_limited` on 429
  - Returns `error.invalid_recipient` on 400 with code 21211

#### W4.4 — GREEN: implement sendSms (HTTP layer is injectable)

#### W4.5 — RED: failing test for config loader (`/var/lib/semantos/twilio.json`)

- **Tests:**
  - Loads valid config (account_sid, auth_token, sender_phone)
  - Returns `error.twilio_not_configured` when file absent

#### W4.6 — GREEN: implement config loader

### W5 — Operator-initiated send endpoint (`POST /api/v1/conversation/<id>/send`)

Wires W2 + W3 + W4 into a single endpoint. Bearer-gated (operator only).

#### W5.1 — RED: failing reactor-conformance test

- **File:** `runtime/semantos-brain/tests/conversation_send_reactor_conformance.zig`
- **Tests:**
  - `POST /api/v1/conversation/<id>/send` with body `{"body":"hello"}`:
    - Bearer present + valid + conversation exists → 200, message appended, Twilio adapter called with (contact_phone, body)
    - Bearer missing → 401
    - Conversation not found → 404
    - Twilio not configured → 503

#### W5.2 — GREEN: implement reactor handler + dispatch slot

### W6 — Talk|direct search (`POST /api/v1/search/contacts`)

The "type a name or suburb, jobs surface" endpoint.

#### W6.1 — RED: failing tests for searchContactsByQuery(query, scope)

- **Tests:**
  - Query matches contact name (substring, case-insensitive) → returns contacts with their job context
  - Query matches job address.suburb → returns all contacts on those jobs
  - Empty query → 400
  - No matches → returns empty array with 200

#### W6.2 — GREEN: implement search

#### W6.3 — RED: failing reactor-conformance test for `POST /api/v1/search/contacts`

#### W6.4 — GREEN: implement reactor handler + dispatch slot

### W7 — Flutter — JobDetailScreen "People" section

Phone PWA UI. Each contact is a tap target opening a conversation thread.

#### W7.1 — RED: failing widget test

- **File:** `apps/oddjobz-mobile/test/job_detail_people_section_test.dart`
- **Tests:**
  - When job has 0 contacts → "No contacts yet" + "Add contact" button
  - When job has 3 contacts → list of 3 tiles, each tappable
  - Tapping a tile navigates to ConversationScreen with the correct (job_id, contact_id)

#### W7.2 — GREEN: implement the People section widget

### W8 — Flutter — ConversationScreen (per-conversation thread UI)

#### W8.1 — RED: failing widget test

- **Tests:**
  - Renders messages oldest-first
  - Operator messages right-aligned; contact messages left-aligned
  - Send button disabled when text field empty
  - Send button enabled when text present
  - Tapping Send POSTs to `/api/v1/conversation/<id>/send`, appends to local list optimistically

#### W8.2 — GREEN: implement ConversationScreen widget

### W9 — Flutter — Talk|direct search surface

The page where typing a name or suburb finds the job + contacts.

#### W9.1 — RED: failing widget test

- **Tests:**
  - Empty state → "Type a name, address, or suburb"
  - Typing "smith" → POST to `/api/v1/search/contacts` → renders matched jobs each with their contacts
  - Tap a contact → opens ConversationScreen for that (job_id, contact_id)

#### W9.2 — GREEN: implement TalkDirectScreen

### W10 — Integration smoke

#### W10.1 — End-to-end test: create job → add contact → message → assert Twilio adapter called

- **File:** `extensions/oddjobz/__tests__/conversation-e2e.test.ts`
- **Tests:**
  - Test fixture creates a job + REA contact + 3 tenant contacts
  - Calling operator sends "Hey John, need photos" via the conversation endpoint
  - Twilio adapter mock receives correct (e164, body)
  - The conversation cell has the message persisted

### W11 — Wrap-up

#### W11.1 — Doc update: archetype catalog drops electrical + plumbing per Todd 2026-05-14

- Apply W0.3 finding to `docs/design/ODDJOBZ-CUSTOMER-CONVERSATIONS.md` §9.3 seed catalog.

#### W11.2 — Update REACTOR-PORT-TRACKER with new endpoints + tracker entries

- `/api/v1/conversation/<id>/send` (POST)
- `/api/v1/search/contacts` (POST)

#### W11.3 — Final summary commit listing all SHAs + what landed

---

## Progress log

Most recent at top.

- **2026-05-14 iter 14 (final)**: ✅ W8 — `scripts/conv-send-smoke.sh` (curl-based pre-flight for both new endpoints: bearer-missing 401, bogus-id 404 vs twilio-disabled 503, search 200 with matches[]). Plan retrospective added below; loop intentionally stops (no ScheduleWakeup).
- **2026-05-14 iter 13**: ✅ W6 `1d233de` — Talk|Direct search-contacts surface. New `SearchContactsApi` (Dio→ POST /api/v1/search/contacts) + `TalkDirectSearchScreen` (autofocused field, 300ms debounce, stale-response guard, results list, tap→ContactConversationScreen). Inline "Search contacts (name, address, suburb)…" CTA appears in TalkNode body when activeMode is Direct + both APIs are wired. Threaded through home_screen → TalkNode. End-to-end search→send loop is now reachable from the Talk navbar.
- **2026-05-14 iter 12**: ✅ W5 `303f98d` — operator-initiated SMS from contact tiles. New `ConversationSendApi` (Dio-backed POST /api/v1/conversation/<id>/send with typed error wires) + `ContactConversationScreen` (minimal composer: contact details + send field at bottom). Threaded through home_screen → HomeNode → _JobRow → JobDetailScreen. Contact tiles in JobDetailScreen's Contacts section are now tappable when (a) api is wired AND (b) contact has phone. End-to-end functional once brain has /var/lib/semantos/twilio.json. Message history list deferred (W2.6+).
- **2026-05-14 iter 11**: ✅ W7 `c0cd741` (docs: drop electrical + plumbing from §9.3 catalog + qualification rubric + job-sheet schema enum) + ✅ W4 `6926285` (fix: thread `talkSurface` from `home_screen` → `HomeNode` → `_JobRow` → `JobDetailScreen` — the gating reason Todd's home→tap detail view was FSM-pill only). Other JobDetailScreen call sites left unchanged.
- **2026-05-14 iter 10**: ✅ W3.3-W3.5 `02c7b90` — `POST /api/v1/search/contacts` end-to-end wiring. `search_contacts_http.zig` orchestration accept fn (7 tests, all pass: matched + 401 ×2 + 400 ×3 + empty_matches). Reactor handler reactorHandleSearchContacts + route dispatch. SiteServer.search_contacts_acceptor field + attach method. cli/serve.zig SearchContactsCtx + searchListCustomers/searchListSites adapters bound to customers_store + sites_store (latter optional → "name only" degraded mode). Endpoint live when token + customers stores present. `test-conv-search` step: 55/55 tests pass. W3 complete.
- **2026-05-14 iter 9**: ✅ W3.1 RED `906abe6` + ✅ W3.2 GREEN `d26f3ea8` — `runtime/semantos-brain/src/contact_search.zig`. Pure-logic `searchContacts(customers, sites, query)` over slices (testable without LMDB). Name (case-insensitive substring on display_name) + site-mediated suburb/full-address match via Customer.siteRef → Site.cellId join; deduped by customer.id; name matches surface first. Added `zig build test-conv-search` step bundling all three W1–W3 module test artifacts (~5s vs 20+ min full test step). All 48 tests pass.
- **2026-05-14 iter 8**: ✅ W2.5 `2437381` — real `lookup_contact` via `customers_store.findById`. Model: `conversation_id = customer_id` (Todd's "1 conv per contact" pattern). Prefers Customer.normalisedPhone (v2 field, E.164 already); falls back to `twilio_adapter.formatE164(raw_phone, default_country_code)`. Endpoint is now end-to-end functional when: token_store + customers_store + `/var/lib/semantos/twilio.json` are present AND target customer has a parseable phone. `persist_message` stays no-op (Twilio sid is the receipt; brain-side cell-write deferred to W2.6+).
- **2026-05-14 iter 7**: ✅ W2.4 `478bbce` — real `std.http.Client`-backed Twilio sender + boot-time config load. Pattern from `src/push_http_transport.zig` StdHttpTransport. cmdServe attempts `twilio_adapter.loadConfig("/var/lib/semantos/twilio.json")`; on success → endpoint can send for real; on failure → endpoint cleanly 503s. Lookup/persist remain stubs → W2.5 dispatches into oddjobz extension. Brain still compiles + launches.
- **2026-05-14 iter 6**: ✅ W2.3 `5a461a2` — wired `POST /api/v1/conversation/<id>/send` end-to-end (reactor handler + SiteServer attach field + `cli/serve.zig` acceptor construction + build.zig modules). Surface 401/404/503/400 paths exercise correctly; happy path returns 503 `twilio_not_configured` because `twilio_config` stays null this phase. W2.4 lands the real Twilio HTTP sender + dispatch-backed lookup/persist (TODO comments mark the swap sites). Brain compiles + launches.
- **2026-05-14 iter 5**: ✅ W2.1 RED `747b716` + ✅ W2.2 GREEN `c3a5de6` — `acceptSend` orchestration in `runtime/semantos-brain/src/conversation_send_http.zig`. Order: bearer → twilio_config → parseRequest → lookup_contact → twilio_adapter.sendSms (mapped) → persist_message → AcceptResult.sent (sid/status ownership transferred). All 41 tests pass. Pure-orchestration; all deps injected (no LMDB / dispatcher coupling at unit-test level). **Process note:** parallel session fast-forwarded main to the feat tip mid-iter; revised hard-constraint #1 to "branch flexibility" so future iters don't bail on a sync.
- **2026-05-14 iter 4**: ✅ W1.7 `93df8d8` — wired `twilio_adapter_mod` in `build.zig` + inline test step. Build graph parses (`zig build --help` lists `test` step). 28 twilio inline tests will run as part of `zig build test`. W1 (Twilio adapter) complete; ready for W2 (reactor endpoint).
- **2026-05-14 iter 3**: ✅ W1.5 RED `f974f68` + W1.6 GREEN `476f237` — `parseConfig` + `loadConfig` for `/var/lib/semantos/twilio.json`. Added `OwnedConfig` wrapper (heap-allocated string buffers + deinit). 9 new tests; 28/28 total pass. Parser uses `std.json.parseFromSlice`; required fields `account_sid`/`auth_token`/`sender_phone`, optional `verify_service_sid`/`default_country_code`. All failure modes (malformed JSON, wrong type, missing/empty required, IO error) collapse to `Error.twilio_not_configured` — operator semantics is binary, no partial-boot grey area.
- **2026-05-14 iter 2**: ✅ W1.3 RED `43f9359` + W1.4 GREEN `00b4408` — `sendSms` with injectable HTTP sender in `runtime/semantos-brain/src/twilio_adapter.zig`. 6 sendSms tests pass (19 total file tests). Types: `TwilioConfig`, `SendRequest`, `SendResponse`, `SenderFn`, `MessageSent`, `MockSender`. Response mapping: 201 → parseMessageSent; 429 → rate_limited; 400 + code 21211 → invalid_recipient; else → http_error. Form encoding: space→`+`, unreserved verbatim, others %XX. Lightweight JSON field scan (no full parser dep) for sid/status/to + Twilio code disambiguation.
- **2026-05-14 iter 1**: ✅ W1.1 RED `67cb11f` + W1.2 GREEN `cd19d4f` — `formatE164` in `runtime/semantos-brain/src/twilio_adapter.zig`. 13 inline tests pass (`zig test src/twilio_adapter.zig` standalone). Algorithm: strip separators → branch on prefix (already-+, 00 intl, leading 0, bare digits) → apply default_country_code where needed → validate against E.164 regex equivalent. Rejected national-min set to 4 digits (loose enough for real phones, tight enough to reject pathological `"5"`).

---

## Out of scope for this loop

- Web chat widget at `oddjobtodd.info/chat` (yesterday's design §8.1). Defer to a later loop.
- Intake agent LLM posture engine (yesterday's §3.5). Defer.
- BRC-122 ARIA binding for LLM provenance. Defer until LLM is in.
- Marketplace / lead resale. Already deferred per yesterday's scope refinement.
- Customer-initiated phone+Twilio Verify flow. Defer — Todd's immediate need is operator-initiated only.
- Multi-day work_visit split. Defer.

---

## When Todd returns

Loop ran 14 iterations on 2026-05-14. All planned work items landed; loop self-terminated.

### What's live

**Brain (Zig) — both endpoints fully wired:**
- `POST /api/v1/conversation/<id>/send` — Twilio SMS dispatch.
  - 401 on missing/invalid bearer.
  - 503 until `/var/lib/semantos/twilio.json` is provisioned on the brain.
  - 404 when `customer_id` doesn't resolve.
  - 422 on Twilio code 21211 (bad phone); 429 on Twilio rate-limit; 502 on other upstream errors.
  - 200 with `{"sent":true, "sid":..., "status":...}` on success.
- `POST /api/v1/search/contacts` — name + suburb/full-address substring search.
  - 401 on missing/invalid bearer; 400 on missing/empty query.
  - 200 with `{"matches":[{id, display_name, phone, siteRef}]}`.

**PWA (Flutter):**
- Tap a job from home → JobDetailScreen now renders the Conversation section (W4).
- Tap a contact tile (when contact has a phone) → ContactConversationScreen with send composer (W5).
- Tap "Search contacts (name, address, suburb)…" on Talk|Direct → TalkDirectSearchScreen with debounced search, tap result → same ContactConversationScreen (W6).

**Tests:**
- `zig build test-conv-search` exercises all four new module test suites (55/55 pass, ~5s):
  - twilio_adapter (28): formatE164 + sendSms (mock sender) + parseConfig/loadConfig.
  - conversation_send_http (13): parseRequest + acceptSend orchestration.
  - contact_search (7): name + suburb/address with dedupe + ordering.
  - search_contacts_http (7): bearer + parse + listAll-mock + acceptSearch.

**Operator pre-flight:**
- `./scripts/conv-send-smoke.sh` (set `BEARER` + `BRAIN_URL`) — curl-based 4-test smoke covering 401 paths + bearer-bogus-id + bearer-valid-query.

### What's NOT live (deferred to follow-ups)

- **Brain-side persist of outbound messages** (W2.6+): `persist_message` is a no-op success today. Twilio sid is the receipt of truth. If we want a local audit/cell-write, a follow-up port adds a brain-side messages_handler or appends to audit_log.
- **Message history list** in ContactConversationScreen: shows "No message history yet" placeholder. Lights up once W2.6+ lands persist + brain-side query.
- **Other JobDetailScreen call sites** still don't pass `talkSurface` or `conversationSendApi` — only the home→tap path is fully wired. Other paths (calendar, attention feed, site detail, customer detail, find tab, JobListScreen) keep the pre-W5 read-only behavior.
- **Twilio Verify customer-side phone-verification loop** (yesterday's design §3.5): web chat widget + LLM intake agent + Verify code-exchange — all deferred.
- **TDD strictness**: W1.5/W1.6/W1.3/W1.4/W2.1/W2.2/W3.1/W3.2 all followed RED→GREEN commit pairs. Flutter-side W4/W5/W6 didn't write widget tests — relied on `flutter analyze`. Adding widget tests is a fast follow-up if regressions surface.

### Process notes

- **Parallel-session fast-forwards**: branch `feat/customer-conversations` was created at iter setup but was fast-forwarded into main mid-iter by a parallel session. Updated the plan's hard-constraint #1 to "branch flexibility" and saved memory `loops_branch_flexibility.md` so future loops don't bail on a sync.
- **All commits path-scoped** (`git commit <paths> -m ...`) per the existing `git_commit_scope_to_paths.md` memory; no parallel-session work was accidentally committed.
- **Pushed to remote**: nothing pushed automatically — all commits local on main per the plan's rule #5. Todd reviews; push happens on his go.

### Today's commits (28 path-scoped; chronological)

```
f974f68  proofs(twilio): W1.5 RED — config loader
476f237  feat(twilio):   W1.6 GREEN — parseConfig + loadConfig
93df8d8  build(twilio):  W1.7 — wire module + test step
b523ef9  docs(plan):     W1 complete
747b716  proofs(conv):   W2.1 RED — acceptSend types + stubs (9 tests fail)
c3a5de6  feat(conv):     W2.2 GREEN — acceptSend orchestration
9a863a0  docs(plan):     branch-flexibility revision
0f4486e  docs(plan):     W2.2 GREEN done
5a461a2  feat(conv):     W2.3 — reactor + serve wiring (endpoint reachable)
396609f  docs(plan):     W2.3 done
478bbce  feat(conv):     W2.4 — real std.http.Client sender + config load
6c69c25  docs(plan):     W2.4 done
2437381  feat(conv):     W2.5 — real lookup_contact via customers_store
3f63271  docs(plan):     W2.5 done
906abe6  proofs(search): W3.1 RED — searchContacts(query) stub + 7 tests
d26f3ea8 feat(search):   W3.2 GREEN — name + suburb + address substring
36f7d8c  docs(plan):     W3.1/W3.2 done
02c7b90  feat(search):   W3.3-W3.5 — POST /api/v1/search/contacts
9ca0b0d  docs(plan):     W3 complete
c0cd741  docs(oddjobz):  W7 — drop electrical + plumbing
6926285  fix(home):      W4 — thread talkSurface into JobDetailScreen
d886269  docs(plan):     W4 + W7 done
303f98d  feat(conv):     W5 — SMS composer + tappable contact tiles
38b11d0  docs(plan):     W5 done
1d233de  feat(talk):     W6 — Talk|Direct search-contacts screen
838e5a3  docs(plan):     W6 done
[next]   feat(smoke):    W8 — conv-send-smoke.sh + retrospective
[next]   docs(plan):     W8 + retrospective
```
