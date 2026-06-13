---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/REPO-TOPOLOGY.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.786470+00:00
---

# Repo Topology — Three Repos, One VPS

**Status**: DECIDED (supersedes `ALIGNMENT-MASTER.md` §4.A and §5 "Target Architecture" block)
**Decided by**: Todd
**Date**: 2026-04-20

---

## Decision

Keep three separate repos. Do **not** merge OJT or BRAP into `semantos-core`.

| Repo | Visibility | Role | Published? |
|---|---|---|---|
| `semantos-core` | shared (may be OSS later) | Protocol, runtime, extensions, node daemon | **Yes** — publishes `@semantos/*` packages |
| `ojt` (new, private) | private | OJT Next.js app + OJT-specific drizzle schema + OJT-specific prompts | No |
| `brap` (new, private) | private | BRAP Next.js app + BRAP-specific drizzle schema + BRAP-specific prompts | No |

The VPS hosts all three — one long-running node daemon built from `semantos-core`, plus two Next.js processes (one per bot). Your business code and prompts stay in private repos; the shared primitives stay in `semantos-core`.

---

## Why not the workspace-member approach from A1 v1

- Mixes private business logic and prompts into a repo you want to share.
- Makes `semantos-core` CI cost and complexity track two apps that aren't its concern.
- Forces a single-repo release cadence — a BRAP hotfix can't ship independently of a `semantos-core` library bump.
- Leaks your domain language (BRAP cells, REA jural verbs, client lists) into a repo that may become OSS.

---

## Why this alternative wins

- Each bot is a normal standalone Next.js app. Build locally with `pnpm install && pnpm build`, deploy with `systemctl restart`. No workspace gymnastics.
- `semantos-core` cuts versioned releases. Each bot pins `@semantos/intent@^0.3.0`, `@semantos/calendar-ext@^0.2.0`, etc. Bot upgrades are opt-in.
- Drizzle is the shared house standard — used in both bots and in the calendar extension. Prisma is gone from BRAP after A2.
- The VPS deploy stays simple: three git clones, three systemd units, nginx in front.

---

## Publishing model for `semantos-core`

Packages to publish (from `semantos-core`):

| Package | Path in repo | Purpose |
|---|---|---|
| `@semantos/intent` | `runtime/intent/` | `handleMessage`, `ConversationPatchShape`, triage |
| `@semantos/session-protocol` | `runtime/session-protocol/` | `SignedBundle`, transports, handoff policy |
| `@semantos/protocol-types` | `core/protocol-types/` | `Identity`, `NodeConfig`, cert shapes |
| `@semantos/semantos-sir` | `core/semantos-sir/` | Lexicons (Jural, PropMgmt, BRAP, Calendar) |
| `@semantos/calendar-ext` | `extensions/calendar/` | Hats, bookings, holds, conflict policy |

Publish target: **GitHub Packages** (scope `@semantos`), private.

Release flow:
1. Land changes on `main` with `changeset` entries.
2. A release PR bumps versions and produces a changelog.
3. Merge → CI publishes each changed package to `https://npm.pkg.github.com` under the `@semantos` scope.

Each bot's `.npmrc`:
```
@semantos:registry=https://npm.pkg.github.com
//npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}
```
`GITHUB_TOKEN` is a classic PAT with `read:packages` (bot repos get read-only tokens; `semantos-core` CI gets a write token stored as a repo secret).

### Alternative if GitHub Packages feels heavy

Git-tag tarballs. `semantos-core` CI tags releases and uploads `.tgz` artifacts to GitHub Releases. Bots install via:
```json
"@semantos/intent": "https://github.com/toddprice/semantos-core/releases/download/v0.3.0/semantos-intent-0.3.0.tgz"
```
Slightly uglier, no auth needed on the bot side. Pick whichever feels lower-friction; the rest of the plan is identical either way.

---

## The bots as standalone repos

### `ojt` repo layout (new)

