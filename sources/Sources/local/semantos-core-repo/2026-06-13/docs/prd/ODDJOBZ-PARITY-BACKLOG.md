---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/ODDJOBZ-PARITY-BACKLOG.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.721461+00:00
---

# OddJobz / Semantos Shell Parity Backlog

Date: 2026-06-12

Goal: make `apps/semantos` a dumb cartridge loader shell while bringing `packages/oddjobz_experience` to functional parity with the archived OddJobz operator reference (`archive/apps-loom-svelte` / `archive/apps-semantos-monolith`).

## Principles

- Shell stays cartridge-neutral: no OddJobz field/business UI in `apps/semantos/lib/shell`.
- Field PWA surfaces cartridge use; brain/helm surfaces cartridge management and policy/configuration.
- Cartridge screens and workflows live in `packages/oddjobz_experience`.
- Brain/runtime endpoints remain the source of truth for cells, patches, quote resources, attachments, and pricing policy.
- Parity target is functional parity first; visual parity/golden CSS clone is a follow-up decision.

## P0 — Shell cartridge loading/navigation

### OJ-P0-1 Dynamic cartridge screen navigation

**Status:** DONE — `fc2ca60f Start OddJobz parity implementation`

**Evidence:** `cd apps/semantos && flutter test -r compact test/shell/cartridge_picker_navigation_test.dart` passed.


**Problem:** `apps/semantos` registers `/oddjobz` and `/betterment` entries but `SemantosRouter` only exposes `/`; the cartridge picker only scopes `activeCartridge` and does not load the cartridge screen.

**Acceptance criteria:**

- Tapping OddJobz in the cartridge picker opens `OddjobzScreen` or an equivalent cartridge-hosted surface.
- Tapping Betterment opens `BettermentScreen` or an equivalent cartridge-hosted surface when Betterment is configured as user-visible.
- Shell home remains shell-neutral.
- Widget test covers picker -> OddJobz screen navigation.

### OJ-P0-2 Surfacing-mode policy

**Status:** DONE — `surfacing_mode_policy_test.dart` proves default cartridges contribute field verbs, dedicated/passive cartridges do not, and the picker hides passive while still routing default/dedicated cartridge entries.


**Problem:** The shell currently treats picker entries as `role == experience`, while manifests also carry `ui.surfacingMode`.

**Acceptance criteria:**

- `default` cartridges may scope helm verbs.
- `dedicated` cartridges navigate to their own screen.
- `passive` cartridges are hidden.
- Betterment visibility is explicit and tested.

## P0 — Package/test health

### OJ-P0-3 OddJobz package isolation

**Status:** DONE — `fc2ca60f Start OddJobz parity implementation`

**Evidence:** `cd packages/oddjobz_experience && flutter test` passed after package resolution.


**Problem:** `packages/oddjobz_experience` must pass tests from its own directory after `flutter pub get`; stale package configs previously surfaced missing dependency errors.

**Acceptance criteria:**

- `cd packages/oddjobz_experience && flutter pub get && flutter test` passes.
- CI/script explicitly runs package-level tests so stale `.dart_tool` does not mask breakage.

### OJ-P0-4 Current button/wiring proof

**Status:** DONE — `cartridge_parity_wiring_test.dart` proves OddJobz + Betterment registry entries and expected wired/unwired manifest verbs.


**Acceptance criteria:**

- Tests enumerate all manifest `ui.verbs` for OddJobz + Betterment.
- Every visible verb is either dispatch-wired or intentionally marked `(unwired)` with a test.
- Known unwired verbs have backlog tickets or are hidden until implemented.

## P1 — Per-job conversation parity

### OJ-P1-1 Job-scoped compose note

**Status:** DONE — `BrainClient.submitJobNote()` and `JobDetailScreen` typed-note composer are covered by widget tests for no-cell blocked state, successful submit/refresh, and auth/server failure rendering.

