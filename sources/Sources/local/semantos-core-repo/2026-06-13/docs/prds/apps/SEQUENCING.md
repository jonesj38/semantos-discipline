---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/SEQUENCING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.788122+00:00
---

# Sequencing Plan — Topology → VPS Bootstrap → Alignment → OJT + BRAP Phases

**Audience**: Todd, planning a solo rollout of two bots onto one VPS.
**Scope**: the full critical path from "three git repos don't exist yet" to "OJT and BRAP are live on the VPS with inter-hat double-booking protection, Vercel decommissioned".
**Naming**: **BRAP** is the blockchain risk assessment platform (the bot/app — formerly called "BREM" in earlier drafts). **BREM** (Blockchain Risk Evaluation Matrix) is the 9-cell methodology that BRAP uses. BRAP is the repo; BREM is the theory.

---

## 1. The big picture

There are three workstreams running partially in parallel:

- **Track S** — Shared substrate in `semantos-core`: repo carve-out, package publishing, lexicon updates, calendar extension, guard interface. Prerequisite for almost everything.
- **Track O** — OJT product work in the `ojt` repo: the seven OJT-PHASE prompts. Zero paying users, can move aggressively.
- **Track B** — BRAP product work in the `brap` repo: the A2 migration (Prisma→drizzle, de-Vercel, handleMessage). Paying users, move with soak discipline.

They converge at the VPS deploy (Track V).

```
Track S:   [A1]──[A3]──────────[guard iface in A5]
             │     └──→@semantos/calendar-ext v0.1
             └──→@semantos/intent v0.1, @semantos/protocol-types v0.1, @semantos/semantos-sir v0.1

Track O:        [OJT-1]─[OJT-2]─[OJT-3]─[OJT-4]─[OJT-5]─[OJT-6]─[OJT-7]
                  ↑                                                ↓
                  consumes @semantos/* from Track S         ready for VPS

Track B:        [A2a schema]─[A2b de-Vercel]─[A2c handleMessage]─[A2d BRAPLexicon]─[A2e soak]
                  ↑                                                                  ↓
                  consumes @semantos/* from Track S                          ready for VPS

Track V:                                                        [VPS bootstrap]─[A5]─[cutover]
                                                                       ↑           ↑       ↑
                                                                  needs S,O,B   needs all   OJT first, BRAP second
```

---

## 2. Critical path (what gates what)

The shortest-possible-serial version. Everything else is parallelizable.

1. **A1** (carve repos, publish first packages) — gates everything.
2. **A3** (calendar extension published) — gates the VPS deploy (needs a migration target) and A5 (needs the guard implementation).
3. **OJT-5** (OJT chat through handleMessage) — gates OJT's end-to-end behavior and is the template A2c follows.
4. **A2c** (BRAP chat through handleMessage) — gates A5 on the BRAP side.
5. **VPS-BOOTSTRAP + A4** (VPS up and running) — gates cutover for both bots.
6. **A5** (booking guard wired) — gates the 10th acceptance criterion on `ALIGNMENT-MASTER.md` §7 (cross-bot inter-hat behavior).
7. **Cutover**: OJT flips DNS first (no-risk, no customers); BRAP flips after ≥ 14 days of shadow traffic.

---

## 3. Work you can do in parallel

At any given moment, Todd can have up to three branches in flight:

| Concurrent | In `semantos-core` | In `ojt` | In `brap` |
|---|---|---|---|
| Day 1 after A1 | A3 (calendar extension) | OJT-1 (drizzle columns) | — (waiting for A2 to start) |
| A3 mid-flight | A3 continues | OJT-2 (phone→cert identity) | A2a (drizzle schema port) |
| A3 published | (next: BRAPLexicon PR for A2d) | OJT-3..4 (transport + v3 routes) | A2b (de-Vercel) |
| OJT-4 done, A3 v0.2 published | (next: guard iface for A5) | OJT-5 (handleMessage) | A2c (handleMessage) |
| OJT-5, A2c merging | A5 guard iface PR | OJT-6 (prompts) | A2d (BRAPLexicon wire-up) |
| Late phase | — | OJT-7 (E2E test) | A2e (soak under feature flag) |
| Near cutover | — | (systemd unit ready) | (systemd unit ready) |
| Final | — | A5 wiring in OJT route | A5 wiring in BRAP route |

