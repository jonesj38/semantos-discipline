---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.315251+00:00
---

# scripts/

Operator-facing helper scripts. Most are one-offs documented inline; the
entries below are the ones worth knowing about.

## `dogfood-up.sh`

Process supervisor for the local dogfood stack. Starts `brain serve`
(the brain) and the OAuth-callback widget on `:3001`, waits for both
to become reachable, prints a status banner with PIDs and the
legacy-cli invocations the operator runs in a second terminal, then
tails their logs in the foreground. `Ctrl+C` graceful-shutdowns both
children. Logs land in `./.dogfood-logs/` (gitignored). Run
`scripts/dogfood-up.sh --help` for flags.