**Evidence:** `./scripts/test-oddjobz-parity.sh` passed; `job_detail_screen_test.dart` covers no-cell/error/refresh states and `brain_client_test.dart` covers `/api/v1/voice-note` request shape.


**Problem:** Current Flutter job detail reads conversation turns but lacks the archived compose note UI.

**Acceptance criteria:**

- Job detail shows a compose box when `job.cellId` exists.
- Sending text calls `POST /api/v1/voice-note` with transcript + `entity_cell_hash` or a canonical turn endpoint.
- On success, conversation turns refresh.
- Tests cover success, auth failure, no-cell blocked state, and refresh.

### OJ-P1-2 Voice note upload

**Status:** DONE — `BrainClient.submitJobVoiceNote()` uploads multipart audio to `/api/v1/voice-note`; `JobDetailScreen` exposes a job-scoped voice-note action with injectable capture; tests verify multipart request shape, refresh, and error handling.

**Evidence:** `flutter test test/brain_client_test.dart test/job_detail_screen_test.dart` passed.

**Acceptance criteria:**

- Job detail exposes microphone/voice note control.
- Client method uploads/transcribes via the brain-supported voice-note path.
- Created voice note appears as an `oddjobz.conversation.turn` or linked attachment/turn.
- Tests mock endpoint and verify refresh/error handling.

### OJ-P1-3 Image/attachment upload and list

**Status:** DONE — `Job` parses attachment refs, `BrainClient.uploadJobAttachment()` posts signed metadata/blob multipart to `/api/v1/attachments/upload`, and `JobDetailScreen` lists job attachments plus exposes an injectable attachment capture/upload action that refreshes the job after upload.

**Evidence:** `flutter test test/brain_client_test.dart test/job_test.dart test/job_detail_screen_test.dart` passed.

**Acceptance criteria:**

- Job detail shows linked attachments for the job.
- Image upload calls `POST /api/v1/attachments/upload` with job/entity reference.
- Attachment list refreshes after upload.
- Tests cover image upload, voice memo attachment metadata, auth failures, and empty state.

## P1 — Quote generation/preview parity

### OJ-P1-4 Quote editor/preview sheet

**Status:** DONE — `QuoteEditorSheet` has edit/preview tabs, manual/catalog line insertion, preview totals, and Job Detail integration. `JobDetailScreen` now persists accepted drafts through `BrainClient.saveQuoteDraft()` to the canonical brain quote seam (`add quote job:<id> min:<cents> max:<cents>`), then refreshes conversation turns.


**Problem:** Current Flutter only runs `quote job <id>` and displays raw monospace output.

**Acceptance criteria:**

- Job detail can open a quote editor/preview for the job.
- Existing quotes for the job are visible.
- New draft supports line items, notes, payment terms, and total preview.
- Save uses canonical quote resource/REPL path.
- Tests cover preview math, save success, save error, and refresh.

### OJ-P1-5 Conversation-context quote seeding

**Status:** DONE — `quoteDraftSeededFromConversation()` conservatively turns inbound/external money mentions into editable quote draft lines. `JobDetailScreen` exposes a `Use conversation context` toggle before opening the editor, so operators can include or exclude seeded context before saving.

**Evidence:** `quote_seed_test.dart` covers seed extraction; `job_detail_screen_test.dart` covers include/exclude behavior and canonical quote save totals.

**Acceptance criteria:**

- Quote editor can include/exclude conversation context.
- Seeded quote lines are shown as editable draft lines before saving.
- No raw-only REPL output is the final UI.

### OJ-P1-6 Quote FSM actions

**Acceptance criteria:**

- Quote detail/editor exposes allowed actions: present, accept, decline, expire, supersede where applicable.
- Tests cover state-dependent actions.

## P1 — Pricing catalog/policy parity

### OJ-P1-7 Brain-side operator-configurable pricing policy and catalog