Rule of thumb: **one open branch per repo at a time**. Three repos → three branches. Don't exceed.

---

## 4. Suggested calendar (solo dev, ~15 hr/week)

Eight-ish weeks from standing start to BRAP cutover. Adjust to taste.

### Week 1 — Foundations (Track S)
- Land **A1 v2** end-to-end. Three repos exist, GH Packages publishing works, both bots build against `@semantos/intent@0.1.0`.
- Tag `semantos-core v0.1.0`. This is the "ground zero" tag; keep it forever as a rollback anchor.
- Deliverable: `pnpm install && pnpm build` green in all three repos.

### Week 2 — Calendar extension (Track S) + OJT warmup (Track O)
- Build A3 (`extensions/calendar/`). Publish as `@semantos/calendar-ext@0.1.0`.
- In parallel: OJT-PHASE-1 (drizzle schema columns for bundles + patches).
- Deliverable: calendar unit + integration tests green in CI; OJT drizzle migration applied.

### Week 3 — OJT phone identity (Track O) + BRAP migration starts (Track B)
- OJT-PHASE-2 (phone→certId adapter, bootKnownCertStore from env).
- BRAP: A2a. Port Prisma schema to drizzle on a branch; run the schema-diff harness; no behavior change yet.
- Deliverable: OJT identity tests pass; BRAP drizzle schema matches Prisma to a byte.

### Week 4 — OJT transport + v3 routes (Track O) + BRAP de-Vercel (Track B)
- OJT-PHASE-3 (HTTP transport in `semantos-core`, published as `@semantos/session-protocol@0.2.0`).
- OJT-PHASE-4 (v3 routes: chat, federation/bundle, jobs/:id/export).
- BRAP: A2b. Replace `@vercel/blob` with local-FS adapter; replace `@vercel/postgres` with `postgres-js`; delete `vercel.json`.
- Deliverable: OJT bundle round-trips over HTTP; BRAP builds with zero `@vercel/*` deps.

### Week 5 — Chat through handleMessage (both bots)
- OJT-PHASE-5 (chatService through handleMessage, patch chain in LLM context).
- BRAP: A2c. Chat route through handleMessage, behind `BRAP_USE_HANDLE_MESSAGE` flag. Flag off by default.
- Deliverable: both bots have a feature-flagged handleMessage path; tests pass with flag on AND off.

### Week 6 — Lexicons + BRAP soak begins (Track S + Track B)
- OJT-PHASE-6 (extraction prompt with jural + propmgmt vocabularies; ≥ 90% fixture pass).
- BRAPLexicon PR to `semantos-core`; publish `@semantos/semantos-sir@0.2.0`. A2d lands in `brap` bumping the dep and wiring BRAP patches through the lexicon validator.
- BRAP: turn on `BRAP_USE_HANDLE_MESSAGE=true` on staging. Start 7-day soak.
- Deliverable: OJT passes extraction gate; BRAP running on the new path in staging, error rate tracked.

### Week 7 — VPS bootstrap + OJT cutover (Track V + Track O finale)
- Provision Binary Lane VPS (see `VPS-BOOTSTRAP.md`).
- OJT-PHASE-7 (13-gate E2E federation test; passes in CI).
- Deploy all three services to VPS. Point `ojt.todd.example` at VPS. **OJT cutover — done, no customers at risk.**
- BRAP stays on Vercel for now; BRAP systemd unit exists on VPS but DNS still points at Vercel.
- Deliverable: OJT live on VPS, `systemctl status` green.

