---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/SHELL.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.327390+00:00
---

# `semantos-shell`

The typed CLI/REPL over the cell engine. Source: [runtime/shell/](../runtime/shell/). Binary: `semantos-shell` → `dist/index.js` (per [runtime/shell/package.json](../runtime/shell/package.json)).

## What it is

A semantic shell with three modes:

| Mode | How to invoke | Use it for |
|---|---|---|
| **REPL** | `semantos-shell` | interactive exploration, tab completion, command history, prompt reflects active facet/extension |
| **One-shot CLI** | `semantos-shell <verb> <args> [--flags]` | scripts, automation, `\| jq` pipelines (stdout stays clean for piping) |
| **Watch** | (currently a stub) | future: long-lived `StoreBridgeServer` for clients to subscribe over WebSocket |

Output goes to stdout; prompts and errors go to stderr — so any verb composes with shell pipes.

## Quickstart

```bash
bun install
cd runtime/shell
bun run build
./dist/index.js                                # REPL
./dist/index.js inspect job-1774               # one-shot
./dist/index.js list --type Job --format json  # piping-friendly
```

Or from the repo root, after `bun install`:

```bash
bun runtime/shell/src/index.ts                # run the entry point under bun directly
```

## Modes in more detail

### REPL ([runtime/shell/src/repl.ts](../runtime/shell/src/repl.ts))

Readline-based, with:

- Tab completion against `KNOWN_VERBS`
- Command history (in-process)
- Prompt rendering active facet + extension
- Built-in commands separate from semantic verbs: `help`, `switch`, `load`, `exit`

Built on the same `parseCommand` + `route` pipeline as the one-shot CLI — there's exactly one parser and one router; the REPL just wraps them in a readline loop.

### One-shot CLI

The same parser and router invoked once with `process.argv`. Exit code reflects success/failure. `--format json|table|cell|csv` chooses the output renderer.

### Watch (stub)

A `StoreBridgeServer` exists in the codebase but no user-facing `semantos watch` command currently ships. Future direction: long-lived process that publishes shell-routed events to subscribers over WebSocket — the substrate for replacing an Express webserver, per [RESTRUCTURING-PLAN.md §9](RESTRUCTURING-PLAN.md). Document this honestly until it ships.

## Verb categories

| Category | Examples | Purpose |
|---|---|---|
| **Semantic object lifecycle** | `new`, `patch`, `transition`, `inspect`, `trace`, `verify`, `sign`, `publish`, `revoke` | Create, mutate, observe, and progress objects through their state machine |
| **Governance** | `stake`, `vote`, `dispute` | Multi-party governance flows |
| **Transfer** | `transfer` | Move ownership between facets |
| **Flow management** | `flow start\|advance\|cancel\|list` | Multi-step workflows |
| **Listing / search** | `list` | Filtered queries by type, status, facet |
| **Compilation** | `eval`, `compile`, `bind` | Drive the Lisp → opcode pipeline (see [PIPELINE.md](PIPELINE.md)) |
| **Extensions (Phase 36E)** | `extension list\|status\|detail` | Inspect installed extensions, governance alerts, grammar summaries |
| **Identity (Phase 19.5)** | `identity register\|derive\|resolve\|list`, `whoami`, `capabilities` | Plexus identity + facet management |
| **Built-ins** | `help`, `switch`, `load`, `exit` | Shell-level (not a semantic verb) |

Full reference: [SHELL-VERBS.md](SHELL-VERBS.md).

## Flags

| Flag | Default | Effect |
|---|---|---|
| `--format json\|table\|cell\|csv` | `json` | Output renderer (see [runtime/shell/src/formatters.ts](../runtime/shell/src/formatters.ts)) |
| `--dry-run` | off | Show capability checks without executing the action |
| `--verbose` | off | Extra detail in output |

## Architecture (one paragraph)

`parseCommand(argv) → ShellCommand`, then `route(cmd, ctx) → result`, then `formatter.format(result, format) → output`. The `ShellContext` carries the active facet, default format, and capability cursor. Verbs live in [runtime/shell/src/commands/](../runtime/shell/src/commands/) (`cdm.ts`, `doc.ts`, `eval.ts`, `extension.ts`, `extract.ts`, `host-exec.ts`, `host-audit.ts`, …) — one file per verb category. Phase 38 added `host.exec` (publish-before-execute) and `host.audit` (read-only verification).

## Related docs

- [SHELL-VERBS.md](SHELL-VERBS.md) — verb reference (extracted from `repl.ts:HELP_TEXT`)
- [PIPELINE.md](PIPELINE.md) — what `compile`, `eval`, `bind` actually do
- [RESTRUCTURING-PLAN.md](RESTRUCTURING-PLAN.md) — the runtime/services extraction that is reshaping where shell sits
