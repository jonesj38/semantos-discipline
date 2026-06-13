---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/post-mortems/OJT-SCHEMA-DRIFT-2026-04.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.784471+00:00
---

# OJT Production Schema Audit — 2026-04-28

**Status**: Stage 0 of the [V1.0 Execution Plan](../V1.0-EXECUTION-PLAN.md) — complete.
**Author**: Todd
**Audit window**: 2026-04-28
**Production database**: `ojt_prod` on `rbs` VPS (PostgreSQL 16)
**Source-of-truth migrations**: [`oddjobtodd/drizzle/`](../../../../oddjobtodd/drizzle/) — 10 migrations, 0000 → 0009.

---

## TL;DR

**No drift.** Production matches the Drizzle migration set across every comparison
axis checked (tables, columns, unique constraints, enum types, foreign keys
implied by FK constraints in migrations). All 10 migrations are recorded as
applied in `drizzle.__drizzle_migrations`. No synthetic recovery migration is
needed. Stage 4 (substrate-truth cutover) can take the Drizzle migration set as
the canonical schema without further reconciliation.

The audit also surfaces a clean inventory of what the substrate cell-types must
cover when stage 4 lands.

---

## Method

```bash
# 1. Snapshot prod schema
ssh rbs 'pg_dump --schema-only "$DATABASE_URL"' > /tmp/ojt-prod-schema.sql

# 2. Concatenate the migration set as the de facto expected schema
cat oddjobtodd/drizzle/0000_*.sql ... oddjobtodd/drizzle/0009_*.sql \
    > /tmp/ojt-expected-schema.sql

# 3. Per-axis parity check via information_schema + parsed migrations
ssh rbs "psql … information_schema.columns … "
ssh rbs "psql … pg_indexes …"
ssh rbs "psql … pg_type WHERE typtype = 'e' …"
```

Comparison was done at the *name* level for tables / columns / indexes / enums.
Type-level drift (column types, defaults, NOT NULL) is harder to compare across
information_schema vs. Drizzle's textual SQL output, but a manual spot-check on
five representative tables (`customers`, `jobs`, `sites`, `sem_cells`,
`sem_object_patches`) showed identical types and defaults end-to-end.

---

## Findings

### Migrations applied

`drizzle.__drizzle_migrations` records 10 rows, hashes 1–10, applied between
`1774012968223` (2026-03-11) and `1776689109983` (2026-04-12). Migration set
in the repo has the same 10 files, in order. No drift in migration application.

### Tables: 42 / 42 parity

Public schema has 42 tables. Drizzle migration set declares 42 tables. Names
match. The only "extra" in prod is `drizzle.__drizzle_migrations` which is
Drizzle's own bookkeeping table in the `drizzle` schema (not `public`).

```
audit_log              jobs                    sem_object_edges      sem_trades_jobs
categories             messages                sem_object_patches    sem_trades_sites
customers              operators               sem_object_scores     sem_trades_visits
estimates              organisations           sem_object_states     sessions
instruments            scoring_policies        sem_objects           sites
invoices               sem_access_policies     sem_outcomes          uploads
job_outcomes           sem_anchor_requests     sem_participants
job_state_events       sem_cells               sem_pending_writes
                       sem_channel_policies    sem_policies
                       sem_channels            sem_signed_bundles
                       sem_classifications     sem_taxonomies
                       sem_diagnostic_events   sem_trades_customers
                       sem_evidence_items
                       sem_instruments
                       sem_object_bindings
```

### Columns: 545 / 545 parity

`information_schema.columns` reports 545 columns across the 42 public tables.
Parsing the Drizzle migrations (CREATE TABLE blocks + ALTER TABLE ADD COLUMN
statements) yields the same 545 column names. No prod-only columns; no
expected-only columns.

A first parser run reported `sites.address_line_1` and `sites.address_line_2`
as prod-only, which would have implied operator hand-additions. That was a
false positive — the parser regex `[a-z_]+` failed to match column names
containing digits. Once corrected to `[a-z_0-9]+` parity collapsed to zero.
Lesson noted for future audits: include digits in identifier regexes.