```
ojt/
├── .env.example
├── .npmrc                          (points @semantos scope at GH Packages)
├── package.json                    (name: "ojt", private)
├── drizzle.config.ts
├── src/
│   ├── app/                        (Next.js 14 app router)
│   ├── db/
│   │   ├── schema.ts               (OJT-owned tables: jobs, intake, sem_objects, sem_object_patches, sem_signed_bundles)
│   │   └── client.ts
│   ├── lib/
│   │   ├── ai/prompts/             (OJT system + extraction prompts; private voice)
│   │   ├── identity/               (phone→certId adapter; consumes @semantos/protocol-types)
│   │   ├── chat/                   (consumes @semantos/intent handleMessage)
│   │   └── calendar/               (thin wrapper around @semantos/calendar-ext)
│   └── …
├── scripts/
│   ├── dev.sh
│   └── deploy.sh
└── systemd/
    └── semantos-ojt.service        (deploy artifact; copied to /etc on VPS)
```

Dependencies:
```json
{
  "dependencies": {
    "next": "14.x",
    "drizzle-orm": "^0.33.x",
    "postgres": "^3.4.x",
    "@anthropic-ai/sdk": "^0.30.x",
    "@semantos/intent": "^0.3.0",
    "@semantos/session-protocol": "^0.3.0",
    "@semantos/protocol-types": "^0.3.0",
    "@semantos/semantos-sir": "^0.3.0",
    "@semantos/calendar-ext": "^0.2.0"
  }
}
```

### `brap` repo layout (new)

Same shape as `ojt`, with BRAP-specific differences:
- Port `3001` instead of `3000` in `next start`.
- `src/db/schema.ts` mirrors the old Prisma models (NextAuth + app + compiler layers) via drizzle. See A2 for the full list.
- `src/lib/ai/prompts/` keeps the 117-line foundation + 434-line chat prompt you have today.
- Keeps Stripe webhook and NextAuth. Removes `@vercel/blob` and `@vercel/postgres` per A2.
- Does **not** include BRAP data (that lives elsewhere — `archive/brem-data/` in `semantos-core` or a separate private data repo, your call).

---

## Shared state: the calendar database

Both bots talk to the **same Postgres database** for calendar tables (`cal_hats`, `cal_bookings`, `cal_holds`). This is the single piece of runtime state that crosses bots, and it's the mechanism by which a booking in OJT blocks a booking in BRAP.

- The schema is owned by `@semantos/calendar-ext`. It ships migrations.
- On the VPS, a one-shot service (`semantos-calendar-migrate.service`) runs `node_modules/.bin/calendar-migrate` against the `calendar_prod` DB on every deploy.
- Both bots' drizzle clients have a **secondary connection** (`CALENDAR_DATABASE_URL`) pointed at the same DB.
- The bots never write schema to this DB — they only read and write rows.

This is a soft "distributed monolith" — fine at single-operator scale; re-architect only if you ever need two operators or independent bot deployment cycles.

---

## Where each phase's work lands

Updated pointer for every existing phase prompt:

| Phase | Work lands in | Notes |
|---|---|---|
| **A1** (new, v2 — see replacement file) | All three repos | carve out bot repos; set up publishing; does not touch behavior |
| **A2** (BRAP migration) | `brap` repo + `semantos-core` for `BRAPLexicon` + release of `@semantos/semantos-sir` | Drizzle confirmed. See §"A2 addendum" below. |
| **A3** (calendar extension) | `semantos-core` (`extensions/calendar/`) | Published as `@semantos/calendar-ext`. See §"A3 addendum". |
| **A4** (VPS deploy) | Filesystem on VPS + systemd units authored in each repo's `systemd/` | See the new `VPS-BOOTSTRAP.md`. |
| **A5** (booking guard) | `semantos-core` for the guard interface + both bot repos for the wiring | See §"A5 addendum". |
| **OJT-PHASE-1..7** | `ojt` repo (not `apps/ojt/` under semantos-core) | Substitute `apps/ojt/…` with the `ojt` repo root in every path. |

