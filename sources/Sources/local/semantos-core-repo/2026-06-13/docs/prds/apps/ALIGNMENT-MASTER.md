---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/ALIGNMENT-MASTER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.786196+00:00
---

# Two-Bot Alignment Master Plan — OJT + BRAP under Semantos

**Status**: AMENDED 2026-04-20 — the v1 "single-repo workspace" target is superseded by `REPO-TOPOLOGY.md`. Decisions §4.A/B/C/D are now locked; see §4 below for the updated state. Read this doc together with `REPO-TOPOLOGY.md` and `VPS-BOOTSTRAP.md`.
**Owner**: todd.price.aus@gmail.com
**Companion docs**:
- `apps/REPO-TOPOLOGY.md` — **the canonical decision** that OJT and BRAP are standalone private repos, not workspace members of `semantos-core`
- `apps/VPS-BOOTSTRAP.md` — step-by-step standup of the three-repo stack on a fresh VPS
- `apps/OJT/OJT-MASTER.md` and `OJT-PHASE-{1..7}-PROMPT.md` — the OJT migration; path references within assume the OJT repo root (not `apps/ojt/` under `semantos-core`)
- `apps/ALIGNMENT-PHASE-A{1..5}-PROMPT.md` — per-phase prompts (A1 is v2; A2–A5 have topology-note headers)

---

## 1. Holistic Objective

Run both of Todd's chatbots — **OJT** (Oddjob Todd handyman intake) and **BRAP** (BRAP risk advisory) — from a **single semantos node on a Binary Lane VPS**, with both apps living under `apps/` in the semantos monorepo, sharing the `core/` (protocol), `runtime/` (intent + session-protocol + node daemon), and `extensions/` (capability domains) tiers, and using a new **shared calendar / inter-hat scheduling extension** to prevent double-booking across the two businesses.

Today both bots live in separate repos (`oddjobtodd/`, `brap-vercel/data/brem-agent/`), both deploy to Vercel, both are Next.js, and neither knows about the other. After alignment they should:

1. Be sibling workspace members of `semantos-core`.
2. Boot from the same daemon process (or the same `pm2` process group) on one VPS.
3. Identify users through a unified hat-context-backed identity layer.
4. Read and write the same `extensions/calendar/` event store so the agent in either bot can refuse a slot that the other bot has already filled.
5. Share Todd's "operator" hat so an admin export / reconciliation in one is visible from the other.

---

## 2. Today's Reality

**OJT** (audited in `OJT-MASTER.md`):
- Next.js 14 + drizzle + PGlite, Claude Haiku 4.5
- 113-line scripted system prompt, procedural `conversationStateManager.ts`
- Phone-based identity (planned), no real customers
- Writes semantic patches but the LLM never reads them back
- Zero lexicon awareness today

**BRAP** (audited in this round):
- Next.js 16 + Prisma + Neon Postgres, Claude Sonnet 4
- 551 lines of prompts (foundation + chat); agentic tool-use loop, no procedural state machine
- Email + optional Google OAuth (NextAuth v5)
- Has its own internal "semantos" packer (`src/lib/brem-compiler/semantos/` — header.ts, cellPacker.ts, replay.ts) that writes 1KB packed semantic cells plus a `StateEvent` audit chain — but **also never reads them back**
- Stripe + Vercel Blob entrenched (paid certified-review flow)

**Semantos monorepo** (audited):
- pnpm workspace: `core/* | runtime/* | extensions/* | apps/* | archive/*`
- `core/` IS the "protocol" tier (semantos-sir, semantos-ir, protocol-types, plexus-*)
- `runtime/intent`, `runtime/session-protocol`, `runtime/node` (daemon entry: `runtime/node/src/daemon.ts`, admin API on :6443)
- `apps/` already hosts loom-react, loom-svelte, poker-agent, mud, piggybank, settlement, etc. — **but none are Next.js**; all React frontends are Vite SPA
- VPS deploy already exists: `scripts/install.sh` (systemd unit, FHS dirs, generates TLS certs, writes `/etc/semantos/node.json`) + `docker-compose.yml`
- **Calendar MVP skeleton was NOT found** by the explore pass (grepped calendar/schedule/timeslot/availability/inter-hat across loom-react, navigator, extensions/) — see Open Decision §4.D

