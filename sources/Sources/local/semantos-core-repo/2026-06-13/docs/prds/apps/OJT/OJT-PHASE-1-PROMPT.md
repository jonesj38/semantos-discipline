---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/OJT/OJT-PHASE-1-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.789743+00:00
---

# OJT Phase 1 Execution Prompt — Drizzle Federation Fields

> Paste this prompt into a fresh session to execute Phase 1 of the OJT
> migration. Repo: `oddjobtodd`. Branch: `feat/sem-patches-federation-fields`.

## Context

You are working in the `oddjobtodd` repo at
`/sessions/nifty-bold-sagan/mnt/oddjobtodd`. OJT is a Next.js + drizzle
intake bot that has its own semantic kernel layer in
`src/lib/semantos-kernel/schema.core.ts`, defining `sem_objects`,
`sem_object_patches`, `sem_evidence`, `sem_state`, `sem_participants`.

The `sem_object_patches` table is 80% structurally compatible with
semantos-core's `ObjectPatch` type from
`semantos-core/runtime/services/src/types/loom.ts`. It is missing four
fields needed for federation: `timestamp` (unix ms), `facet_id`,
`facet_capabilities`, and the Slice 4 `lexicon` attribution field.

It also has no table for storing `SignedBundle` envelopes — the
signature + signer + recipient metadata produced by Slice 5a–5c.

Phase 1 closes both gaps with a drizzle migration and a backfill script.

**Why this matters**: every later phase depends on these fields. Phase 5
writes `lexicon` from the intent pipeline. Phase 4's `/federation/bundle`
endpoint persists envelopes. Phase 7's gate test asserts on
`patch.lexicon` and `patch.facet_id`. Phase 1 must ship first.

---

## CRITICAL: READ THESE FILES FIRST

Before writing any migration, read these files.

**OJT side (the current schema):**
- `src/lib/semantos-kernel/schema.core.ts` — the drizzle schema for
  `sem_objects`, `sem_object_patches`, `sem_evidence`, `sem_state`,
  `sem_participants`. Understand `patchKind`, `delta`, `prevStateHash`,
  `newStateHash`, `source`, `evidenceRef`, `authorObjectId`, `linearity`,
  `consumed`.
- `drizzle/` folder — the migration history. Numbering convention
  (`0000_*.sql` through `0007_*.sql`). Note how the existing migrations
  are written.
- `drizzle.config.ts` — drizzle-kit config (dialect, schema path, output
  folder).
- `package.json` — drizzle scripts (likely `db:migrate`, `db:push`,
  `db:generate`).
- `src/lib/services/chatService.ts` — where `sem_object_patches` is
  written today via `recordStateSnapshot()`-type calls. Understand which
  columns are being populated, so the backfill for `timestamp` is
  correct.

**Semantos-core side (the target shape):**
- `/sessions/nifty-bold-sagan/mnt/semantos-core/runtime/services/src/types/loom.ts`
  — the `ObjectPatch` type. Fields: `id`, `kind`, `timestamp`, `delta`,
  `facetId?`, `facetCapabilities?`, `lexicon?`.
- `/sessions/nifty-bold-sagan/mnt/semantos-core/runtime/intent/src/conversation-patch.ts`
  — `ConversationPatchShape` and `writeConversationPatch`.
- `/sessions/nifty-bold-sagan/mnt/semantos-core/runtime/session-protocol/src/bundle-envelope.ts`
  — `SignedBundle<T>` structure: `version`, `payload`, `signedAt`,
  `signer` (`{ bca, pubkeyHex, certId? }`), `recipient?`, `signature`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. NO DATA LOSS

The backfill must not drop or corrupt any existing row. If a column
cannot be populated from existing data, the backfill inserts NULL and
the column must be declared nullable (with a documented "pre-federation"
meaning).

### 2. FORWARD AND BACKWARD MIGRATIONS

Every migration must have a working `down` (rollback) statement. If
drizzle-kit's default rollback is insufficient for the new table, write
an explicit `DROP TABLE IF EXISTS sem_signed_bundles` in a reverse
migration file.

### 3. TYPES MATCH SEMANTOS EXACTLY

Column types must match the TypeScript shapes in semantos-core:

- `timestamp` is Unix **milliseconds** as `bigint` (NOT `timestamptz`)
- `facet_id` is `text` (free-form identifier; no FK)
- `facet_capabilities` is `integer[]` (Postgres array, not a comma
  string, not JSONB)
- `lexicon` is `varchar(100)` — matches the longest lexicon name
  (`'property-management'`) with room to spare

For bundle envelope columns:

- `signer_pubkey_hex` is `varchar(66)` — 33-byte compressed secp256k1 as
  hex = 66 chars
- `signature` is `varchar(144)` — hex DER ECDSA can reach ~144 chars
- `signer_cert_id` is `varchar(64)` — SHA-256 hex
- `signer_bca` is `varchar(45)` — IPv6 max length

### 4. INDEXES WHERE THE HOT PATH LOOKS THEM UP

