---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/ALIGNMENT-PHASE-A1-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.787299+00:00
---

# Phase A1 (v2) — Carve Out `ojt` and `brap` as Standalone Private Repos; Set Up Package Publishing from `semantos-core`

**Supersedes**: A1 v1 (which merged both bots into `semantos-core/apps/`)
**Companion of**: `REPO-TOPOLOGY.md` and `VPS-BOOTSTRAP.md`
**Prerequisites**: you have GitHub org / user account that can host two new private repos and can read/write GitHub Packages under a `@semantos` scope.
**Estimated size**: one to two focused days. Mechanical, but touches three repos.

---

## Objective

Stand up three clean repos:
1. `semantos-core` — unchanged in content, newly configured to publish `@semantos/*` packages.
2. `ojt` — a new private repo populated from `/sessions/nifty-bold-sagan/mnt/oddjobtodd/` as a standalone Next.js app that installs `@semantos/*` from GitHub Packages.
3. `brap` — a new private repo populated from `/sessions/nifty-bold-sagan/mnt/brap-vercel/data/brem-agent/` on the same pattern.

At the end of A1:
- All three repos build locally (`pnpm install && pnpm build`) against published packages (or a locally-linked preview during the cutover week).
- Neither `ojt` nor `brap` depends on `workspace:*` anything.
- `semantos-core` has a release workflow that publishes versioned `@semantos/*` packages to GitHub Packages on tagged merges to `main`.
- No behavior change in either bot. They still connect to the same DBs and API keys. Routes still respond the same way.

---

## Inputs

- Source trees (copy, do not move):
  - `/sessions/nifty-bold-sagan/mnt/oddjobtodd/`
  - `/sessions/nifty-bold-sagan/mnt/brap-vercel/data/brem-agent/`
- `semantos-core` at `/sessions/nifty-bold-sagan/mnt/semantos-core/`
- Packages to publish from `semantos-core` (see `REPO-TOPOLOGY.md`):
  - `@semantos/intent` ← `runtime/intent/`
  - `@semantos/session-protocol` ← `runtime/session-protocol/`
  - `@semantos/protocol-types` ← `core/protocol-types/`
  - `@semantos/semantos-sir` ← `core/semantos-sir/`
  - `@semantos/calendar-ext` ← `extensions/calendar/` (A3 lands this; for A1 it is optional)

---

## Part 1 — Configure publishing from `semantos-core`

### 1.1 Verify each package is publish-ready

For each of the five packages:
- [ ] `package.json` has a `"name"` of `@semantos/<pkg>`, a valid `"version"` (start at `0.1.0` if unset), a `"main"` or `"exports"` pointing at the built output, a `"files"` array listing what to include, `"publishConfig": { "registry": "https://npm.pkg.github.com", "access": "restricted" }`.
- [ ] `tsconfig.json` emits `.d.ts` and JS into `dist/` on `pnpm --filter <pkg> build`.
- [ ] No `workspace:*` deps on sibling packages — replace with the same `^0.1.0` versions (consumers resolve from the registry).
- [ ] `peerDependencies` used where appropriate (e.g. `drizzle-orm` in `@semantos/calendar-ext`).

### 1.2 Add changesets

- [ ] Install `@changesets/cli` at root: `pnpm add -Dw @changesets/cli && pnpm changeset init`.
- [ ] Configure `.changeset/config.json` to target the five packages, set `access: "restricted"`, `baseBranch: "main"`.
- [ ] Document the flow in `docs/PUBLISHING.md`: you author changesets with `pnpm changeset`, CI runs `pnpm changeset version && pnpm -r publish` on release.

### 1.3 GitHub Actions release workflow

- [ ] Add `.github/workflows/release.yml`:
  ```yaml
  name: release
  on: { push: { branches: [main] } }
  jobs:
    release:
      runs-on: ubuntu-22.04
      permissions: { contents: write, packages: write }
      steps:
        - uses: actions/checkout@v4
          with: { fetch-depth: 0 }
        - uses: pnpm/action-setup@v4
        - uses: actions/setup-node@v4
          with: { node-version: 20, registry-url: 'https://npm.pkg.github.com', scope: '@semantos' }
        - run: pnpm install --frozen-lockfile
        - run: pnpm -r build
        - uses: changesets/action@v1
          with:
            publish: pnpm -r publish --access restricted
          env:
            GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
            NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  ```
