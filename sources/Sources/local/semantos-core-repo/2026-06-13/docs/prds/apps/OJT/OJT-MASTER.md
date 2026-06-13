---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/OJT/OJT-MASTER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.790611+00:00
---

# OJT Migration Master — Semantos as OJT's Runtime

> The holistic objective and phase dependency graph for migrating Oddjob Todd
> (OJT), a handyman intake bot currently hosted on Vercel, onto a Semantos node
> running on a Binary Lane VPS. The end state is a live OJT↔REA federation
> exercising every primitive landed in Slices 4 + 5a–d.

## Metadata

| Field | Value |
|-------|-------|
| Version | 1.0 |
| Date | April 2026 |
| Status | Ready for phased implementation |
| Duration | ~2 weeks (7 phases, mostly sequential with one parallel) |
| Prerequisites | Slice 5d (transport) merged; OJT repo at `oddjobtodd` reachable |
| Target Deploy | Binary Lane VPS (Docker Compose), **not** Vercel |
| Related PRDs | `PHASE-13-INTENT-TAXONOMY.md`, `PHASE-14-PLEXUS-ADAPTER.md`, `PHASE-35B-NODE-AS-SERVICE.md` |

---

## Context

### Where OJT is today

OJT is a Next.js 14 + drizzle + PGlite/Postgres intake bot deployed to Vercel
(`oddjobtodd/vercel.json`, `.vercel/`, `next.config.ts`). It exists to do one
job: take a tenant or home-owner's natural-language description of a handyman
problem and convert it into a bookable estimate.

The bot has never had real customers run through it. It hasn't been exercised
against the full breadth of input a real tenant produces.

Three structural facts about OJT today:

1. **The LLM is heavily scripted.** `src/lib/ai/prompts/systemPrompt.ts`
   (113 lines) hand-tunes Claude Haiku 4.5 for Todd's handyman service
   specifically — tradie tone, scope questions templated by job type
   (doors, decks, gutters, fencing, painting), and
   `src/lib/domain/workflow/conversationStateManager.ts` decides the phase
   (`greeting → listen → estimate → contact → close`) in code and injects
   a system instruction telling the LLM which phase to play.
2. **The LLM has zero semantic / verb awareness.** Grep of OJT's `src/`
   for `jural`, `lexicon`, `propertyManagement`, `TaggedCategory`, `verb`
   returns zero hits. Extraction output is ~65 untyped form fields.
3. **The semantic kernel layer is provisioned but write-only.**
   `src/lib/semantos-kernel/schema.core.ts` defines `sem_objects`,
   `sem_object_patches`, `sem_evidence`, `sem_state`, `sem_participants`.
   `chatService.ts` writes to these tables via `ensureSemanticObject()` /
   `recordEvidence()` / `recordStateSnapshot()` / `recordScores()` — but
   the chat LLM **never reads them back**. It only sees raw `messages`
   rows and the `jobs.metadata` JSON blob.

Plexus-core (`oddjobtodd/plexus-core/`) is on disk but has zero `import`
references in `src/` and is not in `package.json`.

### Where semantos-core is today

