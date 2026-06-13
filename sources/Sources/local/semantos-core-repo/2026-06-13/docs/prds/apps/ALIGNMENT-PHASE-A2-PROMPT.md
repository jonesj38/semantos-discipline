---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/ALIGNMENT-PHASE-A2-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.786735+00:00
---

# Phase A2 — BRAP Migration: Prisma→Drizzle, De-Vercel, Chat Through handleMessage, BRAPLexicon

**Companion of**: `REPO-TOPOLOGY.md`, `ALIGNMENT-MASTER.md` §5/§7/§8, `apps/OJT/OJT-PHASE-5-PROMPT.md`
**Prerequisites**: A1 v2 complete (`brap` is a standalone private repo that installs `@semantos/*` from GH Packages and still runs against Prisma).
**Estimated size**: the largest single phase. Budget a full weekend plus a day of soak.

> **Topology note (post-v2 revision)**: all paths `apps/brap/…` in this doc refer to the root of the **`brap` private repo**, not a workspace folder under `semantos-core`. Dependencies like `@semantos/intent` resolve from GitHub Packages, not `workspace:*`. The `BRAPLexicon` addition to `core/semantos-sir/` is a PR to `semantos-core` that ships in the next `@semantos/semantos-sir` release, which `brap` then bumps. Drizzle is the confirmed target (no dual-ORM fallback); the schema-diff harness exists to make the one-shot cutover safe. See `REPO-TOPOLOGY.md` §"A2 addendum" for the full list of path substitutions.

---

## Objective

Bring BRAP into structural parity with OJT and the semantos monorepo conventions. At the end of A2:
1. BRAP's database is drizzle on Postgres 16 (VPS-hosted or local), not Prisma on Neon.
2. BRAP no longer imports `@vercel/blob` or `@vercel/postgres`; document storage works against a local filesystem adapter (or an S3-compatible adapter that the operator configures via env).
3. BRAP's `/api/chat` route triages through `runtime/intent.handleMessage` and the LLM receives patch-chain context (the write-only pattern from the audit is replaced with read-then-write).
4. A new `BRAPLexicon` is added to `core/semantos-sir/src/lexicons.ts` so patches from BRAP's LLM can be validated against canonical cell keys, threshold verbs, and mitigation actions.
5. BRAP's Stripe webhook still works, but from a route handler that runs inside the Next app and is reachable through the daemon's nginx route (no Vercel function).
6. BRAP's NextAuth setup is preserved; a shared hat-context adapter resolves the NextAuth session into the same `Identity` shape that OJT's phone-cert adapter produces.
7. Paying customers are not disrupted. A feature flag (`BRAP_USE_HANDLE_MESSAGE=true/false`) toggles the new path; dual-writes to Prisma + drizzle run for one week; the old path is removed only after soak.

This phase does NOT change any LLM prompt text. Prompt evolution is deferred to a follow-up.

---

## Inputs / Reference

- BRAP audit (from chat-prompt survey):
  - Chat: `apps/brap/src/app/api/chat/route.ts` — agentic tool-use loop, tool `update_scorecard`, MAX_TOOL_ROUNDS=5
  - Prisma: `apps/brap/src/prisma/schema.prisma` (NextAuth + app + compiler layers; 388 lines)
  - Internal semantos packer: `apps/brap/src/lib/brem-compiler/semantos/` (header.ts, cellPacker.ts, serialize.ts, replay.ts)
  - Prompts: `apps/brap/src/lib/brem/prompts/system.ts` (117 lines), `apps/brap/src/lib/brem/chat-prompt.ts` (434 lines)
  - Vercel deps: `@vercel/blob`, `@vercel/postgres`
- Semantos:
  - `runtime/intent/src/handle-message.ts` — the triage entry point
  - `runtime/intent/src/conversation-patch.ts` — `ConversationPatchShape`
  - `core/semantos-sir/src/lexicons.ts` — existing `JuralLexicon`, `PropertyManagementLexicon` (lines 45–57, 217–229). Add `BRAPLexicon` here.
- OJT counterpart: `apps/OJT/OJT-PHASE-5-PROMPT.md` (chatService through handleMessage) is the template — mirror its structure.

---

## Tasks

### 1. Port the Prisma schema to drizzle

- [ ] Create `apps/brap/src/db/schema.ts` with drizzle definitions mirroring `prisma/schema.prisma`:
  - NextAuth: `accounts`, `sessions`, `users`, `verificationTokens` — use the drizzle NextAuth adapter helpers (`drizzle-orm/next-auth`) so session storage shape stays identical.
  - App: `projects`, `messages`, `projectDocuments`, `reports`, `quizResults`, `creditTransactions`.
  - Compiler: `projectStates`, `stateEvents`, `projectEvidences`, `projectMitigations`, `semanticCells`.