---

## 3. Side-by-side: OJT vs BRAP

| Dimension | OJT | BRAP | Alignment implication |
|---|---|---|---|
| Framework | Next.js 14 | Next.js 16 | Decide §4.B (keep per-app Next vs convert to Vite SPA + Bun route handlers) |
| LLM | Haiku 4.5 (cheap, scripted) | Sonnet 4 (expensive, agentic) | Keep distinct — different shapes, different price points |
| DB | drizzle + PGlite (in-process) | Prisma + Neon Postgres | Decide §4.C (drizzle as the house standard, port BRAP; or accept dual-ORM) |
| State | Procedural state machine | Procedural in-route loop | Both should consume `runtime/intent.handleMessage` for a single triage path |
| Patches | Writes `sem_object_patches`, never reads | Writes `StateEvent` + `SemanticCell`, never reads | Both must read patch chain back into LLM context (see OJT-PHASE-5 + new BRAP equivalent) |
| Lexicon | Zero awareness | Zero awareness (BRAP-internal vocab only) | OJT gets jural+propmgmt; BRAP needs a new `BRAPLexicon` (cell-keys, mitigation actions, threshold verbs) |
| Identity | Phone → certId planned | Email + Google OAuth | Need a unifying hat-context adapter so one operator (you) is the same identity in both |
| Federation surface | None today (PHASE-3 adds HTTP transport) | None | Reuse the same `runtime/session-protocol` HTTP transport for both |
| Vercel deps | None hard | Heavy (Blob, Postgres, Stripe webhook, 60s function cap) | BRAP needs a Blob → S3-compatible adapter (or local FS), a Stripe webhook receiver in the daemon, Postgres on the VPS |
| Customers? | Zero | Active paying users via Stripe | **BRAP cannot break on cutover**; needs blue/green or a maintenance window |

The single biggest delta: **OJT has zero risk of breakage; BRAP has paying users.** The plan must let OJT migrate aggressively while BRAP migrates cautiously behind a feature flag or under a parallel domain.

---

## 4. Decisions (DECIDED 2026-04-20)

| # | Question | Decision | Source |
|---|---|---|---|
| A | `/core` vs `/protocol` naming | **Keep `/core`.** Treat `/protocol` as a synonym in conversation. No rename. | Todd (defaults accepted) |
| B | Per-app framework | **Keep Next.js per-app.** Both bots run as standalone Next servers on the VPS, on ports 3000 / 3001. | Todd (defaults accepted) |
| C | ORM for both bots | **Drizzle, confirmed.** BRAP ports off Prisma in A2 — single-cutover, not dual-ORM. The schema-diff harness in A2 makes the cutover safe. | Todd, 2026-04-20 |
| D | Calendar MVP skeleton | **Greenfield.** Build in `semantos-core/extensions/calendar/`, publish as `@semantos/calendar-ext`. The original "MVP skeleton" was not found by exploration. | Greenfield default |
| E (new) | Where do OJT and BRAP live? | **Standalone private repos** — `ojt` and `brap`. They install `@semantos/*` packages from GitHub Packages. They are **not** workspace members of `semantos-core`. | Todd, 2026-04-20 — see `REPO-TOPOLOGY.md` |

---

## 5. Target Architecture (AMENDED — three repos, one VPS)

```
THREE REPOS:

semantos-core/ (shared; may be OSS later)
├── core/semantos-sir/       (lexicons: Jural + PropMgmt + BRAP + Calendar)
├── core/protocol-types/
├── runtime/intent/          → published as @semantos/intent
├── runtime/session-protocol/→ published as @semantos/session-protocol
├── runtime/node/            (daemon — built and run on the VPS)
├── extensions/calendar/     ★ NEW → published as @semantos/calendar-ext
└── …                        (other existing extensions unchanged)

ojt/ (new, PRIVATE)
├── package.json             (name: "ojt"; NOT a workspace member of semantos-core)
├── .npmrc                   (points @semantos scope at GH Packages)
├── src/                     (OJT Next.js app; private prompts; private schema)
├── systemd/semantos-ojt.service
└── installs @semantos/intent, @semantos/calendar-ext, …

brap/ (new, PRIVATE)
├── package.json             (name: "brap"; NOT a workspace member)
├── .npmrc
├── src/                     (BRAP Next.js app; private prompts; private schema)
├── prisma/ → drizzle/       (A2 ports this)
├── systemd/semantos-brap.service
└── installs @semantos/intent, @semantos/calendar-ext, …
```