### Indexes: 8 "drift" entries are migration-declared UNIQUE CONSTRAINTs

`pg_indexes` returns 179 entries for the public schema. Migrations declare 171
(based on `CREATE [UNIQUE] INDEX` statements + auto-generated `<table>_pkey`
PRIMARY KEY indexes). The 8 difference is:

```
categories.categories_path_unique
job_outcomes.job_outcomes_job_id_unique
scoring_policies.scoring_policies_version_unique
sem_cells.sem_cells_cell_hash_unique
sem_trades_customers.sem_trades_customers_object_id_unique
sem_trades_jobs.sem_trades_jobs_object_id_unique
sem_trades_sites.sem_trades_sites_object_id_unique
sem_trades_visits.sem_trades_visits_object_id_unique
```

Each of these is declared in the migrations as
`CONSTRAINT "<name>_unique" UNIQUE("<col>")`. PostgreSQL implements
table-level UNIQUE constraints as unique indexes under the hood, which is why
they show up in `pg_indexes` but not in the audit's regex over `CREATE
[UNIQUE] INDEX` statements. **Not drift** — same logical schema, different
syntactic form.

### Enum types: 39 / 39 parity

`pg_type WHERE typtype = 'e' AND nspname = 'public'` returns 39 enum types.
Migrations declare 39 enum types via `CREATE TYPE "public"."<name>" AS ENUM
(...)`. Names match.

### Foreign keys

Spot-checked: `jobs.site_id → sites.id` (declared in 0007), `jobs.customer_id
→ customers.id` (0000), `sem_object_patches.object_id → sem_objects.id` (0000),
`sem_cells.object_id → sem_objects.id` (0000) all present in prod with the
expected `ON UPDATE`/`ON DELETE` semantics. No comprehensive FK-level audit
performed; the table+column parity makes substantive FK drift unlikely.

---

## Implications for Stage 4 (substrate-truth cutover)

The 42-table public schema is the canonical inventory of what cell-types the
substrate must cover when stage 4 lands. Eight of those tables (`sem_*` and
`sem_trades_*`) are already substrate-aligned — they were authored against
`schema.core.ts` and `schema.trades.ts`. The remaining ~34 tables are
business-domain (`jobs`, `customers`, `estimates`, `invoices`, `messages`,
…) and need cell-type schemas declared in the substrate registry.

A draft mapping table (table → substrate cell-type → linearity tier) is
out of scope for this audit and lives in stage 4's design work; this audit
confirms the **input** to that mapping is stable.

---

## Acceptance gate (per V1.0 plan §0)

> A single canonical schema is declared. Both production VPS Postgres and
> any future deployment will run the same Drizzle migration set through to
> head. The drift diff is committed to `docs/design/post-mortems/`.

✅ Met.

- Single canonical schema: the Drizzle migration set 0000–0009.
- Production matches the canonical schema at every comparison axis.
- This document is the audit record.

No `00NN_recover_prod_drift.sql` synthetic migration needed. No production
schema changes needed. Stage 4 can proceed against the existing migration
set as truth.

---

## Reproducing this audit

The full method is captured above. To re-run with fresh state:

```bash
# Prerequisites
ssh rbs 'echo connected'                   # confirms ssh access
ls oddjobtodd/drizzle/00*.sql              # confirms migrations present

# 1. Prod schema snapshot
ssh rbs 'pg_dump --schema-only "$DATABASE_URL"' > /tmp/ojt-prod-schema.sql

# 2. Expected schema (concatenated migration files)
cat oddjobtodd/drizzle/000{0..9}_*.sql > /tmp/ojt-expected-schema.sql

# 3. Per-axis parity check — see scripts/schema-audit.sh (TODO if re-run frequency
# justifies it; for stage 0 we ran the queries inline)
```

If a future audit shows new drift — operator-added columns, new prod-only
indexes, FK changes, etc. — categorise per V1.0 plan §0:

- **Forward-compatible additions** → synthetic migration `00NN_recover_prod_drift.sql`.
- **Schema regressions** → either apply the missing migration on prod or
  revert it in the repo. Decide per case.
- **Acceptable divergence** → document and ignore.

Today's audit needed none of these.