- [ ] Preserve all JSONB columns (`cellScores`, `extensions`, `classification`, `cellStates`, `delta`) as `jsonb` in drizzle.
- [ ] Preserve denormalized int columns on `projectStates` (na, nc, ns, se, sm, sf, ls, lr, lp).
- [ ] Preserve `semanticCells.rawHeader` / `rawPayload` as `bytea`.
- [ ] Foreign keys and cascade behavior must match Prisma (diff-check below).

### 2. Schema diff harness

- [ ] Write `apps/brap/scripts/schema-diff.ts` that:
  - Runs `prisma migrate diff --from-empty --to-schema-datamodel prisma/schema.prisma --script` and captures SQL.
  - Runs `drizzle-kit generate` and concatenates the generated SQL.
  - Normalizes both (lowercase identifiers, sort columns, strip comments) and diffs.
  - Fails with a non-zero exit if they diverge in a way that touches column name, type, nullability, default, or FK onDelete action.
- [ ] Run on CI; must pass before cutover.

### 3. Repository layer rewrite

- [ ] Identify every file that imports `@/lib/prisma` or uses `prisma.*` under `apps/brap/src/`. Catalog them.
- [ ] Introduce `apps/brap/src/db/client.ts` exporting a drizzle `db` built on `postgres-js` (not `@vercel/postgres`).
- [ ] For each repository (`ProjectRepository`, `ProjectStateRepository`, `StateEventRepository`, `EvidenceRepository`, `MitigationRepository`, user repos, etc.):
  1. Duplicate the class with a drizzle implementation (e.g. `ProjectRepositoryDrizzle`).
  2. Behind a feature flag `BRAP_DB=prisma|drizzle`, the factory returns the right one.
  3. For write paths, optionally dual-write (write to both, read from the flagged one) during a soak window.
- [ ] Compiler-bridge (`compilerBridge.ts`) must write to BOTH backends during soak, so a rollback does not lose audit events.

### 4. Remove Vercel storage

- [ ] Replace `@vercel/blob` with a small `apps/brap/src/lib/blob.ts` that exposes `put(key, buffer, contentType)` and `get(key)`, backed by:
  - Dev / VPS default: local FS under `$BRAP_BLOB_DIR` (e.g. `/var/semantos/brap/blob`).
  - Optional: S3-compatible adapter via `@aws-sdk/client-s3` gated on `BRAP_BLOB_BACKEND=s3`.
- [ ] Update `/api/project/[id]/upload` and `/api/assess/upload` routes to use the new adapter.
- [ ] Replace `@vercel/postgres` with `postgres` (postgres-js) — drizzle's supported driver on a VPS.
- [ ] Remove `@vercel/blob` and `@vercel/postgres` from `apps/brap/package.json`. CI fails if they reappear.
- [ ] Delete `apps/brap/vercel.json`. The app no longer targets Vercel.
- [ ] Remove any `export const runtime = 'edge'` or `maxDuration` exports from routes — the 60-second cap is a Vercel concept; on the VPS we bound via nginx / the HTTP server.

### 5. Chat route through handleMessage

- [ ] Refactor `apps/brap/src/app/api/chat/route.ts` so every turn:
  1. Loads the last N `ConversationPatch` entries for this project from the db (via a new `conversationPatches` table or by reusing `StateEvent` + `Message` if shapes align).
  2. Calls `handleMessage({ userText, conversationId, projectId, actorIdentity })` from `@semantos/intent`.
  3. Uses the returned `triageHint` (PROPOSES / RATIFIES / NO_INTENT) to decide whether to call the LLM or short-circuit.
  4. Passes the last N patches into the LLM context as a "CONVERSATION HISTORY" block.
  5. After the LLM returns `update_scorecard` tool calls, writes them as `ObjectPatch` entries with `lexicon: 'brap'` (see §6) before denormalizing into `projects.cellScores` as today.
- [ ] Feature-flag the whole new path behind `BRAP_USE_HANDLE_MESSAGE`. Default false on first deploy; flip to true after soak.
- [ ] Preserve the SSE streaming contract — clients must not see a protocol change.
- [ ] Preserve the 5-round tool-use cap and 3-round continuation cap.

### 6. Add BRAPLexicon

- [ ] In `core/semantos-sir/src/lexicons.ts`, add a new `BRAPLexicon`:
  ```ts
  export const BRAPLexicon = {
    id: 'brap',
    verbs: ['score', 'refine', 'probe', 'mitigate', 'escalate', 'classify', 'accept', 'reject'] as const,
    categories: ['na','nc','ns','se','sm','sf','ls','lr','lp'] as const,
    // cell keys come from brem-agent's 9-cell matrix
  };
  ```
- [ ] Export it from `core/semantos-sir/src/index.ts`.
- [ ] Add a unit test in `core/semantos-sir/tests/lexicons.test.ts` mirroring the Jural + PropMgmt tests.
- [ ] In the BRAP chat route, pass `lexicon: 'brap'` on every `ObjectPatch` the agent emits.
- [ ] Add a validator that rejects a BRAP patch whose verb or category is outside the lexicon; the chat route falls back to "NO_INTENT" for that patch and logs the violation.

### 7. Stripe webhook portability