Phase 4's `/federation/bundle` endpoint will look up envelopes by
`patch_id` (inbound verification) and by `direction` (audit queries).
Index both. No other indexes yet — add them when a query is slow,
not speculatively.

### 5. NO CHANGES TO EXISTING CODE PATHS

This phase is schema-only. Do NOT modify `chatService.ts` or any caller
of the new columns. Those changes belong to Phase 5. The only code
change in this phase is the drizzle schema module itself.

### 6. PGLITE AND POSTGRES BOTH WORK

OJT uses PGlite in dev (`pglite-data/`) and Postgres in production.
The migration SQL must run against both. Avoid Postgres-only syntax
(e.g., `CREATE INDEX CONCURRENTLY` is not supported in a migration
transaction; plain `CREATE INDEX` is fine).

---

## PART 0: GIT HYGIENE

### 0.1 Assess current state

```bash
cd /sessions/nifty-bold-sagan/mnt/oddjobtodd
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Ensure clean working tree

If there are uncommitted changes, either commit them on their existing
branch or stash. Do not mix unrelated work into this phase's branch.

### 0.3 Verify prerequisites exist

```bash
ls src/lib/semantos-kernel/schema.core.ts
ls drizzle.config.ts
ls drizzle/
```

If the kernel schema file is missing, STOP — OJT has drifted from
the audit state and this phase's assumptions are invalid.

### 0.4 Create the phase branch

```bash
git checkout -b feat/sem-patches-federation-fields
```

---

## Step 1: Extend `sem_object_patches` with four federation columns (D1.1)

### 1.1 Edit the drizzle schema

File: `src/lib/semantos-kernel/schema.core.ts`

Inside the `semObjectPatches` table definition, add:

```ts
timestamp: bigint('timestamp', { mode: 'number' }),        // unix ms, nullable (pre-federation rows get backfilled from created_at)
facetId: text('facet_id'),                                  // who authored — hat/facet string
facetCapabilities: integer('facet_capabilities').array(),   // Postgres integer[]
lexicon: varchar('lexicon', { length: 100 }),               // 'jural' | 'property-management' | ... | null
```

All four columns are NULLABLE. No defaults.

### 1.2 Generate the migration

```bash
bun run db:generate    # or the equivalent drizzle-kit command from package.json
```

This produces `drizzle/0008_<name>.sql`. Inspect it. It must contain:

```sql
ALTER TABLE "sem_object_patches" ADD COLUMN "timestamp" bigint;
ALTER TABLE "sem_object_patches" ADD COLUMN "facet_id" text;
ALTER TABLE "sem_object_patches" ADD COLUMN "facet_capabilities" integer[];
ALTER TABLE "sem_object_patches" ADD COLUMN "lexicon" varchar(100);
```

Commit: `feat(ojt-p1/D1.1): add federation columns to sem_object_patches`

---

## Step 2: Create `sem_signed_bundles` table (D1.2)

### 2.1 Add the table to the drizzle schema

File: `src/lib/semantos-kernel/schema.core.ts`

```ts
export const semSignedBundles = pgTable('sem_signed_bundles', {
  id: text('id').primaryKey(),
  patchId: text('patch_id')
    .notNull()
    .references(() => semObjectPatches.id, { onDelete: 'cascade' }),

  bundleVersion: smallint('bundle_version').notNull().default(1),

  // Signer (always present)
  signerBca: varchar('signer_bca', { length: 45 }).notNull(),
  signerPubkeyHex: varchar('signer_pubkey_hex', { length: 66 }).notNull(),
  signerCertId: varchar('signer_cert_id', { length: 64 }),

  // Recipient (optional — unaddressed bundles are broadcast-style)
  recipientBca: varchar('recipient_bca', { length: 45 }),
  recipientPubkeyHex: varchar('recipient_pubkey_hex', { length: 66 }),
  recipientCertId: varchar('recipient_cert_id', { length: 64 }),

  signature: varchar('signature', { length: 144 }).notNull(),
  signedAt: timestamp('signed_at', { withTimezone: false }).notNull(),

  direction: varchar('direction', { length: 10 }).notNull(),
  // 'inbound' | 'outbound' — CHECK constraint added below

  verified: boolean('verified').default(false),
  createdAt: timestamp('created_at').defaultNow(),
}, (t) => ({
  patchIdx: index('sem_signed_bundles_patch_idx').on(t.patchId),
  directionIdx: index('sem_signed_bundles_direction_idx').on(t.direction),
}));
```

### 2.2 Add the CHECK constraint in the migration SQL

drizzle-kit will generate the table. After generation, edit the produced
SQL to append:

```sql
ALTER TABLE "sem_signed_bundles"
  ADD CONSTRAINT sem_signed_bundles_direction_check
  CHECK (direction IN ('inbound', 'outbound'));