### Week 8 — Booking guard + BRAP cutover (Track B finale + A5)
- A5 guard interface PR to `semantos-core`; publish `@semantos/intent@0.2.0` + `@semantos/calendar-ext@0.2.0`.
- Wire guard into OJT's v3 chat route and BRAP's chat route.
- Cross-bot E2E test passes (≥ 15 gates).
- BRAP: end soak window with green metrics; delete Prisma code; remove `BRAP_USE_HANDLE_MESSAGE` flag; point DNS at VPS for `brap.todd.example`. **BRAP cutover.**
- Keep Vercel deployment warm for 30 more days as rollback insurance.
- Deliverable: all 10 criteria in `ALIGNMENT-MASTER.md` §7 are true.

---

## 5. Gates and no-go conditions

Before advancing from one week to the next, confirm:

| Before starting | Gate |
|---|---|
| Week 2 | `@semantos/intent@0.1.0` is published and installable from a fresh `pnpm install` on your laptop with only the PAT. |
| Week 3 | OJT-PHASE-1 migration applied to OJT's dev DB; no data loss on the existing fixture set. |
| Week 4 | Calendar extension publishes with tests green; OJT phone identity fingerprint matches what the sem_signed_bundles table expects. |
| Week 5 | BRAP de-Vercel'd build succeeds; Stripe webhook still fires on the non-Vercel build (use ngrok to dev-test). |
| Week 6 | Both bots work against the feature-flagged handleMessage path for at least 20 end-to-end scenarios. |
| Week 7 | Stripe has a second webhook endpoint registered pointing at `https://brap.todd.example/api/stripe/webhook` (webhook-signed events arrive and are acknowledged in staging). |
| Week 8 | 7 days of BRAP soak on VPS with `BRAP_USE_HANDLE_MESSAGE=true` show error rate ≤ 0.5%. |

If any gate fails, do NOT advance — diagnose and repeat the failing step.

---

## 6. What each phase prompt produces

Quick reference for what artifact you expect on completion of each phase. Lets you audit "am I really done?" against a concrete list.

| Phase | Artifact |
|---|---|
| A1 v2 | Three git repos with green CI; `@semantos/intent` + `@semantos/protocol-types` published; `.npmrc` on consumers |
| A2 | `brap` repo: no Prisma, no `@vercel/*`, chat through handleMessage, BRAPLexicon applied; `brap_prod` DB on drizzle |
| A3 | `@semantos/calendar-ext` package with schema + policy + API + CalendarLexicon + PlateView; ≥ 30 unit tests; integration test against local Postgres |
| A4 | Three systemd units live on VPS; nginx reverse proxies with Let's Encrypt; Postgres 16 cluster with three DBs; nightly backup cron |
| A5 | CalendarGuard in `@semantos/intent`; createCalendarGuard in `@semantos/calendar-ext`; both bots wired; cross-bot E2E ≥ 15 gates passing |
| OJT-1 | 4 new columns on `sem_object_patches`, new `sem_signed_bundles` table |
| OJT-2 | Phone→CertRecord adapter, admin cert from env, `bootKnownCertStore` |
| OJT-3 | `createHttpTransport` in `@semantos/session-protocol` |
| OJT-4 | `/api/v3/chat`, `/api/v3/federation/bundle`, `/api/v3/jobs/:id/export` routes |
| OJT-5 | chatService calls handleMessage; patch chain in LLM context |
| OJT-6 | extraction prompt with jural + propmgmt vocabularies + 14 few-shot + validator ≥ 90% |
| OJT-7 | 13-gate E2E federation test with real LLM, real DB, real HTTP transport |

---

## 7. Risk register (solo-dev edition)

| Risk | When it bites | Pre-emptive action |
|---|---|---|
| GH Packages auth flakes on VPS | Week 7+ | Test a dry-run `pnpm install` on VPS in Week 1; rotate PAT before it expires |
| BRAP Stripe webhook misses during cutover | Week 8 | Stripe retries for 3 days; cutover on a Saturday morning |
| OJT identity cert fingerprint drifts between dev and VPS | Week 7 | Compute and pin the certId in a test fixture in Week 2 |
| Calendar migrations collide with dev DB | Week 2 | Use `calendar_dev` locally, `calendar_prod` on VPS; never share a DB name across envs |
| Sonnet cost blows up during BRAP soak | Week 6-7 | Put an Anthropic daily spend cap before enabling the new path; log token counts per turn |
| You run out of steam mid-plan | any week | Cut scope — BRAP can stay on Vercel indefinitely; OJT can migrate alone. The plan is additive, not all-or-nothing |

