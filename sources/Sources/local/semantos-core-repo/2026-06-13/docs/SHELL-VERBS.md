---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/SHELL-VERBS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.327148+00:00
---

# `semantos-shell` verb reference

Extracted from [`HELP_TEXT` in packages/shell/src/repl.ts:16](../packages/shell/src/repl.ts) (lines 16–74). This file lags the source if `HELP_TEXT` changes; keep `HELP_TEXT` as the single source of truth and refresh this doc when it drifts.

## Semantic verbs

| Verb | Args | Purpose |
|---|---|---|
| `new` | `<type-path> [--flags]` | Create a new semantic object |
| `patch` | `<object-id> [--flags]` | Apply a mutation to an object |
| `transition` | `<id> --visibility X` | Change visibility state |
| `inspect` | `<object-id>` | Show object details |
| `trace` | `<object-id>` | View evidence chain |
| `verify` | `<object-id>` | Verify evidence chain integrity |
| `sign` | `<object-id>` | Attach facet signature |
| `publish` | `<object-id>` | Publish: `draft → published` |
| `revoke` | `<object-id>` | Revoke: `published → revoked` |
| `stake` | `<object-id>` | Start governance staking flow |
| `vote` | `<object-id>` | Cast governance vote |
| `dispute` | `<object-id>` | File a dispute |
| `transfer` | `<id> --to <facet-id>` | Transfer ownership |
| `flow` | `start\|advance\|cancel\|list` | Manage multi-step flows |
| `list` | `[--type X] [--status X]` | List objects with filters |
| `eval` | `<expression>` | Evaluate a Lisp policy expression |
| `compile` | `<expression>` | Compile a Lisp expression to cell opcodes |
| `bind` | `<policy-ref> [type-path]` | Bind a compiled policy to a type |

## Extensions (Phase 36E)

| Verb | Args | Purpose |
|---|---|---|
| `extension list` | `[--json]` | List installed extensions with grammar summary |
| `extension status` | | Show extraction status, version compat, governance alerts |
| `extension detail` | `<id>` | Show grammar summary, capabilities, trust signals |
| ↳ | `--grammar` | Show full grammar details |
| ↳ | `--entities` | Show entity list |
| ↳ | `--history` | Show extraction history |

## Identity (Phase 19.5)

| Verb | Args | Purpose |
|---|---|---|
| `identity register` | `<email>` | Register a new identity via Plexus |
| `identity derive` | `<resource-id>` | Derive a child facet |
| `identity resolve` | `<cert-id>` | Look up certificate details |
| `identity list` | | List facets under current identity |
| `whoami` | | Show current identity, facet, capabilities |
| `capabilities` | | List active facet's capabilities |

## Flags

| Flag | Values | Effect |
|---|---|---|
| `--format` | `json\|table\|cell\|csv` (default `json`) | Output format |
| `--dry-run` | | Show capability checks without executing |
| `--verbose` | | Extra detail |

## Built-ins (REPL only)

| Command | Effect |
|---|---|
| `help` | Show this help |
| `switch <facet-id>` | Change active facet |
| `load <extension>` | Change active extension |
| `exit` | Quit the REPL |

## Examples

```bash
new trades.job.plumbing --urgency high
inspect job-1774
list --type Job --status draft --format table
publish job-1774 --dry-run
flow start new-job-intake
identity register alice@example.com
whoami
```

## Verbs not yet in `HELP_TEXT`

The verbs below exist as command modules under [packages/shell/src/commands/](../packages/shell/src/commands/) but are not listed in the REPL help. Surface here so they're discoverable; reconcile with `HELP_TEXT` in a future pass.

| Verb file | Purpose (from filename) |
|---|---|
| `doc.ts` | Document operations (Phase 39 work landed via cherry-pick `df4a5ff`) |
| `host-exec.ts` | Phase 38C — publish-before-execute lifecycle |
| `host-audit.ts` | Phase 38D — read-only cryptographic verification |
| `console.ts` | Console subcommand |
| `fs.ts` | Filesystem-style verbs over the object store |
| `govern.ts` | Governance verbs beyond `stake`/`vote`/`dispute` |
| `grammar.ts` | Grammar inspection / management |
| `infer.ts` | Schema inference |
| `settle.ts` | Settlement-layer interaction |
| `storage.ts` | Storage-adapter operations |

## Related

- [SHELL.md](SHELL.md) — entry point, modes, architecture
- [PIPELINE.md](PIPELINE.md) — what `compile`, `eval`, `bind` drive