**Single VPS, three checkouts, three systemd services:**

```
[Binary Lane VPS]
  /opt/semantos-core/   (clone) → systemd: semantos-node.service  → bun run runtime/node/src/daemon.ts (port 6443, localhost)
  /opt/ojt/             (clone) → systemd: semantos-ojt.service   → next start -p 3000 (localhost)
  /opt/brap/            (clone) → systemd: semantos-brap.service  → next start -p 3001 (localhost)
  nginx + Let's Encrypt  → ojt.todd.example, brap.todd.example, ops.todd.example
  Postgres 16: one cluster, three DBs → ojt_prod, brap_prod, calendar_prod
```

Both bots install `@semantos/intent` and `@semantos/calendar-ext` as normal npm deps from GitHub Packages. Hat-context (Todd's operator hat) is shared by reading a common cert from `/etc/semantos/admin.cert`. Calendar events are written to the shared `calendar_prod` DB so a booking in one bot blocks the other.

See `VPS-BOOTSTRAP.md` for the full standup recipe.

---

## 6. Phase Dependency Graph

```
A1 (workspace placement)
  ├─→ A2 (BRAP migration: Prisma→drizzle, Vercel deps→portable, route through handleMessage)
  ├─→ A3 (calendar extension: schema + policy + API + lexicon + UI)
  └─→ A4 (multi-tenant node: daemon, systemd units, nginx, Postgres)
              └─→ A5 (inter-hat booking guard: both bots consult calendar before confirming)

A1 must come first — every other phase is moving files within the workspace.
A2 and A3 can run in parallel — different files, different concerns.
A4 needs the moved apps from A1 (and assumes A2's portable BRAP, but tolerates Prisma-still-in-place behind a flag).
A5 needs A3 (calendar extension) and A2 (BRAP-on-handleMessage) to wire the guard into both bots' chat routes.
OJT-PHASE-1..7 (the existing OJT prompts) all run concurrently with A1; OJT-PHASE-5 (chat through handleMessage) is the OJT-side counterpart of A2's BRAP-side rewrite.
```

Recommended order if Todd works alone:
1. Decide the four open questions in §4.
2. Run **A1** end-to-end (one weekend; mechanical move + workspace wiring + green CI).
3. Run **OJT phases 1–7** in their already-written order (OJT is risk-free).
4. Run **A2** (BRAP migration; the longest single phase — schema port + Vercel deps swap).
5. Run **A3** (greenfield calendar) in parallel with A2 if you have time.
6. Run **A4** (deploy daemon + bots to VPS); cutover OJT first (no users), then BRAP (paid users — feature-flag the new endpoints, dual-write briefly).
7. Run **A5** (wire booking guard into both bots' chat flows).

---

## 7. Acceptance Criteria for the Aligned System

The plan is "done" when every line below is true.

1. `apps/ojt/package.json` and `apps/brap/package.json` are pnpm workspace members of `semantos-core` with no path-relative imports outside `apps/<self>` except `@semantos/*` workspace deps.
2. `pnpm -w build` and `pnpm -w test` pass with both apps included.
3. Both bots' chat endpoints route through `runtime/intent.handleMessage` and consume `ConversationPatchShape` for context. The LLM in each bot can reference prior patches in its system context.
4. BRAP no longer imports `@vercel/blob`, `@vercel/postgres`; document storage is local FS (or S3-compatible adapter), DB is drizzle on Postgres 16. Stripe webhook receiver lives at `apps/brap/src/app/api/stripe/webhook` and is reachable through the daemon's nginx route.
5. `extensions/calendar/` exposes `bookSlot`, `releaseSlot`, `listHolds`, `findConflicts`, plus a `CalendarLexicon` and a drizzle schema for events.
6. Both bots call `extensions/calendar/findConflicts` before confirming any time-bound action (OJT job slot, BRAP consultant slot). A conflict is surfaced to the user in the chat thread, not silently dropped.
7. A single VPS hosts: 1× semantos-node daemon, 1× ojt next process, 1× brap next process, 1× Postgres cluster, 1× nginx (or Caddy). All four run as systemd units with restart-on-failure; `systemctl status` shows them all green.
8. The shared admin cert (Todd's operator hat) is provisioned once into `/etc/semantos/admin.cert` and consumed by both bots' identity adapter.
9. A 13-gate E2E test at `tests/e2e/inter-hat-booking.test.ts` runs OJT and BRAP against the same calendar extension and proves a slot booked in OJT is unavailable in BRAP (and vice-versa) without either bot crashing or losing a message.
10. Vercel deployments are decommissioned for both apps. DNS for the production hostnames points at the VPS.

---

## 8. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| BRAP cutover breaks paying users | Med | Dual-write Prisma + drizzle for one week; feature-flag the chat-through-handleMessage path; keep Vercel hot for rollback for 30 days |
| VPS resource exhaustion (2× Next + 1× Postgres + daemon on Binary Lane shared VM) | Med | Right-size the VPS *before* A4; budget ≥ 2 vCPU + 4 GB RAM; observe with a basic node-exporter + Prometheus stack |
| Calendar policy is wrong for two-business edge cases (e.g. an OJT job that runs during a BRAP consult) | High | A3 ships with explicit hat-overlap rules + a manual "force-book" override the operator can trigger |
| Stripe webhook downtime during cutover | Low | Buffer Stripe retries (it retries for 3 days); cutover during low-traffic window |
| Drizzle schema port misses Prisma edge cases (cascades, defaults, JSONB shapes) | Med | A2 includes a schema-diff script that exports both ORMs' generated SQL and diffs them |
| Phone identity in OJT collides with email identity in BRAP (no unification) | Low | Unification deferred — the operator hat is shared, end-user identities stay per-bot until a future PRD |

---

## 9. What This Plan Is NOT

- Not a rewrite. Both bots stay recognizably themselves; we move files, swap an ORM, route through a shared intent pipeline, and add a calendar extension.
- Not a multi-tenant SaaS. One operator (Todd), one VPS, two business domains.
- Not a decision to standardize on Next.js. Long-term, semantos prefers Vite SPAs; for now, keep Next per-app and revisit after a year of operation.
- Not a Plexus SDK adoption. Hardcoded admin cert + phone (OJT) / email (BRAP) for end users is acceptable until real Plexus drops.

---

## 10. Companion Phase Prompts

- `apps/REPO-TOPOLOGY.md` — **READ FIRST.** Three-repo decision, publishing model, addenda overriding earlier path assumptions.
- `apps/VPS-BOOTSTRAP.md` — End-to-end VPS standup recipe.
- `apps/ALIGNMENT-PHASE-A1-PROMPT.md` (v2) — Carve out `ojt` and `brap` as standalone private repos; configure GH Packages publishing from `semantos-core`.
- `apps/ALIGNMENT-PHASE-A2-PROMPT.md` — BRAP migration (Prisma → drizzle CONFIRMED, Vercel-isms removed, chat through handleMessage, BRAPLexicon added). Lands in `brap` repo + `semantos-core` PR for the lexicon.
- `apps/ALIGNMENT-PHASE-A3-PROMPT.md` — Calendar extension in `semantos-core/extensions/calendar/`, published as `@semantos/calendar-ext`.
- `apps/ALIGNMENT-PHASE-A4-PROMPT.md` — Multi-tenant VPS node (three checkouts, three systemd units, nginx, Postgres). Design reference; `VPS-BOOTSTRAP.md` is the recipe.
- `apps/ALIGNMENT-PHASE-A5-PROMPT.md` — Inter-hat booking guard. Guard interface in `@semantos/intent`; impl in `@semantos/calendar-ext`; wiring lands in both bot repos.
