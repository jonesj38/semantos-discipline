---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/oddjobtodd-legacy/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.697066+00:00
---

# oddjobtodd-legacy

Vendored code removed from the OJT (Oddjob Todd) intake bot during the
A1 carve-out (2026-04-20).

- `plexus-core/` — legacy pre-workspace copy of `@dusk-inc/plexus-core`,
  a predecessor to the current `@semantos/core` package. Shipped inside
  `oddjobtodd/plexus-core/` as a ~53MB vendored subproject (`node_modules/`
  was stripped on archive). Kept here for reference; not imported by any
  current code. Safe to delete once the OJT team confirms no drift.

- `packages/` — another vendored tree that lived at
  `oddjobtodd/packages/` with `__tests__`, `cell-engine`, `constants`,
  `protocol-types`. Appears to be an even older snapshot from before the
  `semantos-core` monorepo existed. Kept here for reference.

Both were stripped from the `ojt` repo in the A1 carve because neither
is imported from `src/` and both inflated deploy size.