- [ ] Dry-run publish on a feature branch using `npm publish --dry-run` to catch missing `files` fields.
- [ ] First real publish produces `@semantos/intent@0.1.0`, etc., visible in the repo's Packages tab.

### 1.4 Consumer auth

- [ ] Create a classic PAT (Todd-owned) with `read:packages`. Store it in a password manager as `GITHUB_PAT_READ_PACKAGES`.
- [ ] This PAT is what both bots' `.npmrc` will use during local install and on the VPS.
- [ ] If you anticipate open-sourcing `semantos-core` later, keep the PAT-based flow — switching to public npm is a one-liner `.npmrc` change when the time comes.

---

## Part 2 — Create the `ojt` repo

### 2.1 Initialize

- [ ] Create a private GitHub repo named `ojt` (under your user or the same org as `semantos-core`).
- [ ] Clone locally: `git clone git@github.com:toddprice/ojt.git` (adjust org).

### 2.2 Copy the source tree

- [ ] `cp -R /sessions/nifty-bold-sagan/mnt/oddjobtodd/. ojt/` (dot after source = include dotfiles).
- [ ] Delete: `ojt/node_modules/`, `ojt/.next/`, `ojt/.git/` (the nested one from the old repo), `ojt/pnpm-lock.yaml` (you'll regenerate), `ojt/plexus-core/` (the dormant vendored folder — stays out; if you want it as a seed, archive to `semantos-core/archive/ojt-plexus-core/`).

### 2.3 Configure package resolution

- [ ] `ojt/.npmrc`:
  ```
  @semantos:registry=https://npm.pkg.github.com
  //npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}
  always-auth=true
  ```
- [ ] `ojt/package.json`:
  - `"name": "ojt"` (not scoped — this is a private app, not a publishable package)
  - `"private": true`
  - `"packageManager": "pnpm@9.x.x"` (match whatever `semantos-core` uses)
  - Replace any path imports with `@semantos/*` deps pinned at the version A1 just published (e.g. `"@semantos/intent": "^0.1.0"`).
- [ ] `ojt/.env.example` — every env var the bot needs, with short comments. At minimum: `DATABASE_URL`, `CALENDAR_DATABASE_URL`, `ANTHROPIC_API_KEY`, `SEMANTOS_ADMIN_CERT`, `OPERATOR_PHONE_E164`.

### 2.4 Smoke tests

- [ ] Export `GITHUB_TOKEN=<the PAT>` in your shell, then `pnpm install` in `ojt/`. Should resolve `@semantos/*` from GH Packages.
- [ ] `pnpm dev` — OJT boots on :3000. Chat route responds as it did before.
- [ ] Existing OJT tests (drizzle + Slice 4/5 integration tests that live in `oddjobtodd`) run: `pnpm test`. Should pass unchanged.

### 2.5 Systemd stub

- [ ] `ojt/systemd/semantos-ojt.service` — unit file for VPS. Content matches `ALIGNMENT-PHASE-A4-PROMPT.md` §4. Lives in the repo so deploys can copy it in.

### 2.6 Commit, push, add CI

- [ ] Initial commit: "feat: carve ojt out of oddjobtodd; consume @semantos packages".
- [ ] Add `.github/workflows/ci.yml`: install, build, typecheck, test on push/PR.
- [ ] Push to `origin/main`.

---

## Part 3 — Create the `brap` repo

Mirror Part 2 for BRAP, with these differences:

### 3.1 Source

- [ ] `cp -R /sessions/nifty-bold-sagan/mnt/brap-vercel/data/brem-agent/. brap/`
- [ ] Delete: `brap/node_modules/`, `brap/.next/`, `brap/.vercel/`, `brap/.git/`, `brap/pnpm-lock.yaml` or `package-lock.json`.
- [ ] Keep `brap/prisma/` untouched for now (A2 ports it; A1 must preserve runnable state).

### 3.2 Package.json + npmrc

- [ ] Same `.npmrc` as OJT.
- [ ] `"name": "brap"`, `"private": true`.
- [ ] Keep `@vercel/blob`, `@vercel/postgres`, `@prisma/client`, `prisma` — A2 removes them; A1 must not break the app.
- [ ] Add `@semantos/*` deps but do NOT import from them yet (A2 writes the imports).
- [ ] `"start": "next start -p 3001"` so the VPS can run both bots concurrently.

### 3.3 Siblings

- [ ] `brem-data/`, `brem-data-review/` (BREM methodology reference datasets) — move under `semantos-core/archive/brem-data/` or a separate private repo. Do NOT bundle inside the `brap` app repo — the dataset will inflate deploy time.
- [ ] `brem-consultant` (Claude skill package) — not part of the bot runtime; archive separately.

### 3.4 Smoke test

- [ ] `pnpm install && pnpm dev` — BRAP boots on :3001, chat still works end-to-end against the current Prisma/Neon setup. A1 does not touch the DB.

### 3.5 Systemd stub

- [ ] `brap/systemd/semantos-brap.service` with port 3001 and working dir `/opt/brap/`.

### 3.6 Commit + push + CI

- [ ] Same shape as OJT.

---

## Part 4 — Local preview alternative (during the cutover week)

If GH Packages is flaky or you're iterating hard:

- [ ] `pnpm link --global` from each `semantos-core` package, then `pnpm link --global @semantos/intent` inside each bot repo. Fully local, no publish required.
- [ ] Use this for same-day iteration on breaking package changes. Commit no `pnpm-lock.yaml` changes until you're back on the published versions.
- [ ] An alternative for CI/deploys: `verdaccio` as a local npm mirror on the VPS. Overkill for solo ops; skip.

---

## Acceptance Criteria

1. Three repos exist: `semantos-core` (existing), `ojt` (new, private), `brap` (new, private).
2. `semantos-core` publishes at least `@semantos/intent@0.1.0` and `@semantos/protocol-types@0.1.0` to GitHub Packages. Other packages publish as they're updated.
3. `ojt/.npmrc` and `brap/.npmrc` both authenticate to GH Packages via `GITHUB_TOKEN`.
4. `cd ojt && pnpm install && pnpm build && pnpm test` exits 0.
5. `cd brap && pnpm install && pnpm build && pnpm test` exits 0 (Prisma still present; this is A1, not A2).
6. Neither bot references `oddjobtodd` or `brap-vercel` paths anywhere.
7. `semantos-core`'s git log has no new commits adding `apps/ojt/` or `apps/brap/` content (the bots live in their own repos, not here).
8. `docs/PUBLISHING.md` in `semantos-core` documents the release flow end-to-end.
9. GitHub Actions workflows exist in all three repos: release in `semantos-core`, CI (install + build + test) in `ojt` and `brap`.
10. Two systemd unit files exist, one in each bot repo's `systemd/` directory, ready for A4 to consume.

---

## Out of Scope

- Any Prisma → drizzle work in BRAP (A2).
- Any chat-through-handleMessage integration (OJT-PHASE-5 for OJT; A2 for BRAP).
- The calendar extension (A3).
- VPS deploy (A4).
- Inter-hat booking guard (A5).
- Prompt changes.
- Open-sourcing `semantos-core` (independent decision, not blocking).

---

## Rollback

- Delete the `ojt` and `brap` private repos. Your originals at `/sessions/nifty-bold-sagan/mnt/oddjobtodd/` and `/sessions/nifty-bold-sagan/mnt/brap-vercel/data/brem-agent/` were copied from, not moved — nothing is lost.
- Unpublishing GH Packages is possible within 30 days of publish; after that, bump the version and stop using the old one.
- The release workflow in `semantos-core` can be disabled by commenting out the `release.yml` trigger.