```

### 2.3 Verify generation

```bash
bun run db:generate
```

Migration file `drizzle/0009_<name>.sql` exists and contains the
`CREATE TABLE` + the two indexes + the CHECK.

Commit: `feat(ojt-p1/D1.2): add sem_signed_bundles table for federation envelopes`

---

## Step 3: Backfill script for `sem_object_patches.timestamp` (D1.3)

Existing rows have `createdAt` (timestamptz) but no `timestamp` (bigint
ms). Backfill so `timestamp` is present on all rows.

### 3.1 Create the backfill script

File: `scripts/backfill-patch-timestamps.ts`

```ts
// Pseudocode — adapt to OJT's db connection pattern (see src/lib/db/...)
import { db } from '@/lib/db';
import { sql } from 'drizzle-orm';

async function main() {
  const result = await db.execute(sql`
    UPDATE sem_object_patches
    SET timestamp = CAST(EXTRACT(EPOCH FROM created_at) * 1000 AS BIGINT)
    WHERE timestamp IS NULL AND created_at IS NOT NULL
  `);
  console.log(`Backfilled ${result.rowCount ?? 0} patch rows`);
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
```

### 3.2 Dry-run on PGlite

```bash
bun run scripts/backfill-patch-timestamps.ts
```

Output: `Backfilled N patch rows` — N equals the current row count in
`sem_object_patches`.

### 3.3 Idempotency

Running the script a second time must produce `Backfilled 0 patch rows`
(the `WHERE timestamp IS NULL` clause guards against double-write).

Commit: `feat(ojt-p1/D1.3): backfill script for legacy patch timestamps`

---

## Step 4: Unit test — round-trip a row through the new columns

File: `tests/db/sem-patches-federation-fields.test.ts`

```ts
import { describe, test, expect, beforeAll } from 'bun:test';
import { db } from '@/lib/db';
import { semObjectPatches, semSignedBundles } from '@/lib/semantos-kernel/schema.core';

describe('Phase 1 — federation fields on sem_object_patches', () => {
  test('G1 round-trips all four new columns', async () => {
    const id = `test-patch-${Date.now()}`;
    await db.insert(semObjectPatches).values({
      id,
      // ... existing required columns ...
      timestamp: Date.now(),
      facetId: 'hat-tenant',
      facetCapabilities: [1, 2, 4],
      lexicon: 'jural',
    });

    const [row] = await db.select().from(semObjectPatches).where(eq(semObjectPatches.id, id));
    expect(row.timestamp).toBeTypeOf('number');
    expect(row.facetId).toBe('hat-tenant');
    expect(row.facetCapabilities).toEqual([1, 2, 4]);
    expect(row.lexicon).toBe('jural');
  });

  test('G2 all federation columns are nullable (legacy rows)', async () => {
    const id = `legacy-patch-${Date.now()}`;
    await db.insert(semObjectPatches).values({
      id,
      // ... existing required columns only, no federation fields ...
    });
    const [row] = await db.select().from(semObjectPatches).where(eq(semObjectPatches.id, id));
    expect(row.lexicon).toBeNull();
    expect(row.facetId).toBeNull();
  });

  test('G3 sem_signed_bundles FK cascades on patch delete', async () => {
    // insert patch, insert envelope, delete patch, expect envelope gone
  });

  test('G4 direction CHECK rejects invalid values', async () => {
    await expect(
      db.insert(semSignedBundles).values({ /* ... */ direction: 'sideways' }),
    ).rejects.toThrow(/direction_check/);
  });
});
```

Run:

```bash
bun test tests/db/sem-patches-federation-fields.test.ts
```

All four gates pass.

Commit: `feat(ojt-p1/D1.4): gate tests for federation columns + signed-bundle FK + CHECK`

---

## Step 5: Full test sweep + PR

```bash
bun test
bun run build       # or equivalent: ensure drizzle client regenerates with new types
git push -u origin feat/sem-patches-federation-fields
gh pr create --title "OJT P1: sem_object_patches federation fields + sem_signed_bundles" \
  --body "Adds timestamp, facet_id, facet_capabilities, lexicon to sem_object_patches; adds sem_signed_bundles envelope table with FK + CHECK. Backfill script + 4 gates. Schema-only — no runtime callers modified. Unblocks P2–P7."
```

---

## Gate tests (must pass before PR)

- **G1**: `sem_object_patches` round-trips `timestamp` (bigint ms),
  `facet_id`, `facet_capabilities` (integer[]), `lexicon`.
- **G2**: all four federation columns are nullable; legacy rows read back
  with `NULL` values without error.
- **G3**: `sem_signed_bundles.patch_id` FK cascades on patch delete.
- **G4**: `sem_signed_bundles.direction` CHECK rejects values other than
  `'inbound'` and `'outbound'`.
- **G5**: `scripts/backfill-patch-timestamps.ts` is idempotent: second
  run reports `Backfilled 0 patch rows`.
- **G6**: `drizzle-kit generate` produces no pending diff after the phase
  is merged (schema and migrations are in sync).

## Completion criteria

- Two new migrations landed in `drizzle/` (0008 + 0009).
- `semObjectPatches` schema export includes the four new columns.
- `semSignedBundles` schema export exists.
- Backfill script exists and is idempotent.
- All four gate tests pass.
- No changes to any `src/lib/services/*` file (schema-only phase).
- PR open with the body above.

When merged, proceed to OJT-PHASE-2-PROMPT.md.
