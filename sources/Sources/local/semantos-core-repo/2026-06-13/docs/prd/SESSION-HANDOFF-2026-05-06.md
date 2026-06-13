---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/SESSION-HANDOFF-2026-05-06.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.720665+00:00
---

# Session Handoff — 2026-05-06

**Author**: Claude Opus 4.7 (1M context) session window, continuing operator's autonomous build pass.
**Window covers**: 2026-04 dogfood foundation work → D-DOG.1.0c Layer 1 promotion → tonight's iOS Simulator unblock for Bridget's field-node test.
**Reason for handoff**: conversation context expensive to maintain; bundle the state into durable docs the next session (Codex or Claude) can pick up cold.

---

## §1 — TL;DR for the next agent

Operator (Todd Price, Odd Job Todd) is running this codebase against his real handyman business. The Gmail + PDF dogfood path produces real job leads (RJR, Bricks, Clever Property quote requests + work orders + maintenance orders) into a signed cell-DAG graph. Helm SPA + mobile Flutter app render the graph with site / customer / attachment pivot navigation.

What just shipped (this session, ~22 dev-days compressed into ~3 wall-clock days via parallel agents):

- **Tier 1 (#340–#358)** — Gmail OAuth + ingest + extract + ratify pipeline shipped. 472 first-dogfood proposals → 72 v1 cells.
- **Tier 1.5–1.7 (#361–#366)** — point_of_contact extraction → job_type classification (Quote/Work/Maintenance only) → deep PDF extraction (primary tenant + agent + billing party + WO# + dates + photos) → per-attachment fan-out for forwarded-bundle emails.
- **D-DOG.1.0c (#367–#391)** — full Layer 1 promotion: v2 cell schemas + graph translator + per-cell BKDS signing + helm/mobile graph-aware UI + migration verb + canon updates. **20 PRs across 5 phases.**
- **#392 (tonight)** — iOS Simulator Firebase unblock for Bridget's field-node test.

Bridget needs to run `flutter run -d "iPhone 15 Simulator"` tomorrow against `apps/oddjobz-mobile` and walk the field-node ↔ brain pairing flow. The Firebase stub in PR #392 is what unblocks that.

The operator wants to ingest his actual gmails into the new signed graph next. Recipe is in §6.

---

## §2 — Repo state

- Repo: `/Users/toddprice/projects/semantos-core`
- Branch: `main`
- Latest commit: `5667c6b` (Firebase iOS-Simulator stub)
- Origin: `https://github.com/semantos/semantos-core`

**GitHub Actions CI is org-wide red on billing** ("recent account payments have failed"). All session PRs squash-merged via `gh pr merge --squash --delete-branch` on local-test-green confirmation, since CI is not gating. Operator should fix the GitHub org billing when convenient.

### Active worktrees (Codex parallel work)

```
/Users/toddprice/projects/semantos-core-jambox            [codex/jambox-semantic-three]
/Users/toddprice/projects/semantos-core-wallet-engine     [codex/wallet-engine-wrapup]
/Users/toddprice/projects/semantos-core-wallet-ux-followup [codex/wallet-browser-first-run-ux]
/Users/toddprice/projects/semantos-core-node-protocol     [node-protocol]
/private/tmp/jam-room-g-rebase                            [jam-room-g-mobile]
/private/tmp/wsite35-worktree                             [feat/wallet-wsite35-identity-certs] (prunable)
```

These are operator's parallel Codex sessions on orthogonal surfaces. See §4 for what each is delivering.

---

## §3 — What this session shipped (D-DOG.1.0c Layer 1 promotion)

### Cell-DAG architecture (now in place)

```
              site.v2           ← WHERE  (lookup-or-mint by lookupKey)
                │                         (29 Foedera Cres, key #177)
        ┌───────┼────────┐
        ▼       ▼        ▼
    customer customer customer  ← WHO  (lookup-or-mint by phone/email/name+role+site)
       (tenant) (tenant) (agent)        (each role-tagged: tenant|agent|owner|pm|sub-tradie|other)
        │       │        │
        └───────┼────────┘
                ▼
              job.v2                ← WHAT (FSM: lead → quoted → scheduled → in_progress
                │                          → completed → invoiced → paid → closed)
                │                     workOrderNumber, issuanceDate, dueDate, billingParty,
                │                     hasPhotos, photoCount, propertyKey, signedBy, signature
                ▼
            attachment.v2            ← HOW  (source PDF + photo metadata)
                                          sourceBlobKey + mimeType + pageCount + photoCount
```

Each cell is **BKDS-signed**: `derive(root, "oddjobz.cell-sign/v1", cellContentHash) → signingKey`. Per-cell rotation, fully recoverable from `root + scope + cellID`. Each signature uses a distinct derived pubkey — third parties cannot cluster cells by signing key without root access (privacy property).

### Phases delivered

| Phase | PRs | What landed |
|---|---|---|
| 1 — Schemas | #367 | v2 cell types (job/customer/site/attachment) + type-hash registry, v1 backward-compat preserved |
| Doc | #368 | D-DOG.1.0c matrix committed |
| 2A — Translator + stores | #369 #370 #371 #372 | sites_store_fs (new) + customers/attachments v2 + jobs v2 read path + handler graph-walk rewrite |
| 2B — RPC + TS + parity | #373 #374 #375 #376 | TS RPC parser + payload_hint forwarding + FS fallback graph + cross-store query handler + 35 byte-parity fixtures (zero divergences) |
| 3 — UI Wave 1 | #377 #378 | Helm + mobile JobList graph-aware (site / primary customer / due date / photos badge) |
| 3 — UI Wave 2 | #379 #380 #386 #387 #388 #389 | Helm site/customer/job-detail pivot routes + hash router; mobile site/customer/attachment pivot screens with inline PDF viewer |
| 4 — Signing | #390 | BKDS per-cell key derivation + verifier + `brain resign-pending` admin verb |
| 5 — Migration + docs | #391 | `legacy migrate-to-graph` verb + 3 new operator runbooks + canon updates |
| Bridget unblock | #392 | iOS Simulator Firebase stub |

### Test count growth across the session

Starting baseline → end: legacy-ingest +50, core/cell-ops +51, runtime/semantos-brain +103, apps/loom-svelte +66 (entirely new), apps/oddjobz-mobile +40+. **~250 new tests** across the deliverable.

### Reference matrix doc

`docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md` — the 19.5-dev-day plan. Every sub-deliverable now has a corresponding PR. Update its status table when the next session continues.

---

## §4 — Codex parallel-work map

These streams ran concurrently outside this session's window. **They're orthogonal to D-DOG.1.0c (cell-DAG promotion)** so they didn't conflict, but they're relevant to the next phases.

### 4.1 — Voice pipeline

- `4a4254c` — Wire Whisper + llama.cpp voice pipeline; 4-node dock; jobs offline cache
- `9b17fe5` — Add on-device model download UI to TalkNode
- `c03d52d` `d179330` `94774c8` — Android NDK + INTERNET permission + streaming SHA-256 fixes for whisper/llama_cpp Flutter bindings

**Implication for our roadmap**: **Tier 4 (voice triggers) is largely already shipped on the platform side.** What remains is wiring voice intents → SIRProgram → ratification path (so spoken "schedule visit at Foedera Cres next Tuesday" updates the job graph). Leverages all of Phase 1.7's structured fields.

### 4.2 — Helm v7 cockpit + jam-room redesign

- `a3f08e4` — Helm v7 cockpit design — Flutter mobile + Svelte brain helm
- `7a5b28c` — Rewire jam-room UI: Svelte 5 desktop + Flutter mobile redesign
- `bff8529` — jam-room: wire Phase A–G components into live app + streamline layout

**Implication**: helm SPA was upgraded under the hood while we built D-DOG.1.0c's graph-aware views on top. So far no conflicts surfaced; the D-DOG.1.0c routes (`/sites/[id]`, `/customers/[id]`, `/jobs/[id]`) plug into the v7 cockpit's hash router. **No action required** unless future Tier 2 work surfaces visual inconsistencies.

### 4.3 — Wallet UX

- `0e5504f` (#383), `974d36a` (#385), `5e40dd2` (#384) — first-run + plexus signup engine flow + smooth recovery UX
- `fad1fe6` (#381) — Bridget Doran bug-report fixes
- `9087020` (#382) — DNS seed for headers sync

**Implication for D-DOG.1.0c §2 (signing root)**: HatBkds is currently sourced from a deterministic data-dir-seeded scalar (PR #390 noted this). Production swap-in to a wallet-KEK-decrypted root waits on D-O5p's operator-root-priv source. The wallet UX work brings that closer; check `codex/wallet-engine-wrapup` for status.

### 4.4 — Oddjobz Meta ingestion (Tier 5 prerequisite)

- `0e18eb3` — feat(oddjobz): unify meta ingestion dispatch and attention

**Implication**: Tier 5 (Meta + Bricks summary ingestion) prerequisite is partially in place. When we run Tier 5, the Meta ingestion pipeline is already unified — we just route through the same `oddjobz.ratify_proposal` RPC the Gmail flow uses (PR #372).

---

## §5 — Open follow-ups (the bug-list)

Things the session became aware of but didn't fix. Sorted roughly by user-impact severity.

### High-impact / will-bite-soon

| # | Item | Where | Notes |
|---|---|---|---|
| 1 | View store dangling-slice hazards (chunked-list arena fix) | `runtime/semantos-brain/src/{sites,customers,jobs,attachments}_store_fs.zig` | Phase 4 routed around with `appendSigned` + `applySignedLine`; underlying hazard remains. `id_keys: ArrayList(u8)` relocates on grow at 3+ rows, invalidating earlier-inserted index keys. Proper fix: chunked-list arena (so growth doesn't relocate). Operator-affecting once cell counts get large. |
| 2 | HatBkds production root | `runtime/semantos-brain/src/hat_bkds.zig` + cli.zig wiring | Currently uses a deterministic data-dir-seeded scalar. Production swap-in to wallet-KEK-decrypted BRC-42 root waits on D-O5p's operator-root-priv source. Cells are signed + verifiable today but "operator's root" is auto-generated rather than wallet-tied. **Worth tracking**; may already be unblocked by Codex's wallet-engine-wrapup (see §4.3). |
| 3 | F.2 site_screen_test pre-existing failure | `apps/oddjobz-mobile/test/helm/site_screen_test.dart` | Test references `onAddressTap` parameter on `JobListRow`; the actual widget has `onTap`, `onPhotosTap`, `onCustomerTap` but no `onAddressTap`. Was masked when F.2 (PR #386) was salvaged from a credit-cap-stopped agent worktree. **Small fix** — either add `onAddressTap` to `JobListRow` or update the test to use the existing tap mechanism. |
| 4 | iOS push disabled (Firebase stub) | `apps/oddjobz-mobile/lib/src/push/firebase_push_adapter.dart` | PR #392 stubbed Firebase to unblock iOS Simulator. iOS background wakes are now disabled until Firebase is restored OR a native APNs shim is added. Android UnifiedPush still works. **In-session WSS live updates work on iOS** (HelmEventStream); only background wakes are affected. |
| 5 | FS fallback warning throttle | `runtime/legacy-ingest/src/cell-writer/brain-rpc.ts` | Bulk-ratify of 472 proposals spammed 472 copies of `[brain-rpc] WSS unavailable ... falling back to direct FS append`. Throttle to once per session. **Small.** |

### Medium-impact / nice-to-have

| # | Item | Where | Notes |
|---|---|---|---|
| 6 | Helm path-matcher unification | `apps/loom-svelte/src/App.svelte` | E.2 (#380) added a hash router for `#/sites/<id>`. E.3 (#379) and E.4 (#389) piggybacked on it for customer + job-detail routes. Self-resolving route components scattered across views. Should be unified into a single route table. |
| 7 | Helm WSS transport multiplex | `apps/loom-svelte/src/lib/oddjobz-query.ts` | One-shot WebSocket per request today; with 3-N RPCs per render this is fine. Wave 2 added more verbs; multiplexing onto the existing event-stream socket is the right move. Transport seam is built for single-file swap. |
| 8 | Helm DOM render tests | `apps/loom-svelte/tests/` | Test runner is `node --test --import tsx`, no Svelte renderer. Pure-function tests cover the joiner/coordinator logic but not the actual Svelte component output. Move to vitest + @testing-library/svelte for full coverage. |
| 9 | Wire format casing inconsistency | RPC layer (Zig + TS) | Tier 1.7 fields are camelCase (primaryContact, etc.); legacy 5 + proposal_id are snake_case. Functional but inconsistent. Normalise in a follow-up. |
| 10 | `legacy attachment <provider>:<item>:<n>` verb | `runtime/legacy-ingest/src/verb.ts` + new file | Decrypt + open source PDF for attachments (today helm/mobile shows metadata only with a "needs `legacy attachment` verb" message). |
| 11 | tsconfig moduleResolution in legacy-ingest | `runtime/legacy-ingest/tsconfig.json` | Pre-existing repo-wide TS config issue; `bun run check` reports `--moduleResolution: bundler` errors. Bun tests are the truth; tsc is purely advisory. Cleanup if convenient. |
| 12 | Operator's `.zshrc` alias persistence | `~/.zshrc` | Operator's shell alias `legacy='bun apps/legacy-cli/src/cli.ts'` doesn't persist across new shells. Investigate the `.zshrc` short-circuit. |

### Deferred (intentional)

| # | Item | Notes |
|---|---|---|
| 13 | Cold-tier signing | Per matrix §2 — deferred until operator-held economic value enters cells (post-Stripe era). |
| 14 | D-DOG.1.0e BSV anchoring | Cells anchor to BSV for outsider-verifiable history. Deferred until needed (today everything is local). |
| 15 | Tier 6 sovereign promotion | Lift legacy verbs into brain, drop the FS fallback warning permanently. Big architectural change; do after Tier 2/3 land so we know what the Semantos Brain-side verb shape needs to be. |
| 16 | GitHub Actions billing | Org-wide CI red on billing. Operator action — fix in GitHub org settings. |

---

## §6 — Recipe: ingest your gmails into the new signed graph

Operator workflow for tomorrow. **All commands run from `~/projects/semantos-core`** with the `legacy` shell alias active (or `bun apps/legacy-cli/src/cli.ts` substituted).

### 6.1 — Pull + verify

```bash
cd ~/projects/semantos-core
git pull origin main
git log --oneline -5  # should show 5667c6b at top
```

### 6.2 — Optional: back up first-dogfood data

```bash
mv ~/.semantos/data/oddjobz/jobs.jsonl{,.first-dogfood-bak}
mv ~/.semantos/data/oddjobz/legacy-ratifications.jsonl{,.first-dogfood-bak}
```

(Skip if you want migration to attempt re-ratifying them through the graph translator.)

### 6.3 — Migrate existing v1 cells to the signed graph

```bash
legacy migrate-to-graph                   # see what it'd do (no --dry-run since the verb defaults to acting; check with --dry-run if added)
```

Output: rows with proposal-store matches get re-ratified through `oddjobz.ratify_proposal` (now signed via Phase 4's BKDS); rows without matches get a `legacy_unsigned` marker. Helm/mobile show a "legacy" pill on those.

### 6.4 — Re-ingest with the new graph + structured extraction

```bash
legacy ingest gmail \
    --reextract \
    --query "(from:bricksandagent.com OR from:robertjamesrealty.com.au OR from:cleverproperty.com.au OR (from:todd.price.aus@gmail.com after:2026/05/04))"
```

This:
- Walks all four sender domains plus your two forwarded-bundle emails
- Re-extracts via the v0.5 prompt (job_type classification + Tier 1.7 deep PDF parse)
- Per-attachment fan-out turns each PDF in the bundles into its own proposal
- Writes graph (site + customers + job + attachments) via `oddjobz.ratify_proposal` if WSS is up; otherwise via the TS-side FS fallback (which writes the same graph shape)

### 6.5 — Verify graph populated

```bash
ls -la ~/.semantos/data/oddjobz/
# Should see: sites.jsonl, customers.jsonl, jobs.jsonl, attachments.jsonl, legacy-ratifications.jsonl
wc -l ~/.semantos/data/oddjobz/*.jsonl
```

### 6.6 — Open helm or mobile

Helm SPA: should show all the new jobs with site address + primary customer + due date + photos badge. Click address → site-pivot. Click customer → customer-pivot. Click row body → job detail.

Mobile (after Bridget's #392 unblocks the iOS Simulator): same graph navigation.

---

## §7 — What to do next session

The operator decides priority. Three tracks queued:

1. **Tier 2 — Backlog kanban** — graph-aware kanban view of jobs across the FSM states. PRD: `docs/prd/TIER-2-BACKLOG-KANBAN.md`.
2. **Tier 3 — Execution proposal engine** — uses `dueDate` from Tier 1.7 + 7am-7pm capacity model to propose a daily schedule. PRD: `docs/prd/TIER-3-EXECUTION-PROPOSAL-ENGINE.md`.
3. **Tier 5 — Meta + Bricks summary ingestion** — Codex's `0e18eb3` already unified Meta dispatch; just need Bricks weekly-summary ingest. **Quick.**

Lower-priority but useful:
- Tier 4 (voice triggers) — Codex shipped the platform; we wire voice → SIR → ratify
- Tier 6 (sovereign promotion) — lift legacy verbs into brain
- Open follow-ups §5 — pick the high-impact ones

Operator's pattern in this session: "do what's recommended, go." So **default recommendation: Tier 2 first** (operator-visible, highest-value-per-day, builds on D-DOG.1.0c's graph). Then Tier 5 (small, leverages Codex work). Then Tier 3.

---

## §8 — Operating model for the next session

Pattern that worked through 22 PRs in this window:

1. **Scope into the matrix** before firing agents. The D-DOG.1.0c matrix (`docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md`) was load-bearing — every PR cross-referenced it.
2. **Split aggressively.** Phase 2 had to split into 2A (4 PRs) and 2B (4 PRs); Phase 2A had to further split into A.1, A.2, A.3, A.4. Each agent sub-PR was bounded enough to fit one round-trip with full local-test verification.
3. **Trust agent stop-reports.** Several agents stopped before committing because they discovered the brief's premises didn't match code reality. Each was right. Treat their stop-reports as findings, not failures.
4. **Salvage uncommitted WIP** when credits run out mid-flight — most agents got past implementation; the cap usually hit during PR/merge. F.2/F.3/F.4/E.4 all salvaged (PR #386, #387, #388, #389) tonight.
5. **Don't auto-merge cosmetic PRs.** Operator WIP snapshots (e.g. PR #360) stay unmerged for review; only wholesale-shipping deliverables auto-merge via `gh pr merge --squash --delete-branch`.

GitHub Actions CI is red on billing org-wide. Local `bun test` + `zig build test` + `flutter test` are the source of truth until that's fixed.

---

## §9 — Cross-references

- **Architecture matrix**: `docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md`
- **Tier 2 PRD**: `docs/prd/TIER-2-BACKLOG-KANBAN.md`
- **Tier 3 PRD**: `docs/prd/TIER-3-EXECUTION-PROPOSAL-ENGINE.md`
- **Operator runbooks** (Phase 5 docs from PR #391):
  - `docs/operator-runbooks/cell-signing-bkds.md` — BKDS recovery model
  - `docs/operator-runbooks/job-graph.md` — graph navigation guide
  - `docs/operator-runbooks/dogfood-gmail.md` — end-to-end gmail dogfood (now §11 covers post-Layer-1 graph flow)
- **Sovereignty implications**: `docs/canon/sovereignty-cell-signing.md`
- **Glossary entries** added in PR #391: `oddjobz.cell-sign/v1`, `legacy migrate-to-graph`, `job.v2`/`customer.v2`/`site.v2`/`attachment.v2`