Slice 4 (PR #116, merged `c6a6c5e`) shipped lexicon polymorphism across the
whole pipeline: `ObjectPatch.lexicon` is a first-class field, `Intent.category`
is a `TaggedCategory`, and the federation gate at
`tests/gates/intent-pipeline-federation.test.ts` proves a multi-lexicon
patch chain round-trips between two loom instances — OJT writes under
`lexicon: 'jural'`, REA appends under `lexicon: 'project-management'`,
both patches land on the final object with attribution intact.

Slice 5a–d (PRs #117 `f8561e0`, #120 `1c647b7`, plus `feat/intent-slice-5d-transport`)
turned the federation wire production-grade:

- **5a** — `SignedBundle<T>` envelope with real secp256k1 ECDSA sign/verify
  (tamper, key-swap, and version gates)
- **5b** — `KnownCertStore` + `verifyBundleWithTrust` (cert trust with
  revocation + impostor protection)
- **5c** — addressed bundles (recipient certId embedded in signed preimage)
  + `HandoffPolicy` (per-object ACL on both sender and receiver)
- **5d** — `BundleTransport` interface + `InMemoryTransport` reference
  (WebRTC / HTTP / overlay transports plug into the same shape)

157 pipeline-surface tests pass across 18 gate files. The architectural work
is done. What is missing is the **live system**: a real tenant driving a real
LLM over a real HTTP wire producing real lexicon-tagged patches that federate
to a real REA stub.

### Why Vercel is the wrong target

Three independent reasons, each sufficient:

- Semantos is a long-lived daemon. The admin API is Bun.serve on 6443 with
  mTLS, the workbench is a separate server on 3000, there is a UDP shard port,
  and the federation object store assumes a persistent on-disk state. Vercel's
  serverless / edge model is structurally wrong for this shape.
- The `Dockerfile` + `docker-compose.yml` in semantos-core are already
  production-shaped for VPS deploy. `docker compose up` and the node is live.
- Federation between OJT-node and REA-node over `BundleTransport` / HTTP wants
  both ends to be addressable, persistent processes. A VPS gives this. Vercel
  does not.

The Binary Lane VPS is the deploy target.

---

## Holistic objective

> **Make OJT a live semantos tenant whose LLM produces lexicon-tagged
> conversation patches that federate to an REA stub over a real HTTP wire,
> using a hardcoded admin cert for Todd and phone-number-derived certs for
> users and REAs — so that the real Plexus SDK can be swapped in later
> without changing any call site above the `CertRecord` boundary.**

Decomposed:

1. Close the structural gap between OJT's `sem_object_patches` table and
   semantos's `ObjectPatch` type (four columns: `timestamp`, `facet_id`,
   `facet_capabilities`, `lexicon`; plus a new `sem_signed_bundles` table
   for envelope persistence).
2. Give OJT a phone-number → `CertRecord` identity adapter that assigns
   structurally to semantos's `CertRecord` interface, and a hardcoded admin
   cert loaded from environment variables — so the real Plexus SDK from
   Dusk can drop in later by replacing one adapter module.
3. Give semantos-core an `HttpBundleTransport` implementation of
   `BundleTransport`, so Slice 5d's in-memory gates can run over a real
   wire between separate VPS processes.
4. Build OJT's public-facing HTTP edge: `/api/v3/chat`,
   `/api/v3/federation/bundle`, `/api/v3/jobs/:id/export`. This is the
   layer that Vercel was doing and that must move to Binary Lane.
5. Wire OJT's `chatService` through semantos's `handleMessage` intent
   pipeline, so every conversation turn produces a `ConversationPatchShape`
   persisted with the new federation fields, and so the LLM sees the patch
   chain as context rather than only raw `messages` rows.
6. Teach the OJT LLM the Jural and PropertyManagement verb vocabularies.
   Every extracted fact gets tagged `(lexicon, category)`; every tag is
   validated against the registry; invalid tags trigger one re-prompt then
   drop rather than fabricate. This is the audit-surfaced phase that closes
   the "LLM doesn't look for verb constraints" gap.
7. Run the full chain end-to-end in a real gate: tenant message → OJT LLM
   extracts lexicon-tagged patch → persisted to new drizzle columns →
   `exportBundle` signs + addresses to REA → HTTP transport → REA verifies +
   policy → imports → REA-PM appends `project-management` patch → bundle
   back → OJT imports. Every Slice 5 attack vector must still reject.

---

## Jural + PropertyManagement verbs (for quick reference)

From `core/semantos-sir/src/lexicons.ts`:

- **JuralLexicon** (`lexicon: 'jural'`):
  `declaration`, `obligation`, `permission`, `prohibition`, `power`,
  `condition`, `transfer`
- **PropertyManagementLexicon** (`lexicon: 'property-management'`):
  `lease`, `maintenance`, `inspection`, `rent`, `violation`, `renewal`,
  `termination`

Every OJT-produced patch must carry one of these `(lexicon, category)` pairs
from Phase 6 onward. The federation gate in Phase 7 asserts this.

---

## Phase dependency graph

```
                       ┌───────────────────────────────┐
                       │ P1  Drizzle federation fields │
                       │     (sem_object_patches +     │
                       │      sem_signed_bundles)      │
                       └───────────────┬───────────────┘
                                       │
                       ┌───────────────┴───────────────┐
                       │                               │
                       ▼                               ▼
         ┌───────────────────────────┐   ┌──────────────────────────────┐
         │ P2  Phone-cert adapter    │   │ P3  HTTP BundleTransport     │
         │     (oddjobtodd)          │   │     (semantos-core) — PARALLEL│
         └─────────────┬─────────────┘   └──────────────┬───────────────┘
                       │                                │
                       └──────────────┬─────────────────┘
                                      │
                       ┌──────────────┴────────────────┐
                       │ P4  OJT HTTP edge             │
                       │     (/chat, /federation, /export)│
                       └──────────────┬────────────────┘
                                      │
                       ┌──────────────┴────────────────┐
                       │ P5  chatService → intent      │
                       │     pipeline (handleMessage)  │
                       └──────────────┬────────────────┘
                                      │
                       ┌──────────────┴────────────────┐
                       │ P6  LLM lexicon awareness     │
                       │     (prompts + validator)     │
                       └──────────────┬────────────────┘
                                      │
                       ┌──────────────┴────────────────┐
                       │ P7  E2E OJT↔REA federation    │
                       │     gate (real LLM, real wire)│
                       └───────────────────────────────┘
```

Critical path: **P1 → P2 → P4 → P5 → P7** (≈ 8 working days).
Parallel: **P3** (semantos-core, can start as soon as P1 starts).
Highest intellectual risk: **P6** (prompt engineering + real-world LLM
noise). Start collecting tenant transcripts now so P6 has a fixture set.

---

## Per-phase scope at a glance

| Phase | Branch | Repo | LOC | Days | Risk |
|-------|--------|------|-----|------|------|
| P1 | `feat/sem-patches-federation-fields` | oddjobtodd | ~150 | 0.5 | low |
| P2 | `feat/phone-cert-adapter` | oddjobtodd | ~200 | 1 | low |
| P3 | `feat/http-bundle-transport` | semantos-core | ~250 | 1 | low |
| P4 | `feat/ojt-http-edge` | oddjobtodd | ~400 | 2 | medium |
| P5 | `feat/chat-uses-intent-pipeline` | oddjobtodd | ~300 | 2 | medium |
| P6 | `feat/llm-lexicon-aware` | oddjobtodd | ~250 | 2 | **high** |
| P7 | `feat/ojt-rea-e2e-gate` | oddjobtodd | ~300 | 1 | medium |

---

## Acceptance criteria for the program

The migration is complete when all of the following are true:

1. `docker compose up` on the Binary Lane VPS brings up an OJT node that
   accepts HTTP traffic on the edge routes.
2. A tenant sending `"the tap in my kitchen is dripping and the lease says
   the landlord covers plumbing"` through `POST /api/v3/chat` results in a
   persisted `ObjectPatch` row with `lexicon = 'property-management'` or
   `lexicon = 'jural'` and a valid `(lexicon, category)` pair.
3. `GET /api/v3/jobs/:id/export` returns a `SignedBundle` addressed to an
   REA cert, signed by Todd's admin key, with a signature that
   `verifyBundleWithTrust` accepts.
4. The Phase 7 gate test passes: full OJT↔REA round-trip over HTTP with
   real LLM extraction; `patch[0].lexicon === 'jural'` or
   `'property-management'`; `patch[1].lexicon === 'project-management'`;
   every Slice 5 attack vector (tamper, key-swap, impostor, wrong-recipient,
   cross-object handoff leak, unregistered recipient) is still rejected.
5. The original `@plexus/vendor-sdk` mock and the real Plexus SDK are both
   drop-in replacements for the phone-cert adapter from Phase 2 — verified
   by running P2's unit tests against a fake "real SDK" shim.
6. Vercel deployment of OJT is shut down (or kept only for the marketing
   site). The bot runtime runs on Binary Lane.

---

## Operating protocol for each phase

Each phase has a dedicated prompt file (`OJT-PHASE-N-PROMPT.md`) in this
directory. To execute a phase:

1. Open a fresh conversation.
2. Paste the contents of the phase's prompt file.
3. The prompt is self-contained — it lists the files to read first,
   the anti-BS rules, the git-hygiene bootstrap, the step-by-step work,
   and the gate tests.
4. Commits follow `feat(ojt-pN/D<N>.<step>): <summary>` format.
5. On phase completion, merge the PR and move to the next phase.

Phase prompts are listed below and live as siblings of this file:

- `OJT-PHASE-1-PROMPT.md` — Drizzle federation fields
- `OJT-PHASE-2-PROMPT.md` — Phone-number identity adapter
- `OJT-PHASE-3-PROMPT.md` — HTTP BundleTransport (semantos-core)
- `OJT-PHASE-4-PROMPT.md` — OJT HTTP edge app
- `OJT-PHASE-5-PROMPT.md` — chatService → intent pipeline wiring
- `OJT-PHASE-6-PROMPT.md` — LLM lexicon constraints
- `OJT-PHASE-7-PROMPT.md` — End-to-end OJT↔REA federation gate