- [ ] Keep `apps/brap/src/app/api/stripe/webhook/route.ts` as-is in shape; it's a Next route handler and works off-Vercel.
- [ ] Verify webhook signature validation uses the standard Stripe SDK (not Vercel-specific).
- [ ] In Stripe dashboard, add a second webhook endpoint pointing to `https://brap.todd.example/api/stripe/webhook`. Do NOT delete the Vercel endpoint until A4 is green for 30 days.

### 8. NextAuth → shared hat-context

- [ ] Create `apps/brap/src/lib/identity.ts` that takes a NextAuth session and returns a semantos `Identity` with:
  - `certId = sha256("brap:role:email:" + lowercased email)`
  - `role = 'end_user' | 'operator'`
  - `displayName`, `email` preserved
- [ ] Operator (Todd) is identified by a constant `BRAP_OPERATOR_EMAIL`; his `Identity` is enriched with `hatId = 'todd-operator'` — the SAME hatId OJT uses for Todd's operator hat. This single shared hatId is what lets A5's booking guard know "both bots are being operated by the same person".
- [ ] Remove any Prisma-specific identity helpers that no longer fit; keep the adapter lean.

### 9. Tests

- [ ] Unit: drizzle repos match Prisma repos for representative fixtures (property tests: round-trip a Project, assert equal).
- [ ] Integration: `pnpm --filter @semantos/brap test:integration` boots a Postgres instance (testcontainers or a well-known `DATABASE_URL`), runs migrations, exercises each route.
- [ ] E2E: a 10-step scripted project (upload doc → extract → score → refine → threshold → mitigate → accept) passes through both the old Prisma path (BRAP_DB=prisma) and the new drizzle path (BRAP_DB=drizzle) with identical final `ProjectState.stateHash`.
- [ ] E2E for handleMessage: a 5-turn chat run through `BRAP_USE_HANDLE_MESSAGE=true` yields the same `cellScores` as the same script with the flag false.
- [ ] Lexicon: every tool_use output from the LLM in a 50-fixture replay yields a valid BRAP patch (verb ∈ lexicon, category ∈ lexicon). ≥ 95% required.

### 10. Soak & cutover

- [ ] Deploy to staging VPS with `BRAP_DB=drizzle` + `BRAP_USE_HANDLE_MESSAGE=false`. Run for 48 hours against mirrored production traffic (replay logs or a small beta cohort). Monitor error rates.
- [ ] Flip `BRAP_USE_HANDLE_MESSAGE=true`. Monitor for 7 days.
- [ ] Remove Prisma client code, drop `prisma/` folder, remove the feature flag. Land as a single "chore(brap): remove prisma, make handleMessage default" commit.
- [ ] Keep Vercel deployment warm for another 30 days as rollback insurance.

---

## Acceptance Criteria

1. `apps/brap/package.json` has no `@vercel/*` deps and no `prisma`/`@prisma/client` deps.
2. `apps/brap/prisma/` does not exist.
3. `apps/brap/src/db/schema.ts` is the sole DB schema source; `drizzle-kit migrate` is the migration tool.
4. `BRAP_USE_HANDLE_MESSAGE` is not present as a flag — the handleMessage path is the only path.
5. `apps/brap/src/app/api/chat/route.ts` imports `handleMessage` from `@semantos/intent` and pre-pends the last N `ConversationPatch` entries to LLM context.
6. `core/semantos-sir/src/lexicons.ts` exports `BRAPLexicon` with the full cell-key + verb set.
7. Every `ObjectPatch` BRAP writes has `lexicon: 'brap'`.
8. The fixture replay shows ≥ 95% of LLM tool outputs pass BRAP lexicon validation.
9. Stripe webhooks are delivered and acknowledged on the VPS endpoint; logs show ≥ 99% 2xx.
10. Soak period ran ≥ 7 days with `BRAP_USE_HANDLE_MESSAGE=true` and error rate ≤ 0.5%.
11. A deleted-then-restored Project round-trips perfectly against the drizzle schema (CI test).
12. The operator's `certId` is identical across OJT and BRAP when Todd signs into both.

---

## Out of Scope

- Prompt rewriting — the 434-line chat prompt stays the same. A future phase may unify OJT's and BRAP's prompts against a shared extraction vocabulary.
- Unifying end-user identity across OJT (phone) and BRAP (email). Operator identity is shared; end-user identity stays per-app.
- The calendar extension (A3) and the booking guard (A5). A2 lands the substrate they need, nothing more.

---

## Rollback

- Feature flags make cutover reversible until the Prisma code is deleted.
- During soak, flip `BRAP_USE_HANDLE_MESSAGE=false` and BRAP reverts to the legacy chat loop with zero data migration.
- During the dual-write window, flip `BRAP_DB=prisma` and BRAP reads from Prisma while still writing to both — all data is current on Prisma.
- After Prisma removal, rollback requires the pre-removal tag; plan a `v-prisma-last` git tag at the soak boundary so it is always recoverable in one `git checkout`.
