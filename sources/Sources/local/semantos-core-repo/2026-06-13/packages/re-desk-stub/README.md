---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/re-desk-stub/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.393808+00:00
---

# @semantos/re-desk-stub

Stub property-management vertical extension. Single
`MaintenanceRequest` cell type, single capability, single state
machine — intentionally **minimal scaffolding**, sufficient to validate
the chapter-29 federation primitive (cross-vertical dispatch envelope)
end-to-end with the full `@semantos/oddjobz` extension on the
receiving side.

Ships D-O11 phase O11a per
`docs/design/ODDJOBZ-EXTENSION-PLAN.md` §3 phase O11.

> The point is to **prove the federation pattern, not to build a real
> property-management extension**. A real `re-desk` vertical (under
> the SHOMEE/RE platform) is downstream work; the smoke test in this
> commission validates that the dispatch-envelope substrate primitive
> composes correctly across two independent extensions.

## Surface

- `re-desk.maintenance-request.v1` — LINEAR cell. Fields: `requestId`,
  `customer`, `description`, `dispatchTo` (a `tenant-domain#hat-id`
  reference like `"oddjobtodd.info#tradie-todd"`), `state` (FSM:
  `draft → dispatched → accepted → in_progress → completed → invoiced
  → closed`), `createdAt`, `dispatchedAt`, `acceptedAt`, etc.
- `cap.re-desk.dispatch` — operator-held capability that gates the
  `draft → dispatched` transition (the moment the dispatch envelope
  is created).
- `MaintenanceRequest` FSM — same K1/K2/K4 invariants pattern as
  `oddjobz.job-fsm` (see `extensions/oddjobz/src/state-machines/
  job-fsm.ts`).

The extension exports a single helper, `materialiseFromDispatch`,
which the receiving-vertical's accept-handler calls when a completion
patch arrives back over the federation wire. The PM-side
`MaintenanceRequest` FSM advances `accepted → completed → invoiced`
based on patches authored by the tradie's hat on the federated
envelope.

## Tenant-hat reference syntax

Dispatch targets are encoded as `<tenant-domain>#<hat-id>` —
operator-readable, unambiguous to parse, single delimiter. The
substring before the `#` is the receiving tenant's brain-routable
domain; the substring after is the hat-id whose context-tag the
envelope's accept-handler keys against. See
`docs/canon/glossary.yml#tenant-hat-reference`.

## Why so small

The full property-management vertical is a months-long product effort.
What this extension proves is the **shape** of the federation seam:

1. A vertical-A operator (here: PM) creates a vertical-A cell.
2. A vertical-A FSM transition (`draft → dispatched`) produces a
   `dispatch.envelope.v1` cell.
3. The envelope rides over the federation wire (D-W1 Phase 4
   SignedBundle transport in production; an in-memory transport in
   the smoke test).
4. The receiving vertical-B's dispatch handler verifies the cert
   chain and routes the envelope's payload to the registered
   accept-handler.
5. Vertical-B's accept-handler materialises the payload into a
   vertical-B cell (here: an `oddjobz.job.v1`) under
   `provenance = from_dispatch`.
6. Vertical-B drives its own FSM locally; on completion it emits a
   `dispatch.completion.v1` patch back to vertical-A, which advances
   vertical-A's FSM.

Once that loop closes, the full re-desk vertical is "fill in the
fields" — no new substrate primitives are required. That's the
architecturally-load-bearing claim D-O11 establishes.
