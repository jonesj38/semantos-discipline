---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/ODDJOBZ-EXTENSION-PLAN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.729490+00:00
---

# Oddjobz Extension — Plan

**Version**: 0.3 DRAFT
**Status**: Plan
**Author**: Todd
**Date**: 2026-04-29 (v0.2), 2026-04-30 (v0.3)
**Changelog**:
- 0.3 — inserted D-W1 (brain dispatcher unification) as architectural prerequisite for D-O5p, D-O5m, D-O6b, D-O7, D-O10, D-O11; split D-O6 into D-O6a (v0.5, no persistence) and D-O6b (v1.0, canon-aligned cells); refined critical path so D-O6a (half day) ships before substrate prep to flush dynamic-route + WASM handler unknowns before D-O5m commits.
- 0.2 — folded in Flutter mobile shell as a peer node (not a thin client); split O5 into desktop/pairing/mobile sub-phases; added D-O5p, D-O5m deliverables.
**Related**:
- `docs/design/V1.0-EXECUTION-PLAN.md` — the parent plan (Todd's OJT migration, 7 stages)
- `docs/design/BRAIN-DISPATCHER-UNIFICATION.md` — D-W1; the substrate this plan lands on
- `docs/EXTENSIONS-VS-TYPES.md` — four-tier model (extensions are workspaces composing types)
- `docs/textbook/28-build-your-first-adapter-kanban.md` — the canonical adapter template
- `docs/textbook/29-cross-vertical-dispatch-and-federation.md` — dispatch envelope; how oddjobz federates with future verticals (RE, accounting)
- `docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md` — site + wallet + auth in one binary
- `docs/design/HELM-ATTENTION-SURFACE.md` — the convergence surface
- `docs/design/SOCIALS-EXTENSION-PLAN.md` — sibling extension; same shape
- `docs/prd/PHASE-26G-NODE-PACKAGING.md` — node packaging; Phase 28 names the Flutter mobile shell as primary tradie UI
- `src/ffi/exports.zig` — Zig FFI core ABI (native + wasm32); the WASM Flutter consumes via dart:ffi

---

## 0. Headline

> Carve the existing Next.js + Drizzle + Postgres OJT bot into `extensions/oddjobz/` — a substrate-native workspace extension that registers Job, Quote, Visit, Invoice, Customer, Site as cell types, defines the trades lexicon and capability scopes, and ships **two operator surfaces**: a Svelte desktop helm and a Flutter mobile shell. The Flutter shell isn't a thin client — it consumes the same Zig WASM the brain runs (via `src/ffi/exports.zig` cross-target build), so the phone is a peer node in the operator's identity DAG with its own cell engine, its own child cert, and its own offline-capable substrate. A public chat surface handles site visitors. The current OJT deployment becomes the canonical tenant. A `semantos node provision-tenant` CLI plus a QR-pairing flow then spins up the same shape for a second tradie in minutes — brain online, phone paired, helm ready. Every primitive the work needs already exists in the substrate (BRAIN, WSITE, mobile-auth, recovery, attention surface, dispatch envelope, voice-shell grammar, FFI cross-target build); this plan is composition, not invention.

---

## 1. The Pattern

```
                        ┌─────────────────────────────────────┐
                        │ tradie's tenant: oddjobtodd.info    │
                        │                                     │
   ┌─────────────────┐  │  ┌────────────────────────────────┐ │
   │ visitor:        │──┼─►│ Tier 1 — public site           │ │
   │ "need a quote   │  │  │   chat widget (anon)           │ │
   │ on a deck"      │  │  │   landing page (static)        │ │
   └─────────────────┘  │  │   booking form (dynamic, WASM) │ │
                        │  └──────────────┬─────────────────┘ │
                        │                 │ persists as       │
                        │                 ▼                   │
                        │  ┌────────────────────────────────┐ │
                        │  │ oddjobz extension              │ │
                        │  │   types: Job, Quote, Visit,    │ │
                        │  │     Invoice, Customer, Site    │ │
                        │  │   lexicon: trades              │ │
                        │  │   caps:  cap.oddjobz.{quote,   │ │
                        │  │     dispatch, invoice, write,  │ │
                        │  │     close}                     │ │
                        │  │   state machines per type      │ │
                        │  │   policy hooks (calendar,      │ │
                        │  │     attention, metering)       │ │
                        │  └──────────────┬─────────────────┘ │
                        │                 │                   │
                        │   ┌─────────────┴────────┐          │
                        │   │ Semantos substrate   │          │
                        │   │  cell engine (K1-10) │          │
                        │   │  capability domain   │          │
                        │   │  recovery + identity │          │
                        │   └──────────┬───────────┘          │
                        │              │                      │
   ┌─────────────────┐  │              ▼                      │
   │ tradie's hat    │──┼──►┌────────────────────────────────┐│
   │ (BRC-52 cert)   │  │   │ Tier 2 — operator helm         ││
   │ ratifies on     │  │   │   svelte SPA at /helm          ││
   │ phone or helm   │  │   │   reads/writes brain           ││
   └─────────────────┘  │   │   identity-cert gated          ││
                        │   └────────────────────────────────┘│
                        │                                     │
                        │   ┌────────────────────────────────┐│
                        │   │ Tier 3 — provisioning surface  ││
                        │   │   semantos node provision-     ││
                        │   │     tenant <domain> --owner-   ││
                        │   │     cert <plexus-cert.pem>     ││
                        │   │     --extensions oddjobz       ││
                        │   └────────────────────────────────┘│
                        └─────────────────────────────────────┘

   Operator's personal mesh (intra-identity DAG):

   ┌───────────────────────────┐       ┌───────────────────────────┐
   │ Brain (sovereign node     │       │ Phone (Flutter shell)     │
   │   on VPS, root cert)      │◄─────►│   child cert, secure      │
   │   - cell engine WASM      │ peer  │     enclave-held          │
   │   - oddjobz extension     │ mesh  │   - cell engine WASM      │
   │   - LLM heavy lifts       │       │     (same Zig binary,     │
   │   - legacy ingest         │       │     wasm32 target)        │
   │   - public chat           │       │   - voice-shell grammar   │
   │   - dispatch envelope hub │       │   - on-device Whisper +   │
   └───────────────────────────┘       │     small Llama for parse │
                                       │   - camera/GPS/mic        │
                                       │   - offline-capable       │
                                       └───────────────────────────┘

   Federation (later, with RE vertical):

       oddjobtodd.info ◄──── dispatch envelope ────► acme-property.com
       (oddjobz ext)         RELEVANT + AFFINE        (re-desk ext)
                             patches per hat
                             K1-enforced bridge
```

The shape is the canonical adapter pattern from chapter 28: typed cells, capability-gated state transitions, hash-chain audit. The shape is also the canonical site-as-sovereign-node pattern from `WALLET-SITE-AS-SOVEREIGN-NODE.md`: HTTP server + wallet + auth + dynamic handlers in one binary. What's net-new is the *extension package* that bundles the trades-vertical specifics into a shippable, tenant-installable artefact, **plus the Flutter mobile shell that paircycle-binds to a brain via a child cert and consumes the same WASM substrate the brain consumes** — so a phone-side action is a real cell-engine transition with K1–K10 enforced locally, not an RPC to a remote authority.

---

## 2. Where We Are

### What's already in place

| Need | Status | Where |
|---|---|---|
| Production OJT bot running | shipped | Next.js on rbs VPS (`semantos-ojt.service`) |
| OJT schema, substrate-aware | shipped | 42 tables, `sem_*` aligned to `schema.core.ts`, `sem_trades_*` to `schema.trades.ts` (per Stage 0 audit) |
| Trades vertical schema | shipped | `oddjobtodd/src/lib/semantos-kernel/schema.trades.ts` |
| BRAIN host shell + REPL | shipped | `runtime/shell/` — Brain 1 through Brain 4.5, Brain 5.1 in flight |
| WSS wallet endpoint | shipped | `/api/v1/wallet` via Brain 4.5 (PR #264) |
| HTTP REPL + LLM transport | shipped | Brain 5.1 (PR #265) — bearer-auth |
| Static site serving | shipped | brain `site_server` (`type = "static"`) |
| Dynamic route shape | shipped | brain `site_server` (`type = "dynamic"` → WASM handler) |
| Helm scaffolding (Svelte) | partial | `apps/loom-svelte/` — needs auth wiring + extension UIs |
| Helm scaffolding (React) | shipped | `apps/loom-react/src/helm/` — Phase 39A merged; AS1–AS5 in flight |
| Mobile-auth flow | shipped | `WALLET-MOBILE-AUTH-FLOW.md` — redirect-and-callback, BRC-100 sign |
| Identity-cert challenge | shipped | WSITE3 — 401 + `X-Semantos-Challenge` header |
| Plexus identity issuance | shipped | the operator already has a cert |
| Plexus recovery enrolment | shipped | recovery payload backed up per BRAIN boot step 13 |
| Zig FFI core ABI (native + wasm32) | shipped | `src/ffi/exports.zig` — phase 30A/30C; init, cell read/write/verify, capability_check, capability_present, linear_consume |
| Flutter mobile shell — design | spec'd | named in `PHASE-26G-NODE-PACKAGING.md` Phase 28 as "primary UI for tradie daily operations" |
| BRC-42 BKDS for child-cert derivation | shipped | the phone's cert is a child derived under the operator's root |
| Voice-shell grammar (`do | find | talk`) | spec'd | `WALLET-VOICE-SHELL-GRAMMAR.md` — VS1–VS5; pipeline is platform-agnostic |
| Trades-aligned cell schemas | partial | `sem_trades_jobs`, `sem_trades_visits`, `sem_trades_sites`, `sem_trades_customers` already exist as Postgres tables; cell-type registration is Stage 4 of V1.0 plan |
| Dispatch envelope primitive | spec'd | chapter 29; implementation lands when first cross-vertical scenario is real |

### What's missing — the scope of this plan

| Net-new | What it is |
|---|---|
| `extensions/oddjobz/` package | The shippable extension — manifest, types, lexicon, capabilities, state machines, policy hooks |
| oddjobz cell types in canonical registry | `oddjobz.job.v1`, `oddjobz.quote.v1`, `oddjobz.visit.v1`, `oddjobz.invoice.v1`, `oddjobz.customer.v1`, `oddjobz.site.v1`, `oddjobz.estimate.v1`, `oddjobz.message.v1` with conformance vectors |
| Capability tokens | `cap.oddjobz.quote`, `cap.oddjobz.dispatch`, `cap.oddjobz.invoice`, `cap.oddjobz.close`, `cap.oddjobz.write_customer`, `cap.oddjobz.public_chat_serve` |
| Trades lexicon — formalised | The vocabulary already exists in code (`schema.trades.ts`); needs a Lean spec at `proofs/lean/Semantos/Lexicons/Trades.lean` and a formal registration as the 9th lexicon |
| Helm UI for oddjobz (desktop) | Svelte SPA composed from `apps/loom-svelte/`; views for jobs, quotes, calendar, customers; talks to brain REPL + WSS |
| Flutter mobile shell | A Flutter app consuming `src/ffi/exports.zig` cell-engine WASM via dart:ffi; voice-shell grammar pipeline on-device with local Whisper + small Llama for parsing; cloud LLM via brain-WSS for heavy generation; oddjobz views as `apps/oddjobz-mobile/` (or analogous) |
| Child-cert pairing flow | QR-encoded payload on the brain side (provisioning CLI emits it); Flutter app scans, derives child cert under operator's root via BRC-42 BKDS, registers with brain over WSS, capability scope set per tenant manifest |
| Mesh sync between operator's brain and phone | Same SignedBundle / multicast / heartbeat machinery any two Semantos peers use, scoped to the operator's identity DAG; LAN-discovery via mDNS + remote via Plexus push relay |
| Public chat dynamic route | `oddjobz-chat.wasm` — anonymous-OK, rate-limited, anonymously persists `chat.message.v1` cells that can be ratified into `oddjobz.lead.v1` |
| Visitor → lead → job pipeline | The Paskian-style ratification: agent (Claude or local LLM) drafts a lead from chat, operator ratifies on phone, lead becomes a job |
| Tenant manifest schema | Declarative form for "what is this tenant" — domain, owner cert, recovery enrolment, extensions array, LLM adapter creds, custom branding |
| `semantos node provision-tenant` CLI | The "few commands" wrapper — reads manifest, lays down dirs, writes systemd units, copies extension bundles, registers domain in Caddy |
| Per-tenant systemd template | `semantos-shell@<domain>.service` — multi-tenant on one VPS or one-per-VPS, both supported |
| Migration adapter (Next.js → extension) | Dual-write from current Next.js routes into oddjobz cells; eventually flips authority and the Next.js front becomes a thin shell over the Semantos Brain substrate |

---

## 3. Phases

The plan is structured to keep Todd's existing OJT bot online throughout and turn each milestone into something a second tradie could buy. Phases O1–O4 are sequential prerequisites. O5 is where helm becomes useful. O6–O9 are parallelisable. O10 is the productisation gate.

Total estimated effort to a sellable v1: ~6–8 weeks of focused work, broken into one-week-or-less chunks. The longest pole is the helm UI build (O5) and the substrate cutover (O7) which absorbs Stage 4 of the V1.0 plan.

### Phase O1 — Trades lexicon formalisation (~3 days, sequential)

The trades vocabulary already lives in `oddjobtodd/src/lib/semantos-kernel/schema.trades.ts` and the Stage-0 schema audit confirmed it's aligned with `schema.core.ts`. What's missing is canonical registration as the 9th lexicon (`docs/canon/lexicons.yml` — currently scaffold-empty), a Lean spec at `proofs/lean/Semantos/Lexicons/Trades.lean`, and a TypeScript registration at `core/semantos-sir/src/lexicons.ts`.

Deliverables:
- `proofs/lean/Semantos/Lexicons/Trades.lean` — header injectivity (M1), substructural decomposition (M2), domain-flag mapping (M3), recovery semantics (M4) per `FORMAL-VERIFICATION-STRATEGY.md`.
- `extensions/oddjobz/src/lexicon.ts` — TS registration that the SIR layer imports.
- `docs/canon/lexicons.yml` — entry under id: `trades` with `status: built`.

Acceptance:
- Existing `sem_trades_*` Postgres tables can be expressed as cell-type schemas keyed under `trades.*` lexicon.
- `lowerSIRWithAuthority` accepts trades-lexicon authority cert and rejects non-conforming programs.

### Phase O2 — Cell types + conformance vectors (~3 days, sequential)

Define the eight oddjobz cell types as canonical schemas with stable type-hashes. Conformance vectors at `extensions/oddjobz/tests/vectors/oddjobz_*.json` ensure byte-identical packing across implementations.

| Type | Linearity | Notes |
|---|---|---|
| `oddjobz.job.v1` | LINEAR | The work-unit. State machine: `lead → quoted → scheduled → in_progress → completed → invoiced → paid → closed` |
| `oddjobz.quote.v1` | LINEAR | A priced offer; consumed when accepted (becomes a Job) or rejected |
| `oddjobz.visit.v1` | LINEAR | A scheduled site visit; consumed when completed (produces a Visit-completed cell) |
| `oddjobz.invoice.v1` | LINEAR | An invoice; consumed when paid |
| `oddjobz.customer.v1` | PERSISTENT | Identity record; accumulates Job/Visit/Invoice references |
| `oddjobz.site.v1` | PERSISTENT | A physical work location; accumulates Visit cells |
| `oddjobz.estimate.v1` | AFFINE | Pre-quote draft; can be discarded without becoming a Quote |
| `oddjobz.message.v1` | PATCH | Customer/operator chat messages; patches Job or Customer |

Acceptance:
- Each type round-trips byte-identically (pack → unpack → pack).
- Each type carries the correct linearity flag.
- Type-hashes recorded in `docs/canon/glossary.yml` alongside existing typed cells.
- The Stage-0 audit's 42-table inventory is fully covered by the type set.

### Phase O3 — Capability mints (~1 day, sequential)

Modify `apps/node-installer/src/first-boot.ts` so that when the extensions array includes `"oddjobz"`, boot step 6 also mints:

| Token | Held by | Spent at |
|---|---|---|
| `cap.oddjobz.write_customer` | operator hat (root) | customer create / merge |
| `cap.oddjobz.quote` | operator hat | `lead → quoted` transition (issues a price) |
| `cap.oddjobz.dispatch` | operator hat | `quoted → scheduled` (commits to a visit slot) |
| `cap.oddjobz.invoice` | operator hat | `completed → invoiced` (issues an invoice) |
| `cap.oddjobz.close` | operator hat | `paid → closed` (terminal transition) |
| `cap.oddjobz.public_chat_serve` | node daemon | per-message rate-limited; visitor chat |

`cap.oddjobz.public_chat_serve` is *not* operator-held — it's a service capability minted to the node itself, with rate-limiting via the metering extension. This keeps visitor chat anonymous-OK without exposing operator-level capabilities. Same pattern as `cap.social.draft` in the socials extension: cheap-and-runtime vs expensive-and-ratified.

Domain flags `0x20–0x25` reserved for oddjobz — needs a one-line addition to the domain-flag registry in `docs/spec/protocol-v0.5.md` §6.

Acceptance:
- A clean install with `--extensions oddjobz` produces five operator-held UTXOs + one service capability in post-boot state.
- Cell creation is rejected at the type-registry layer if the corresponding capability is absent.

### Phase O4 — State machines + kernel-gated transitions (~3 days, sequential)

Implement the eight type state machines in `extensions/oddjobz/src/state-machines/`. Each transition is gated structurally via `OP_ASSERTLINEAR` (`0xC5`) on the resource cell and `OP_CHECKDOMAINFLAG` (`0xC6`) on the capability token's domain flag — same pattern as kanban (chapter 28) and socials (D-S3).

Critical edges and their gates:

| From | To | Token spent | Signing principal |
|---|---|---|---|
| ∅ | `lead` (Job) | `cap.oddjobz.public_chat_serve` (service) OR `cap.oddjobz.write_customer` (operator) | service or operator |
| `lead` | `quoted` | `cap.oddjobz.quote` | operator hat |
| `quoted` | `scheduled` | `cap.oddjobz.dispatch` | operator hat |
| `scheduled` | `in_progress` | none (auto on start-of-visit) | service (clock-tick) |
| `in_progress` | `completed` | none (operator marks done) | operator hat |
| `completed` | `invoiced` | `cap.oddjobz.invoice` | operator hat |
| `invoiced` | `paid` | none (incoming-funds receipt) | service |
| `paid` | `closed` | `cap.oddjobz.close` | operator hat |

K4 (failed opcodes leave PDA byte-for-byte unchanged) means a failed external call (Xero invoice push, Stripe payment confirmation, SMS send) can be retried without partial-state corruption.

Acceptance:
- Unit test: a `quoted → scheduled` transition without spending `cap.oddjobz.dispatch` fails at the kernel gate (K2).
- Unit test: two `quoted → scheduled` transitions on the same Job fail on the second (K1, the cell is already consumed into its successor).
- Unit test: an induced HTTP failure on the `invoiced → paid` step leaves cell state byte-for-byte unchanged (K4) and a retry succeeds.

### Phase O5 — Desktop helm SPA wired to existing tenant (~1 week, parallel after O4)

This is the high-risk, high-information phase: wire the existing Svelte helm scaffolding (`apps/loom-svelte/`) into the live oddjobtodd.info brain substrate. Find every CORS / cookie / WSS-handshake / cert-challenge corner-case in a desktop-browser context before multiplying them across multi-tenancy and a separate mobile shell.

Sub-deliverables:
- O5a — Build the Svelte SPA into a static bundle. Drop into `/var/lib/semantos/.semantos/sites/oddjobtodd.info/public/helm/`. brain's site_server picks it up at `oddjobtodd.info/helm/`.
- O5b — Identity-cert gate. Operator's cert challenge on `/helm/*` paths via WSITE3's `X-Semantos-Challenge` header. Successful sign sets a first-party session cookie. Bearer token issued for WSS sub-channel.
- O5c — Wire helm to brain REPL via authenticated HTTP. Job list, customer list, calendar view, attention feed all read from the substrate via REPL `find` verbs.
- O5d — Wire helm to brain WSS for live tick streams. Chat message arrival, job state advances, attention-surface updates flow over WSS.
- O5e — Mobile auth roundtrip (the existing redirect-and-callback flow). Operator on his phone hits oddjobtodd.info/helm in mobile Safari, redirected to wallet origin, signs with hat, redirected back, session cookie set. This is the auth path BEFORE the Flutter shell exists; it stays useful indefinitely as the path-of-last-resort and as the entry point for non-tradie operators (a one-off contractor logging into helm from a borrowed laptop).

Acceptance:
- Operator opens `https://oddjobtodd.info/helm`, gets challenged, signs on his phone, lands in helm, sees his job list and attention feed live.
- WSS reconnects gracefully on token rotation.
- No CORS / mixed-content / CSP errors in browser console.
- Static-bundle build is reproducible from CI.

### Phase O5p — Child-cert pairing flow (~2 days, parallel after O5b)

The handshake that makes a phone (or any second device) a peer node in the operator's identity DAG. The brain emits a one-shot QR-encoded pairing payload; the device scans it, derives a child cert under the operator's root via BRC-42 BKDS, registers with the brain, and is now a first-class signing principal scoped to whatever capabilities the operator delegated.

Sub-deliverables:
- O5p-a — Pairing-payload schema. CBOR-encoded, signed by operator's root cert, includes:
  - target tenant cert_id
  - delegation context tag (so the phone's cert is structurally isolated from any other context — per spec v0.5 §4.4)
  - capability allowlist (e.g. `[cap.oddjobz.write_customer, cap.oddjobz.public_chat_serve_ratify, cap.attach.photo, cap.attach.gps, cap.attach.voice]` — heavyweight caps stay root-only)
  - lifetime (single-use; expires after 5 minutes)
  - brain WSS endpoint + cert pinning data
- O5p-b — REPL verb `device pair --device-name "Todd's iPhone" --caps minimal | full` emits the QR payload + a fallback URL.
- O5p-c — Acceptor side runs in the brain: receives child cert registration, verifies BRC-42 derivation against the operator's root, records in the identity DAG, mints capability delegations under the requested allowlist.
- O5p-d — REPL verb `device list` / `device revoke <cert_id>` for managing paired devices. Revocation is a capability-token spend (the parent cert revokes child caps via `OP_CHECKDOMAINFLAG` failure on next presentation).

Acceptance:
- Operator runs `device pair`, scans the QR with a stub mobile client (test fixture), confirms a child cert is recorded in the identity DAG with the specified caps.
- Re-running with the same QR is rejected (single-use enforcement).
- Revoking the child cert means subsequent operations from that cert fail at the kernel gate within one heartbeat cycle.

### Phase O5m — Flutter mobile shell (~3–4 weeks, parallel after O5p)

The Flutter app from PHASE-26G-NODE-PACKAGING.md Phase 28, brought into the oddjobz extension's surface set. It's a real Semantos peer node: cell engine, voice-shell grammar pipeline, mesh sync, offline-capable.

Sub-deliverables:
- O5m-a — Flutter scaffolding at `apps/oddjobz-mobile/` (or `apps/semantos-mobile/` if the shell is intended to be extension-agnostic and the oddjobz UI is loaded from the brain dynamically). Project setup, dart:ffi binding to `src/ffi/exports.zig`'s wasm32 build via the `wasm_run` package or platform-native via the C ABI.
- O5m-b — Child-cert custody. iOS Keychain / Android Keystore secure-enclave-backed storage of the device's BRC-42-derived signing key. Pairing UI scans the QR from O5p, completes the handshake, persists the child cert.
- O5m-c — Cell-engine bring-up. Local VFS at the platform's per-app sandbox path (NSFileManager / Android getFilesDir). Local capability UTXO mirror. Local hash chain.
- O5m-d — Voice-shell grammar pipeline. On-device Whisper (whisper.cpp via dart:ffi) for STT. On-device small Llama (e.g. llama.cpp 1B model) for `do | find | talk` parsing. Cloud LLM via brain-WSS as fallback for high-confidence parse failures.
- O5m-e — Mesh sync. Implement the SignedBundle envelope sender/receiver. mDNS discovery for LAN brain peers; Plexus push relay for remote. State reconciliation: phone resyncs on remote-state-newer detection.
- O5m-f — Sensor adapters: camera (HEIC capture → cell attachment), GPS (per-Visit pin), microphone (voice memo → cell). Each produces a signed cell under the device's child cert.
- O5m-g — Push notification subscription. APNs / FCM registration during pairing; brain-side AS5 attention-surface dispatcher routes immediate items to the phone.
- O5m-h — Operator UI: jobs list, calendar, customer list, single-job detail, ratification-queue card, voice/text input bar, attention feed (right-panel-equivalent), settings. The UI consumes oddjobz extension views which can be shipped from the brain dynamically (so updating extension UI doesn't require app store re-submission for trivial view changes).
- O5m-i — Offline mode. Queue locally-signed cell transitions while disconnected; flush on reconnect with K1 conflict resolution surface ("this didn't apply because state changed — here's the current state").

Acceptance:
- Operator pairs phone via QR, scans, confirms; phone now shows current job list pulled from brain.
- Operator says "do | quote | the deck job at three grand"; voice → STT → parse → typed VoiceCommand → ratification card → operator confirms → cell-engine transition signed under device cert → mesh sync → brain accepts → desktop helm reflects within seconds.
- Operator takes a photo at a job site; photo appears as Visit attachment within seconds (online) or on next reconnect (offline).
- Push notification fires within 30 seconds of an immediate attention item.
- Pulling phone offline, advancing a job to `completed`, then reconnecting: the transition lands on the brain.
- Race scenario: brain advances same job to `invoiced` while phone is offline trying to advance to `completed` — phone's transition fails on reconnect with a clear "state moved on" message; no data loss.

This is the substantive engineering pole of the plan. It composes Phase 28 of `PHASE-26G-NODE-PACKAGING.md` plus Voice Shell stage 6 of V1.0 plan plus Attention Surface stage 7. None of those individual primitives are net-new — what's net-new is wiring them into a single Flutter binary scoped to oddjobz's operator surface.

### Phase O6 — Public chat dynamic route (split v0.5 + v1.0)

Ships in two takes so the canon-alignment debt doesn't sneak in. v0.5 lands first (half day, no persistence), gives `oddjobtodd.info` a product-shaped demo and exercises the Semantos Brain `dynamic` route + WASM handler path before D-O5m commits to that surface. v1.0 layers persistence after D-O2 (cell types) so canonical cells are right from day one.

#### Phase O6a — chat v0.5 (~half day, parallel after O4)

Minimum viable public chat. No persistence, no lead extraction yet. Exists to:
1. Prove the Semantos Brain `dynamic` route + WASM handler dispatch path works end-to-end with a real handler (not a synthetic test).
2. Give the public landing page an actual product surface — visitor types into the chat box, gets a coherent reply that sounds like a tradie. Marketing-demo-ready.
3. Surface any Zig-level dispatch bugs while a half-day fix is the worst case, before D-O5m commits weeks of Flutter work to the same surface.

Shape:
- `extensions/oddjobz/handlers/oddjobz-chat.wasm` — minimal handler that takes inbound visitor message, forwards to Brain 5 LLM adapter, streams the response back.
- Front-end chat widget — minimal HTML+JS on the public landing page, opens WSS to `/api/chat` for streaming LLM response.
- Anonymous + rate-limited (`cap.oddjobz.public_chat.serve`).
- **No cell persistence.** Conversations are ephemeral. This is the explicit canon-alignment guard — nothing is being persisted as a canonical cell yet, so nothing can be wrong.

Acceptance: a visitor types into the widget on `oddjobtodd.info`, gets a streamed LLM response in <5 seconds, closes the tab, the conversation is gone.

#### Phase O6b — chat v1.0 (~2-3 days, parallel after O2 and D-W1 Phase 2)

Layers persistence, lead extraction, and ratification onto v0.5. Cannot ship before D-O2 (cell types declared) and D-W1 Phase 2 (`files` + `capabilities` resource handlers in the dispatcher), because the persistence is canon-aligned cells written through dispatcher-mediated capability scopes.

Shape:
- Each visitor message persisted as a `chat.message.v1` cell under a tenant-scoped chat thread.
- LLM responds in the operator's voice using few-shot examples from prior ratified messages.
- When the LLM detects a lead-shape (name + contact + job description), drafts an `oddjobz.estimate.v1` AFFINE cell and queues it for operator ratification via the mobile-auth flow.
- Mobile push when a lead is queued; tapping the notification opens the ratification card; signing produces an `oddjobz.lead.v1` cell.

This is the same pattern as the socials extension's draft → ratify → publish loop, applied to inbound rather than outbound. The agent drafts; the operator ratifies; the lead becomes a quote.

Sub-deliverables:
- O6b-1 — Persistence layer: `chat.message.v1` cell type + writes through `dispatcher.dispatch(files.write, ...)`.
- O6b-2 — Lead-extraction prompt + ratification queue. Reuses `oddjobtodd/src/lib/ai/extractors/extractionSchema.ts` and the LI3 ratification queue from `WALLET-LEGACY-INGEST.md`.
- O6b-3 — Mobile push: when a lead is queued, operator's phone (D-O5m) gets a notification; tapping opens the ratification card; signing produces an `oddjobz.lead.v1` cell.

Acceptance:
- A visitor types "hi I need a quote on a deck repair, my number is 0400-..." in the chat widget.
- Within 30 seconds the operator's phone has a "New lead from chat — ratify?" notification.
- Ratifying spends `cap.oddjobz.write_customer` + `cap.oddjobz.quote` (or just write_customer if the lead isn't quote-ready), produces a Job in `lead` state.
- Conversation history is persisted as `oddjobz.message.v1` patches on the Job.

### Phase O7 — Substrate-truth cutover for OJT (~1 week, sequential after O2)

This phase absorbs Stage 4 of the V1.0 plan but reframes it: instead of declaring cell-types in core, the cell-types are the oddjobz extension's responsibility. The extension is what gets installed; the schema cutover happens *for the tenant that has oddjobz installed*.

Sub-deliverables:
- O7a — Dual-write adapter at `oddjobtodd/src/lib/semantos-kernel/dual-write.ts`. Every Postgres write also produces a substrate cell (signed under operator's hat, persisted via BRAIN `host_persist`).
- O7b — Shadow mode for ≥7 days. Postgres remains authoritative; reconciliation job runs nightly to compare cell-state vs Postgres-state.
- O7c — Authority flip. Substrate cells become source of truth. Postgres remains as a read-cache projected from cells.
- O7d — Backfill historical Postgres rows as substrate cells (one-time idempotent batch, synthetic legacy provenance pointer per cell).

Acceptance:
- Every customer-state-mutating Next.js route produces a substrate cell that is the source of truth.
- Reading from Postgres returns the same logical state as reading from the substrate VFS.
- 100% of historical Postgres rows materialised as substrate cells.

After O7 lands, the existing Next.js front-end becomes a thin client over the substrate — the same shape any other tenant would have.

### Phase O8 — Tenant manifest schema (~2 days, parallel after O5)

Declarative TOML/YAML form for "what makes this tenant a tenant":

```toml
# tenant.toml — read by `semantos node provision-tenant`
[tenant]
domain = "acme-plumbing.com.au"
display_name = "Acme Plumbing"
owner_cert_path = "./acme-plumbing-cert.pem"
recovery_enrolment_id = "plexus-rec-abc123"

[extensions]
install = ["sovereignty", "oddjobz"]

[branding]
landing_page_template = "default-tradie"  # or path to custom HTML
brand_color = "#2a5fb5"
business_hours = "07:00-18:00 AEST"

[llm]
adapter = "openrouter"
api_key_path = "./openrouter-key.txt"
model = "claude-sonnet-4-7"
voice_examples_path = "./acme-conversations.jsonl"

[infrastructure]
mode = "shared-vps"  # or "dedicated-vps"
port = 8082          # auto-assigned in shared mode
caddy_managed = true

[recovery]
plexus_endpoint = "https://recovery.semantos.io"
backup_interval_hours = 24
```

Acceptance:
- Schema defined as a TS type in `runtime/shell/src/tenant-manifest.ts`.
- Validator rejects malformed manifests with actionable errors (missing cert, invalid domain, unknown extension id).
- Round-trip: write a manifest for the existing OJT tenant → run the provisioning CLI in `--dry-run` mode → output is byte-identical to the existing OJT deployment.

### Phase O9 — Per-tenant systemd template (~2 days, parallel after O8)

`semantos-shell@<domain>.service` — a templated systemd unit that replaces the current `semantos-shell.service`. Each tenant gets its own unit file (or override) keyed by domain. Same VPS can host multiple tenants on different ports; or each tenant goes to its own VPS.

Sub-deliverables:
- O9a — `runtime/shell/systemd/semantos-shell@.service` template.
- O9b — Per-tenant directory layout: `/var/lib/semantos/<domain>/{config,data,certs,logs}/`.
- O9c — Caddy config templating: `oddjobz-tenant.caddy.template` with placeholders for domain + port.
- O9d — Smoke test: spin up a second tenant `acme-plumbing-test.local` on a different port; confirm both run independently; confirm no shared state leakage.

Acceptance:
- Two tenants on the same VPS each have their own substrate, identity, capability set, helm, and chat surface.
- Stopping tenant A's unit does not affect tenant B.
- A capability minted in tenant A's substrate is structurally invisible to tenant B (different cert subjects, different domain flags).

### Phase O10 — `semantos node provision-tenant` CLI (~3 days, sequential after O8 + O9)

The productisation gate. The "few commands to spin up a tradie" promise becomes real.

```bash
# What the operator (you, selling to a tradie) types:
semantos node provision-tenant ./acme-plumbing-tenant.toml

# What it does, in order:
#   1. Validates the manifest (O8)
#   2. Verifies the owner cert against Plexus issuance records
#   3. Verifies recovery enrolment (handshake with plexus-recovery service)
#   4. Allocates a port (shared mode) or provisions a VPS (dedicated mode)
#   5. Lays down /var/lib/semantos/<domain>/ directory tree
#   6. Generates self-signed TLS for sub-services
#   7. Writes site.toml with the routes (/, /api/chat, /helm, /api/v1/repl, ...)
#   8. Copies extension bundles (sovereignty.wasm, oddjobz.wasm, helm-spa.zip)
#   9. Writes systemd unit (O9 template, instantiated)
#  10. Writes Caddy block (O9c template, instantiated)
#  11. Reloads Caddy + systemctl daemon-reload + systemctl start
#  12. Runs first-boot for the tenant (mints capabilities, generates BCA)
#  13. Issues operator's first bearer token tied to their cert
#  14. Prints next-steps: "Phone the tradie, walk them through their first-login redirect"
```

Sub-deliverables:
- O10a — CLI entrypoint at `apps/node-cli/src/commands/provision-tenant.ts`.
- O10b — Plexus integration calls (cert verification, recovery handshake).
- O10c — Bundle copy machinery (extensions are tarballs of `manifest.json + types.json + handlers/*.wasm + helm-views/*`).
- O10d — Idempotency — re-running the CLI against an existing tenant updates the manifest without destroying state.

Acceptance:
- Provision a fresh tenant in <5 minutes from CLI invocation to first-login URL printed.
- The provisioned tenant works end-to-end: visitor chat, operator helm, ratification, job pipeline.
- The provisioned tenant federates with the OJT tenant via dispatch envelope (proven in O11 below).
- Re-provisioning is safe.

### Phase O11 — Dispatch envelope smoke test (~2 days, optional but high-leverage)

Federation test: spin up a second tenant `acme-property.com.au` with a *different* extension (a stub re-desk extension that registers a single `MaintenanceRequest` cell type), and prove a dispatch envelope flows from `acme-property → oddjobtodd` and back.

This validates chapter 29's federation primitive against real brain substrate before any RE-vertical work begins. If the dispatch envelope works for stub re-desk, it'll work for full re-desk later.

Sub-deliverables:
- O11a — Stub re-desk extension at `extensions/re-desk-stub/` — single `MaintenanceRequest` type, single cap, single state machine.
- O11b — Dispatch envelope cell type + handler at `extensions/dispatch/` — the bridge primitive.
- O11c — Smoke test: PM hat creates a MaintenanceRequest with `dispatch_to = "oddjobtodd.info#tradie-todd"`. Envelope materialises in the tradie's substrate. Tradie's hat accepts. PM sees `accepted` patch. Tradie posts completion; PM's MaintenanceRequest auto-advances to `invoiced`.

Acceptance:
- AFFINE patches are correctly invisible to the wrong hat (PM can't see tradie's margin notes; tradie can't see owner financials).
- K1 enforced: an envelope can't be silently dropped — if the receiving tenant can't accept, creation fails at the kernel gate.
- The audit trail is regulator-grade (per chapter 29's claim).

This phase is optional for the v1 sale but valuable as a demo: "buy a Semantos node and you're ready to federate with property managers, accountants, suppliers, anyone else on the network."

---

## 4. Mapping the existing Next.js OJT to oddjobz extension

The existing code at `oddjobtodd/` is not thrown away. It folds into the extension along the following mapping:

| Next.js / Drizzle artefact | Becomes part of oddjobz extension as |
|---|---|
| `oddjobtodd/src/lib/db/schema.ts` (core tables) | Cell-type schemas in `extensions/oddjobz/src/types.ts` |
| `oddjobtodd/src/lib/semantos-kernel/schema.trades.ts` | Already substrate-aligned; promoted to lexicon-canonical at O1 |
| `oddjobtodd/src/lib/ai/extractors/` | LLM extraction prompts; reused in the chat handler (O6) and legacy ingest (V1.0 stage 5) |
| `oddjobtodd/src/lib/ai/prompts/` | Operator-voice few-shots; reused in chat handler |
| `oddjobtodd/src/app/api/chat/` | Logic relocates to `extensions/oddjobz/handlers/oddjobz-chat.wasm` (O6) |
| `oddjobtodd/src/app/api/intake/` | Same — relocates to a Semantos Brain dynamic route |
| `oddjobtodd/src/app/admin/leads/` | Replaced by helm view (O5); the Next.js front becomes a thin shell during cutover |
| `oddjobtodd/src/app/admin/calendar/` | Replaced by helm calendar view |
| `oddjobtodd/src/app/admin/chat/` | Replaced by helm chat-history view |
| `oddjobtodd/src/lib/identity/firebase.ts` | Deleted at V1.0 stage 3 (auth cutover) |
| `oddjobtodd/drizzle/` | Postgres remains as a read-cache during shadow mode (O7), then optionally retired |
| `oddjobtodd/systemd/semantos-ojt.service` | Replaced by `semantos-shell@oddjobtodd.info.service` (O9) at the very end |

The migration order matters: O1–O4 (substrate prep) and O5–O6 (helm + chat) ship in parallel with the existing Next.js bot still running. The cutover at O7 brings substrate authority over from Postgres. The Next.js front goes static-shell after O7. The Vercel deprecation in V1.0 stage 8 retires it entirely.

---

## 5. Composition with existing extensions

Same compose-don't-reinvent posture as the socials plan. Concretely:

| Need | Composes with |
|---|---|
| Schedule a Visit at a future time | `extensions/calendar/` — a Visit cell carries a calendar.event ref |
| Brand-voice / tone-of-voice for chat replies | `extensions/policy-runtime/` — a `SpeechActPolicy` (same class introduced for socials) gates LLM-generated replies |
| Operator's brain attention surface | `extensions/attention/` (Phase 39+) — Jobs, Visits, Quotes feed in as ranked items |
| Recovery of customer history | `extensions/recovery/` — extension-state cells flow through the standard recovery payload |
| Outbound social posts about completed jobs | `extensions/socials/` — federation via cell hash refs from Job → Post |
| Federation with re-desk (later) | `extensions/dispatch/` — the dispatch-envelope bridge per chapter 29 |
| Inbound from Gmail / WhatsApp / GCal | `extensions/legacy-ingest/` — V1.0 stage 5; ingested items become oddjobz cells |
| Voice command for operators (desktop helm) | `extensions/voice-shell/` — V1.0 stage 6; `find | jobs at site Henderson` style queries |
| Voice command for operators (mobile shell) | Same `extensions/voice-shell/` grammar, executed on-device in the Flutter app via dart:ffi to whisper.cpp + small Llama; cloud-LLM fallback via brain-WSS for low-confidence parses |
| Metering for SaaS billing | `extensions/metering/` — per-tenant MFP cashlanes settle to operator + Plexus |
| Mobile-side cell-engine execution | `src/ffi/exports.zig` — the same wasm32 cell engine the brain runs, consumed via dart:ffi by the Flutter shell |
| Multi-device identity (phone + brain + future tablet) | BRC-42 BKDS — every device gets a child cert under the operator's root with structurally isolated context tag |
| Device pairing handshake | Reuses the BRC-100 envelope mechanism over a one-shot QR-encoded payload; same cryptographic primitive as any other cross-process auth |

The oddjobz extension *consumes* these primitives. None are re-implemented. This is what makes the "Semantos as platform" SKU coherent: every extension lives at the same altitude and composes through the same primitives.

---

## 6. Lexicon decision — TRADES becomes the 9th lexicon

The eight lexicons currently named (jural, CDM, circuit, project-mgmt, property-mgmt, risk-assessment, bills-of-lading, control-systems) don't include trades. The oddjobz work registers `trades` as the 9th. Existing `schema.trades.ts` is the de facto vocabulary; O1 formalises it.

Mapping (informal):
- Jural — `lead → quoted` is a power-act (the operator exercises the power to offer); `quoted → scheduled` is an obligation acceptance; `paid → closed` is a satisfaction.
- Project-mgmt — Job/Visit/Invoice are the core nouns; the Job FSM is the project lifecycle.
- Property-mgmt (cross-vertical) — Site cells share structure with property-mgmt's Property cells; the dispatch envelope (O11) is the bridge.

The reason to add `trades` rather than just reuse jural + project-mgmt is that there's a coherent micro-vocabulary specific to the trades domain (Quote vs Estimate, Visit vs Job, Site vs Customer-address) that deserves its own lexicon for type-checking precision. Same reason CDM has its own lexicon despite being expressible as a jural+project compound.

---

## 7. Boot-sequence integration

Mirroring the socials integration into the textbook chapter 27 boot sequence:

| Step | With oddjobz extension enabled |
|---|---|
| 6 — capability mint | additionally mint `cap.oddjobz.{quote, dispatch, invoice, close, write_customer}` for operator hat; `cap.oddjobz.public_chat_serve` for node service |
| 12 — adapter feed subscription | oddjobz subscribes to chat-message stream, calendar-tick stream, payment-receipt stream |
| 13 — recovery payload | extension state cells (Customer, Site PERSISTENT cells, plus current-state of LINEAR cells) included in payload |

No new top-level boot step — same architectural test: if oddjobz needed a substrate change, it would be the wrong altitude.

---

## 8. Deliverables (D-W1 + D-O1 .. D-O11)

Reserve **D-O*** for oddjobz, alongside D-S* for socials. **D-W1** is the Semantos Brain dispatcher unification this plan lands on (separate prefix because it's substrate, not extension). Add to `docs/canon/deliverables.yml` once dispatched.

| ID | Title | Phase | Deps | Est. days |
|---|---|---|---|---|
| D-W1 | brain dispatcher unification (5 phases, see BRAIN-DISPATCHER-UNIFICATION.md §8) | W1 | — | 19 (3+3+5+3+5) |
| D-O1 | Trades lexicon formalisation (Lean + TS + canon) | O1 | — | 3 |
| D-O2 | Cell type definitions + conformance vectors | O2 | D-O1 | 3 |
| D-O3 | Capability mint integration with first-boot | O3 | D-O2 | 1 |
| D-O4 | State machines + kernel-gated transitions | O4 | D-O2, D-O3 | 3 |
| D-O5 | Desktop helm SPA wired to existing tenant | O5 | D-O4 | 7 |
| D-O5p | Child-cert pairing flow (REPL + QR + acceptor) | O5p | D-O4, D-W1 (Phase 1) | 2 |
| D-O5m | Flutter mobile shell — Phase 28 brought into oddjobz | O5m | D-O4, D-O5p, D-W1 (Phase 4) | 18–25 |
| D-O6a | Public chat v0.5 — widget + LLM passthrough (no persistence) | O6a | D-W1 (Phase 1, specifically `llm.complete` resource) | 0.5 |
| D-O6b | Public chat v1.0 — lead extraction + ratification + cells | O6b | D-O2, D-O6a, D-W1 (Phase 2) | 2-3 |
| D-O7 | Substrate-truth cutover (OJT → oddjobz cells) | O7 | D-O2, D-W1 (Phase 2) | 7 |
| D-O8 | Tenant manifest schema | O8 | — | 2 |
| D-O9 | Per-tenant systemd template + Caddy templating | O9 | D-O8 | 2 |
| D-O10 | `semantos node provision-tenant` CLI | O10 | D-O8, D-O9, D-O5p, D-W1 | 3 |
| D-O11 | Dispatch envelope smoke test | O11 | D-O4, D-O10, D-W1 (Phase 4) | 2 |

**Critical path** (the recommended ordering — v0.3 refines v0.2's "all parallel after D-O4" into the actual sequence; D-W1 Phase 0+1 lead because D-O6a's LLM passthrough needs the `llm.complete` resource handler that lands in Phase 1):

1. **D-W1 Phase 0** (~3 days) — dispatcher core + wire codec + in-process transport. No resources moved yet; smoke-tested via the existing `brain repl` interactive shell.
2. **D-W1 Phase 1** (~3 days) — bearer_tokens + identity_certs + `llm.complete` resource handlers + Unix socket transport. Retires bearer-token pain (issues #1+#2). Brings LLM online as a dispatcher resource.
3. **D-O6a + D-O5p** (~2.5 days, parallel) — D-O6a (~half day) is the chat widget v0.5 calling `llm.complete` end-to-end — proves the dispatcher pattern carries a real resource and gives `oddjobtodd.info` a product-shaped demo. D-O5p (~2 days) is child-cert pairing inheriting the `identity_certs` resource shape.
4. **D-O1 → D-O2 → D-O3 → D-O4** (~10 days, sequential) in parallel with **D-W1 Phase 2** (~5 days) — substrate prep lands on top of dispatcher Phase 2 (sites/modules/headers + files resource handlers).
5. **D-O6b** (~2-3 days, after D-O2 + D-W1 Phase 2) — chat v1.0 with canon-aligned cell persistence.
6. **D-W1 Phase 3** (~3 days) — HTTP transport rewrite (OPTIONS, directory routes, per-site CORS); retires brain issues #3+#4.
7. **D-O7** (~1 week + shadow-mode observation) — substrate-truth cutover.
8. **D-O8 → D-O9 → D-O10** (~7 days) — productisation rails.
9. **D-W1 Phase 4** (~5 days) — SignedBundle mesh transport, in parallel with **D-O5m kickoff**.
10. **D-O5m** (~3-5 weeks) — Flutter mobile shell, the long pole.
11. **D-O11** (~2 days) — federation smoke test.

The carpenter+musician motivating example (`docs/design/BRAIN-DISPATCHER-UNIFICATION.md` §2.5) is the strongest single argument for this ordering: paying ~6 days for D-W1 Phase 0+1 upfront means a future "drop a music extension on the same brain" is a six-line manifest, not a substrate refactor.

**Total v1 (Todd's OJT migrated + desktop helm + Flutter mobile shell + a second tradie can be provisioned)**: ~12–14 weeks of focused engineering, gated on the Flutter shell as the long pole. Without the Flutter shell (desktop-only v1): ~7–9 weeks.

**Suggested first-cut sale-ready milestone**: D-O6a + D-W1 (Phase 0–3) + D-O1 through D-O7 + D-O5p + a stub Flutter pairing UI (D-O5m-a + D-O5m-b only — pairing works, full mobile UI is wave 2). At that point a second tradie can be provisioned, helm works on desktop, public chat is live, the brain is sovereign, and the phone shows "paired — full mobile UI coming soon." Lets you start onboarding paying tradies before the Flutter shell is fully built. ~7–9 weeks to that milestone.

---

## 9. Acceptance gates (per deliverable)

Same shape as socials/wave-1.5:

1. **Canon discipline**: only canonical glossary terms used. PR description includes `Canon discipline: passed`.
2. **K1/K2/K4 enforcement tests** for every state-machine transition.
3. **Conformance vectors** for new cell types round-trip byte-identically.
4. **Recovery round-trip**: encrypt extension state, encode in recovery payload, decode, decrypt — bytes match.
5. **Mobile-auth round-trip** for any operator-ratified transition.
6. **Two-tenant smoke test** post-O10 — provision a second tenant, confirm isolation.
7. **Updates `docs/canon/deliverables.yml`** with status transitions.
8. **No new top-level boot step** — confirmed by absence of changes outside steps 6, 12, 13.

---

## 10. Risks & open questions

- **Postgres dual-write performance**. Every write going through both substrate cell creation + Postgres write doubles the write path. Stage 4 of V1.0 plan flags shadow-mode for a week of measurement before authority flip. If latency is unacceptable, the answer is async cell creation + eventually-consistent Postgres reconciliation, not abandoning substrate-truth.
- **WASM handler size**. The `oddjobz-chat.wasm` handler embeds the LLM-call + lead-extraction prompt + ratification queue. Aim ≤2 MB for cold-start latency. If it grows, split into multiple handlers (chat-receive, chat-respond, lead-draft).
- **Tenant secrets**. OAuth tokens, LLM API keys, payment-processor creds are per-tenant. Each lives encrypted under a key derived from the tenant's owner-cert root seed (same pattern as wallet.json, same as social.credential.v1). Recovery flow must handle expired refresh tokens — surface to operator via the existing wallet-recovery channel.
- **Two tenants on one VPS — port collisions**. Shared-mode tenants get auto-assigned ports starting from 8082. If a tenant uses a port-bound external service (e.g. a custom integration), document the port-allocation in the tenant manifest and reject conflicts at provisioning.
- **Cross-tenant accidental data leakage**. Capability-domain isolation ensures cells from tenant A can't be spent under tenant B's identity. But shared on-disk paths (lmdb files, log files) need per-tenant directories with appropriate ownership. O9 acceptance test must include a leakage check.
- **The lexicon question — can `trades` actually be just project-mgmt + jural?** Tested at O1 — if the formalisation feels strained when expressed in those terms, separate lexicon is justified. If it feels natural, drop the separate lexicon and reuse the existing two.
- **Re-deploying a tenant — what state survives?** Manifest changes (LLM model, branding) should be live-reloadable. Extension version upgrades need migration paths. State (Job cells, customer history) survives by definition because it's substrate cells. Worth specifying explicitly in the manifest so operators know what's mutable.
- **Re-billing / payment plumbing** — out of scope for v1 (operator collects via existing channels). Post-v1, MFP cashlanes between operator and Plexus become a per-tenant settlement layer.
- **Flutter shell binary size**. Cell engine WASM + whisper.cpp + small Llama all bundled drives the app close to the iOS app-store size limit (~200 MB uncompressed). Mitigation: ship Llama as a post-install download conditional on the operator opting into local-LLM mode; default to brain-cloud LLM. Whisper is small enough to bundle.
- **iOS dart:ffi WASM execution**. Apple JIT restrictions on iOS may force WASM-via-interpreter rather than JIT-compile, which is acceptable for the cell engine's workload (cells are 1KB; opcount is typically <1000) but worth measuring early. Alternative: compile Zig FFI directly to ARM64 native and skip WASM entirely on mobile, sharing the same Zig source via the existing native-target build path (`src/ffi/exports.zig` already supports both via the `is_wasm` comptime branch).
- **Child-cert delegation surface**. The capability allowlist in the pairing payload is what determines what the phone can do. Get this wrong and a stolen phone can do too much; get it too restrictive and the operator's hands-busy mobile flow has to fall back to desktop ratification for routine work. v1 default: phone gets `cap.oddjobz.write_customer`, `cap.oddjobz.public_chat_serve_ratify`, `cap.attach.{photo,gps,voice}`, `cap.oddjobz.complete` (mark a Visit done). Phone does NOT get `cap.oddjobz.invoice` or `cap.oddjobz.close` by default — those stay desk-only.
- **Mesh sync conflicts at low frequency**. Most tradies have one phone and one brain; conflicts are rare. But: laptop helm + phone simultaneously editing the same Customer record is plausible. K1 catches this — the second write fails — but the UX needs to surface it well rather than just silently rejecting. v1 plan: conflict events become attention-surface items.
- **Phone loss recovery**. Operator loses phone → revoke child cert via REPL → buy new phone → re-pair via QR. State on the phone was a cache + a queue of unbroadcast drafts. Cache is rebuildable from the brain. Unbroadcast drafts are lost (acceptable — they were on the phone, not yet ratified). Worth surfacing in onboarding so tradies know "your phone is replaceable; your brain is the truth."

---

## 11. What success looks like

After O1–O10 land, the following sequence works end-to-end:

```bash
# 1. Issue an identity cert for a new tradie via Plexus admin
$ plexus issue-cert \
    --subject "trent-the-tradie@example.com" \
    --recovery-enrol \
    > acme-plumbing-cert.pem

# 2. Compose a tenant manifest
$ cat > acme-plumbing-tenant.toml <<'EOF'
[tenant]
domain = "acme-plumbing.com.au"
display_name = "Acme Plumbing"
owner_cert_path = "./acme-plumbing-cert.pem"
recovery_enrolment_id = "plexus-rec-acme-001"

[extensions]
install = ["sovereignty", "oddjobz"]

[branding]
landing_page_template = "default-tradie"
brand_color = "#2a5fb5"
EOF

# 3. Provision
$ semantos node provision-tenant ./acme-plumbing-tenant.toml
[provision] validating manifest...                     ok
[provision] verifying owner cert against Plexus...     ok
[provision] verifying recovery enrolment...            ok
[provision] allocating port 8082...                    ok
[provision] laying down /var/lib/semantos/acme-plumbing.com.au/...
[provision] minting capability tokens...               5 operator caps + 1 service cap
[provision] copying extension bundles...               sovereignty (2.1MB), oddjobz (3.4MB)
[provision] writing systemd unit...                    /etc/systemd/system/semantos-shell@acme-plumbing.com.au.service
[provision] writing Caddy block...                     /etc/caddy/conf.d/acme-plumbing.com.au.conf
[provision] starting service...                        active (running)
[provision] running first-boot...                      done (cert_id 8f3a..., bca fd12:...)

  Provisioned in 4m 12s.

  Send Trent this URL — first login on his phone:
  https://acme-plumbing.com.au/auth/setup?token=eyJhbGc...

  Helm: https://acme-plumbing.com.au/helm
  Public site: https://acme-plumbing.com.au/

# 4. Trent opens the URL on his phone, signs with his hat, redirects back.
#    He now has a working sovereign brain at acme-plumbing.com.au.

# 5. Trent installs the oddjobz Flutter app from the App Store / Play Store.
#    Operator (you) runs:
$ ssh acme-plumbing.com.au
$ semantos device pair --device-name "Trent's iPhone" --caps minimal
[device] generating one-shot pairing payload...
[device] payload signed under operator root cert (cert_id 8f3a...)
[device] expires in 5 minutes (single-use)

  Pairing QR:

  ████████████████████
  ██  ▄▄▄  █ ▀ █▄ ▀▀██
  ██  █ █  █▀▀█▀▄ ▀▄██
  ██  ▀▀▀  █▀▄▀█▀▀▄ ██
  ████████████████████

  Or paste this URL on the device:
  semantos-pair://acme-plumbing.com.au/pair?token=eyJhbG...

# 6. Trent scans the QR with the oddjobz app. Phone derives child cert under
#    operator root via BRC-42 BKDS, registers with brain, persists cert in
#    iOS Keychain (or Android Keystore). Phone is now a peer node in
#    Trent's identity DAG.

# 7. Trent says into the phone: "do | quote | the deck repair at three grand."
#    On-device Whisper transcribes; on-device Llama parses into a typed
#    VoiceCommand; ratification card displays the parsed action; Trent taps
#    Approve; child-cert signs the cell-engine transition; mesh syncs to
#    brain; brain accepts. Quote cell exists end-to-end in <2 seconds, no
#    cloud round-trip required for the parse step.

# 8. Trent's customer "Mrs Henderson" sends a message via the public chat
#    widget on acme-plumbing.com.au asking about her bathroom job. Brain's
#    oddjobz-chat.wasm parses the message, drafts a lead. Push notification
#    fires on Trent's phone within 30 seconds. He's at another job site, on
#    his ladder. He glances at the notification, reads the chat preview,
#    taps Approve later when he's down. Lead becomes a Job in his brain.
```

The defining property: at no point in this sequence does Trent trust an external service with anything that matters. His identity, his customer database, his job history, his chat backlog, the cell engine that enforces it all — all reside on his sovereign node *and* on his phone, signed under his hat, recoverable from his root, federatable with other Semantos nodes via dispatch envelopes. The phone isn't a window onto the brain; it's a peer of the brain, scoped via capability delegation, K1-enforced at the kernel level on both ends.

---

## 12. Recommended next step

Open Wave 3 commission at `docs/canon/commissions/wave-3-oddjobz.md`, modeled on Wave 1.5: 13 deliverables (D-O1 through D-O11 plus D-O5p, D-O5m), sequential prereqs O1 → O2 → O3 → O4, then five parallel tracks (desktop helm O5, pairing+mobile O5p→O5m, public chat O6, substrate cutover O7, productisation O8→O9→O10), with O11 as the federation demo at the end.

**Concrete first task**: Phase O5a — build `apps/loom-svelte/` into a static SPA and drop into the existing oddjobtodd.info brain site. Wire it to one read-only REPL endpoint (e.g. `find jobs --status open`) end-to-end via authenticated HTTP. That's a half-day's work and surfaces every CORS / auth / WSS unknown before they bite multi-tenant *or* the Flutter shell. Desktop helm goes first because:

1. The browser is the cheapest place to debug auth + WSS + cert-challenge interactions; once the desktop story is clean, the same patterns plug directly into the Flutter shell over dart:ffi.
2. Desktop helm validates that the existing Svelte scaffolding is the right starting point.
3. The Flutter shell is the long pole (3–5 weeks); decoupling it from the critical path means tradies can be onboarded with desktop helm + a paired-but-stub mobile app while the full Flutter UI builds out.
4. The pairing flow (D-O5p) — the substrate-level work that makes mobile possible — is two days, sequenceable any time after D-O5b's cert-challenge plumbing is in place.

After D-O5a works, fork the work into two streams: continue filling in desktop helm views (O5b–O5e) and start D-O5p+D-O5m in parallel. Six weeks later you have a sale-ready first-cut: paying tradies onboarded, brain sovereign, desktop helm fully working, mobile app paired with a minimal voice + ratification UI, the rest of the mobile views building incrementally as wave 2 of the same extension.

---