**Status:** IN PROGRESS — `ac5801a2 Make OddJobz catalog operator configurable` made catalog empty-by-default/operator-owned; `a4e225ba Route cartridge management through Me panel` added Me → Brain management entry point. Brain-side policy APIs/UI still required.


**Problem:** OddJobz is visit-based service-business agnostic. Pricing/catalog policy must be operator configurable, not hardcoded to handyman or any other trade.

**Acceptance criteria:**

- Fresh operator sees a clear “pricing/catalog not configured” state in the brain-management surface, not an assumed handyman catalog.
- Operator can create/edit/reset their own pricing policy and quote catalog from brain/helm management.
- PWA Me panel links to a mobile-optimised brain-management view for these controls.
- Pricing/catalog management does not appear as normal field DO/TALK/FIND verbs.
- Optional seed templates are clearly labelled as examples and never treated as canonical defaults.
- One-click seed/import action writes `oddjobz.pricing_policy.v1` or policy draft through the supported brain-side seam.
- Test proves fresh unconfigured state and explicit operator seed/configuration path.

### OJ-P1-8 Catalog-assisted line item insertion

**Status:** PARTIAL — `ac5801a2 Make OddJobz catalog operator configurable` added `QuoteCatalogStore` and optional example seed; this slice adds editor insertion from configured catalog. Brain-management UI for editing the catalog/policy still required.


**Acceptance criteria:**

- Quote/invoice editor can insert common catalog items.
- Catalog selection prepopulates description/unit price/tax/category from the operator’s configured catalog.
- Tests cover insertion and edited override.

## P2 — Visual/design parity

### OJ-P2-1 Archived styling pass

**Acceptance criteria:**

- Decide exact visual clone vs Material functional parity.
- If clone: translate `archive/apps-loom-svelte/src/app.css` tokens into Flutter theme/widgets.
- Golden tests for key states: job list, job detail, conversation turn, quote editor, attachment strip.

## P2 — Documentation and CI

### OJ-P2-2 Parity checklist in CI

**Status:** DONE — `scripts/test-oddjobz-parity.sh` runs OddJobz package tests, Betterment package smoke tests, and Semantos shell parity tests.


**Acceptance criteria:**

- Add a script or doc command list for app tests, package tests, and any brain tests required for parity.
- Record known deferred archive features with owners/status.

## Boundary hardening note — OddJobz/Betterment bleed

**Status:** DONE — Added regression coverage that proves active-cartridge scoping prevents OddJobz/Betterment field-verb bleed. In unscoped helm mode, default-mode cartridges intentionally aggregate; once a cartridge is active, `GrammarRegistry.verbsForModalAndExtension()` must return only that cartridge's verbs. Dispatcher duplicate intent names are also rejected so name-keyed dispatch cannot silently cross cartridge boundaries.

**Evidence:** `cartridge_parity_wiring_test.dart` covers scoped OddJobz vs Betterment bundled manifests; `intent_dispatcher_test.dart` covers duplicate name rejection.

## OJ-P2 — TALK/DIRECT identity fallback and conversation patches

### OJ-P2-3 Tenant/REA direct messaging fallback via Twilio

When an operator messages a tenant or REA from `TALK | DIRECT`, OddJobz should route through the strongest available identity channel:

1. If the participant has a Semantos/PKI identity and a supported direct channel, send as an authenticated direct message.
2. If no PKI/direct identity exists, fall back to Twilio SMS.
3. Twilio SMS content should include a secure reply URL into the OddJobz chat widget.
4. Replies from that URL become canonical conversation patches anchored to the relevant job/customer/participant.
5. Conversation patches must preserve participant provenance (`operator`, `tenant`, `rea`/property manager, subcontractor) so quote generation can trace which party supplied each fact/price/scope change.
6. Quote autogeneration/import must consume these patches through the SCG/edge extraction seam, not via substrate-side LLM calls.

This belongs under TALK/DIRECT and the conversation/SCG pipeline, not the DO/FIND management surfaces.