---

## 8. Scope-cut options if life intervenes

If you have to ship something by a given date:

- **Minimum viable alignment**: A1 + OJT-1..7 + VPS bootstrap for OJT only. Leaves BRAP on Vercel. Calendar extension still useful (OJT books its own slots).
- **Operator-hat-only calendar**: skip the `todd-advisor` hat; OJT is the only bot writing to calendar_prod; booking guard is a no-op on BRAP. Ship later when BRAP catches up.
- **No lexicon validation**: skip OJT-PHASE-6 and A2d. Bots work without strict verb gates. Revisit after real usage reveals garbage extractions.
- **Single-DB deploy**: consolidate `ojt_prod`, `brap_prod`, `calendar_prod` into one DB with schema prefixes. Operationally simpler, slightly harder to isolate. OK for solo scale.

Each of these is a one-weekend reduction of the eight-week plan.

---

## 9. "Order of prompts I feed the AI coder"

If you're passing these prompts into an AI to implement, this is the serial order that respects every dependency:

```
1.  REPO-TOPOLOGY.md                 — read-only reference for the AI
2.  ALIGNMENT-PHASE-A1-PROMPT.md     — carve repos, publish
3.  ALIGNMENT-PHASE-A3-PROMPT.md     — calendar extension    (parallel with OJT-1)
4.  OJT/OJT-PHASE-1-PROMPT.md        — drizzle columns
5.  OJT/OJT-PHASE-2-PROMPT.md        — phone→cert identity
6.  OJT/OJT-PHASE-3-PROMPT.md        — HTTP transport
7.  OJT/OJT-PHASE-4-PROMPT.md        — v3 routes
8.  ALIGNMENT-PHASE-A2-PROMPT.md     — BRAP migration        (can parallel OJT-3..4)
9.  OJT/OJT-PHASE-5-PROMPT.md        — chat through handleMessage
10. OJT/OJT-PHASE-6-PROMPT.md        — extraction prompt + lexicon
11. OJT/OJT-PHASE-7-PROMPT.md        — E2E federation test
12. VPS-BOOTSTRAP.md                  — standup the VPS (procedural, not an AI task)
13. ALIGNMENT-PHASE-A4-PROMPT.md     — deploy services to VPS (reference for systemd units)
14. ALIGNMENT-PHASE-A5-PROMPT.md     — booking guard, cross-bot E2E
```

Each prompt is self-contained with prereqs and acceptance criteria. The AI should read `REPO-TOPOLOGY.md` once to ground itself in the three-repo shape, then each phase prompt drives one focused session.

---

## 10. Done definition

Rollout is complete when ALL of these are true:

1. `ojt.todd.example` and `brap.todd.example` resolve to your VPS and serve 200 on `/api/health`.
2. A booking made through OJT on `todd-handyman` reliably blocks a conflicting booking attempt on `todd-advisor` through BRAP (and vice versa). Proven by the A5 cross-bot E2E test.
3. `pnpm install` in `ojt` and `brap` resolves `@semantos/*` purely from GitHub Packages.
4. BRAP has zero `@vercel/*` or `@prisma/*` deps.
5. OJT passes its 13-gate federation E2E with a real LLM.
6. Both bots' chat routes call `handleMessage` from `@semantos/intent`; no legacy chat code remains.
7. Vercel deployments for both bots are decommissioned (or kept cold as rollback insurance only).
8. One `deploy-all.sh` from your laptop updates all three repos on the VPS in under 2 minutes.
9. Nightly Postgres backups exist for the past 14 days.
10. You can explain the full system to someone else (or rubber-duck yourself) without referring to any doc. The system matches your mental model.

Past that point, product work on OJT and BRAP evolves independently. Semantos-core becomes a quarterly-ish upgrade cadence — bump a lexicon, add a transport, publish, bots bump deps when convenient.
