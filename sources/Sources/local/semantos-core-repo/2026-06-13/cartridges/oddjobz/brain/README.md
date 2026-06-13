---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.452553+00:00
---

# @semantos/oddjobz

Oddjobz extension — cell types + state machines for the trades/services
vertical. Per `docs/design/ODDJOBZ-EXTENSION-PLAN.md`.

This package owns the eight canonical cell-type schemas (Phase O2):

| Type                   | Linearity   | Role                                         |
|------------------------|-------------|----------------------------------------------|
| `oddjobz.job.v1`       | LINEAR      | Work-unit; FSM `lead → … → closed`           |
| `oddjobz.quote.v1`     | LINEAR      | Priced offer; consumed when accepted         |
| `oddjobz.visit.v1`     | LINEAR      | Scheduled site visit; consumed when complete |
| `oddjobz.invoice.v1`   | LINEAR      | Invoice; consumed when paid                  |
| `oddjobz.customer.v1`  | PERSISTENT  | Identity record; accumulates references      |
| `oddjobz.site.v1`      | PERSISTENT  | Physical work location                       |
| `oddjobz.estimate.v1`  | AFFINE      | Pre-quote draft; can be discarded            |
| `oddjobz.message.v1`   | PATCH       | Customer/operator chat; patches a Job        |

Each schema exports a `pack(value): Uint8Array`, an `unpack(bytes): value`,
a frozen `typeHash` (SHA-256 of `whatPath:howSlug:instPath`), and a
`linearity` flag.

Conformance vectors live in `tests/vectors/oddjobz_*.json` and are
regenerated via `bun tools/gen-vectors.ts` (or `pnpm gen:vectors` from
this directory).

State machines (Phase O4) and capability mints (Phase O3) live in sibling
deliverables; they reference these types but are out of scope here.

The lexicon authority registration lives at `src/lexicon.ts`. Until D-O1
lands, that file is a TODO-stub that exports the cell-type registry keyed
by `typeHash` for downstream consumers.
