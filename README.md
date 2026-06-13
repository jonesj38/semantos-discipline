# Semantos Discipline

Durable, multi-run discipline package for the Semantos `semantos-core` codebase.

Source repository: <https://github.com/semantos/semantos-core>

## Package layout

- `00-Final-Reports/` — final discipline report and executive summary
- `01-Methodology/` — evidence rules, analysis questions, verification plan, quality gate
- `02-Source-Map/` — deterministic source maps and corpus inventory
- `03-Analysis/` — focused analysis artifacts from separate Shad runs
- `04-Data/` — manifests, source mix, claims ledger, artifact manifest
- `05-Scripts/` — verification/package scripts
- `06-Visualizations/` — diagrams and visual artifacts
- `07-Out-Reports/` — raw Shad run logs/prompts/outputs
- `Sources/` — symlinks/pointers to source snapshots used for retrieval

## Source authority

For behavior claims, actual code/proofs/tests/config/runtime snapshots are primary. Docs and plans are secondary context and must not override current source behavior.