---

## Addenda to existing phase prompts

These amendments override any conflicting instruction in the older per-phase docs. Apply them mentally when reading the older prompts; a future edit can inline them.

### A2 addendum
1. All paths `apps/brap/…` → `brap` repo root (`src/…`, `drizzle.config.ts`, etc.).
2. Dependencies replace `workspace:*` with pinned npm versions (`@semantos/intent: ^0.3.0`, etc.) resolved from GitHub Packages.
3. **Drizzle is the confirmed target** (was a default; now locked). No dual-ORM ambiguity.
4. `BRAPLexicon` lands as a PR to `semantos-core`, ships in `@semantos/semantos-sir@^0.3.0`, then `brap` bumps its dep.
5. Cutover still uses the `BRAP_USE_HANDLE_MESSAGE` feature flag, but within the `brap` repo alone.

### A3 addendum
1. Paths `extensions/calendar/…` stay the same — this work lands in `semantos-core`.
2. The extension is published as `@semantos/calendar-ext`. Bots consume it; they do not reach in.
3. `PlateView` is exported from the package as a React component; bots `import { PlateView } from '@semantos/calendar-ext/ui'`.
4. Migrations ship in the package as `@semantos/calendar-ext/migrations/*.sql` plus a bin `calendar-migrate` that the VPS runs once per deploy.
5. Todd's hat topology (`todd-operator`, `todd-handyman`, `todd-advisor`) is **seeded at deploy time from env**, not at package install — keeps the package domain-neutral.

### A4 addendum (see also VPS-BOOTSTRAP.md)
1. `/opt/semantos/` becomes `/opt/semantos-core/`, `/opt/ojt/`, `/opt/brap/` — three checkouts.
2. Each repo owns its own `systemd/` directory with the .service file. Deploy script copies to `/etc/systemd/system/`.
3. The Bun daemon is built from `semantos-core`; the two Next apps are built from their own repos.
4. All three services share `/etc/semantos/` for common config (cert, env.shared).

### A5 addendum
1. Guard interface (`CalendarGuard`) lives in `@semantos/intent`; implementation lives in `@semantos/calendar-ext`.
2. Each bot constructs `handleMessage({ calendarGuard: createCalendarGuard(sharedCalDb) })` at module init.
3. Cross-bot E2E test lives in `semantos-core` under `tests/e2e/inter-hat-booking.test.ts` and imports both bots as dev-dependencies (via npm, not workspace), OR runs both bots as separate HTTP servers with a test harness that curls them.
4. The second path (run both as separate HTTP servers) is more faithful and avoids coupling `semantos-core`'s test suite to your private app code. Recommended.

---

## Implications for the master doc

`ALIGNMENT-MASTER.md` as written still captures the **intent** correctly — but treat its §5 "Target Architecture" diagram as out-of-date in that `apps/ojt/` and `apps/brap/` are NOT under `semantos-core`. A corrected diagram is in `VPS-BOOTSTRAP.md` §1.

The four open decisions in §4 of the master collapse to:
- A (`/core` vs `/protocol`): keep `/core`. Decided.
- B (framework per app): keep Next.js per app, unchanged.
- C (ORM): **drizzle confirmed** for both bots and calendar ext.
- D (calendar skeleton): greenfield; build in `semantos-core` and publish.

---

## What this does NOT change

- OJT-PHASE-1 through OJT-PHASE-7 are still correct in content; only the base path changes from `apps/ojt/` to the `ojt` repo root.
- The calendar extension schema and API in A3 are unchanged.
- The VPS systemd + nginx + Postgres shape in A4 is unchanged in concept; see `VPS-BOOTSTRAP.md` for the concrete recipe.
- The inter-hat booking guard in A5 is unchanged in behavior; only the import paths and where the E2E test lives.
