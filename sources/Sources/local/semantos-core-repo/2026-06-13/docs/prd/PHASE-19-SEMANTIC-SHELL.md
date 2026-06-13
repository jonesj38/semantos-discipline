---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-19-SEMANTIC-SHELL.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.677116+00:00
---

# Phase 19 — Semantic Shell

**Version**: 1.0
**Date**: March 2026
**Status**: Ready for implementation
**Duration**: 2 weeks (with 3-day buffer)
**Prerequisites**: Phase 9 complete (service extraction), Phase 9.5 complete (visibility/governance types). Does NOT require Plexus phases — runs in parallel.
**Master document**: `SEMANTIC-SHELL-ARCHITECTURE.md`
**Branch**: `phase-19-semantic-shell`

---

## Context

The loom has renderer-agnostic services (LoomStore, FlowRunner, IdentityStore, ConfigStore, IntentClassifier, FlowRegistry, SettingsStore). The React loom is one renderer — a canvas-based UI with conversation panels and inspectors.

The semantic shell is a **second renderer** — a CLI/REPL/API that exposes the same services through a typed command grammar. Think `bash` but typed, evidence-bearing, and capability-aware.

The conversation UI compresses ambiguity into resolved intents. The shell lets users express resolved intents directly via grammar: `semantos <verb> [<type-path>] [--flags] [<object-id>]`.

Both renderers consume the same Phase 9 services. The shell is NOT a new backend — it's a new frontend.

### Architecture Layers

```
+------------------------------------------------------------------+
|  WORKBENCH SERVICES (Phase 9)                                   |
|  LoomStore, FlowRunner, IdentityStore, ConfigStore,        |
|  IntentClassifier, FlowRegistry, SettingsStore                  |
+------------------------------------------------------------------+
        |                                    |
        v                                    v
+--------------------+          +-----------------------------+
|  React Loom   |          |  Semantic Shell (CLI/REPL)  |
|  (Phase 4–9)       |          |  (Phase 19)                 |
|  - Canvas          |          |  - Command parser           |
|  - Conversation    |          |  - Verb router              |
|  - Inspector       |          |  - Output formatters        |
+--------------------+          +-----------------------------+
```

Same services. Two renderers. No duplication.

---

## Source Files / References

| Alias | Path | What to extract |
|-------|------|-----------------|
| `ARCH:SHELL` | `docs/prd/SEMANTIC-SHELL-ARCHITECTURE.md` | Command grammar, verb set, Unix composability |
| `SVC:STORE` | `packages/loom/src/services/LoomStore.ts` | createObject(), applyPatch(), transitionObject(), getObject(), listObjects() |
| `SVC:FLOW` | `packages/loom/src/services/FlowRunner.ts` | startFlow(), advanceFlow(), getFlowState() |
| `SVC:REGISTRY` | `packages/loom/src/services/FlowRegistry.ts` | lookupFlow(), getFlowDefinition() |
| `SVC:IDENTITY` | `packages/loom/src/services/IdentityStore.ts` | getActiveIdentity(), getFacet(), listFacets() |
| `SVC:CONFIG` | `packages/loom/src/services/ConfigStore.ts` | loadExtension(), getExtension(), getObjectTypeDefinition() |
| `SVC:CLASSIFY` | `packages/loom/src/services/IntentClassifier.ts` | classifyIntent() |
| `SVC:SETTINGS` | `packages/loom/src/services/SettingsStore.ts` | getSetting(), setSetting() |
| `TYPE:WORKBENCH` | `packages/loom/src/types/workbench.ts` | Cell, Header, LoomObject, Identity, Facet |
| `CFG:CORE` | `configs/extensions/core.json` | Governance types and flows |
| `CFG:TRADES` | `configs/extensions/trades-services.json` | Real extension for testing |
| `POLICY:BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming, branch rules |

---

## Deliverables

### D19.1 — Shell Package Scaffold

**New file**: `packages/shell/package.json`

Create a standalone CLI package:

```json
{
  "name": "@semantos/shell",
  "version": "19.0.0",
  "description": "Semantic shell: typed CLI/REPL for semantic objects",
  "type": "module",
  "bin": {
    "semantos": "./dist/index.js"
  },
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "scripts": {
    "build": "tsc",
    "dev": "node --watch dist/index.js"
  },
  "dependencies": {
    "@semantos/loom": "workspace:*"
  },
  "devDependencies": {
    "typescript": "^5.3.3"
  }
}
```

**New file**: `packages/shell/src/index.ts`

Entry point and CLI binary startup:

- Detect if running with arguments or no args (REPL mode)
- If args: parse and execute single command
- If no args: enter REPL loop
- Wire to a shared services instance (LoomStore, IdentityStore, etc)

```typescript
import { Shell } from './shell';
import { setupServices } from '@semantos/loom/services';

const services = setupServices();
const shell = new Shell(services);

const args = process.argv.slice(2);
if (args.length === 0) {
  shell.repl();
} else {
  shell.execute(args).then((output) => {
    console.log(output);
  }).catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}
```

**New file**: `packages/shell/src/shell.ts`

Main REPL and command execution loop:

- Readline-based REPL with history
- Command parsing, routing, formatting
- Prompt shows active facet: `[facet-3a2b@trades] > `
- Built-in commands: `help`, `switch <facet-id>`, `load <extension>`, `exit`

Commit: `phase-19/D19.1: Shell package scaffold — CLI binary, entry point, REPL loop`

---

### D19.2 — Command Grammar Parser

**New file**: `packages/shell/src/parser.ts`

Parse CLI commands into structured `ShellCommand` types:

```typescript
/**
 * Shell command grammar:
 *   semantos <verb> [<type-path>] [--flags] [<object-id>]
 *
 * Examples:
 *   semantos new trades.job.plumbing --urgency high
 *   semantos inspect job-1774
 *   semantos list --type governance.dispute --status open --format json
 *   semantos publish job-1774 --dry-run
 */
export interface ShellCommand {
  verb: 'new' | 'patch' | 'transition' | 'inspect' | 'trace' | 'verify' | 'sign' |
        'publish' | 'revoke' | 'stake' | 'vote' | 'dispute' | 'transfer' | 'flow' | 'eval' | 'list';
  typePath?: string;          // e.g., 'trades.job.plumbing'
  objectId?: string;          // e.g., 'job-1774'
  flags: Record<string, string | boolean>;
  rawArgs?: string[];
}

export function parseCommand(args: string[]): ShellCommand {
  // 1. Extract verb (first non-flag arg)
  // 2. Collect all --flag value pairs and --boolean flags
  // 3. Remaining args: typePath + objectId (or just objectId if verb is inspect/trace/verify)
  // 4. Return structured ShellCommand
  // 5. Helpful error messages: "Unknown verb 'foo'. Did you mean 'flow'?"
}
```

Requirements:

- Type-safe grammar: no string manipulation, structured output
- Helpful error messages: suggest corrections for misspelled verbs
- Flags support: `--format json|csv|cell|raw`, `--facet <id>`, `--verbose`, `--dry-run`, etc.
- Object IDs can be strings: no type checking (let router validate)
- Type paths are dot-separated and validated against loaded extensions via ConfigStore

Test examples:
- `new trades.job.plumbing --urgency high`
- `inspect job-1774`
- `list --type governance.dispute --status open --format json`
- `publish job-1774 --dry-run`
- `flow start new-job-intake --category plumbing --urgency high`

Commit: `phase-19/D19.2: Command grammar parser — structured ShellCommand output, helpful errors`

---

### D19.3 — Verb Router

**New file**: `packages/shell/src/router.ts`

Map parsed verbs to service method calls. Each verb maps to one or more LoomStore / FlowRunner / IdentityStore methods.

```typescript
export interface RouterContext {
  store: LoomStore;
  flowRunner: FlowRunner;
  identity: IdentityStore;
  config: ConfigStore;
  settings: SettingsStore;
  facetId: string;  // Active facet for this command
}

export async function route(cmd: ShellCommand, ctx: RouterContext): Promise<unknown> {
  switch (cmd.verb) {
    case 'new':
      // createObject via LoomStore
      // Inject facetId as ownerId (or derive cert if Phase 14 present)
      break;
    case 'patch':
      // applyPatch via LoomStore
      break;
    case 'transition':
      // transitionObject via LoomStore
      break;
    case 'inspect':
      // getObject via LoomStore
      break;
    case 'trace':
      // Get object + evidence chain
      break;
    case 'verify':
      // Verify evidence chain hash integrity
      break;
    case 'sign':
      // Attach facet signature to patches
      break;
    case 'publish':
      // transitionObject with visibility draft → published
      // Check capability (5) first
      break;
    case 'revoke':
      // transitionObject with visibility published → revoked
      // Check capability (4) first
      break;
    case 'flow':
      // startFlow or advanceFlow via FlowRunner
      break;
    case 'list':
      // listObjects with filters
      break;
    case 'vote':
      // Governance flow for voting (delegates to FlowRunner)
      break;
    case 'dispute':
      // Governance flow for disputes (delegates to FlowRunner)
      break;
    case 'stake':
      // Governance flow for staking (delegates to FlowRunner)
      break;
    case 'transfer':
      // Transfer ownership via LoomStore
      // Stub-safe: delegates to PlexusService if Phase 14 present, no-op if not
      break;
    case 'eval':
      // Reserved for Phase 21 (Lisp axiom compiler)
      // Return message: "Lisp axiom compiler not yet available (Phase 21)"
      break;
  }
}
```

Requirements:

- Every verb checks capabilities via IdentityStore before executing mutations
- Every mutation verb records provenance (active facet ID on patch)
- Non-mutations (inspect, trace, verify, list) are read-only
- Errors are descriptive, not exceptions (missing capability → "You need capability X to do Y")
- `--dry-run` flag shows what would execute without executing
- Transfer verb is stub-safe: works without Phase 14 PlexusService

Commit: `phase-19/D19.3: Verb router — service dispatch with capability checks, provenance, stub-safe`

---

### D19.4 — Output Formatters

**New file**: `packages/shell/src/formatters.ts`

Format shell output for consumption by users and Unix pipes:

```typescript
export type OutputFormat = 'json' | 'table' | 'cell' | 'csv';

export interface Formatter {
  format(data: unknown, format: OutputFormat): string;
}

export class OutputFormatter implements Formatter {
  format(data: unknown, format: OutputFormat = 'json'): string {
    switch (format) {
      case 'json':
        return JSON.stringify(data, null, 2);
      case 'table':
        // Aligned columns for list output
        return formatAsTable(data);
      case 'cell':
        // Hex dump of cell bytes
        return formatAsHexDump(data);
      case 'csv':
        // CSV for evidence chain export
        return formatAsCSV(data);
    }
  }
}
```

Requirements:

- JSON formatter (default): structured output, pipe-friendly, valid JSON parseable by `jq`
- Table formatter: human-readable aligned columns (for `list` output, responsive to terminal width)
- Cell formatter: raw cell bytes as hex dump (for `inspect --format cell`)
- CSV formatter: for `trace --format csv` evidence chain export (headers: HASH, AUTHOR, ACTION, TIMESTAMP)
- All output goes to stdout. Errors go to stderr. This is Unix composability.

Test examples:
- `semantos list --format json | jq '.[] | select(.type == "trades.job")'`
- `semantos trace job-1774 --format csv > evidence.csv`
- `semantos inspect job-1774 --format cell | xxd`

Commit: `phase-19/D19.4: Output formatters — JSON, table, cell, CSV for Unix pipes`

---

### D19.5 — Shell Configuration

**New file**: `packages/shell/src/config.ts`

Load and manage shell configuration from files and environment variables:

```typescript
export interface ShellConfig {
  adapterMode: 'stub' | 'local' | 'cloud';
  activeFacetId: string | null;
  defaultExtension: string;
  defaultFormat: OutputFormat;
  apiEndpoint?: string;
}

export function loadConfig(): ShellConfig {
  // 1. Load from ~/.semantos/config.toml or ./.semantos.toml in project root
  // 2. Override with environment variables:
  //    - SEMANTOS_MODE (stub|local|cloud)
  //    - SEMANTOS_FACET (active facet)
  //    - SEMANTOS_EXTENSION (default extension)
  //    - SEMANTOS_FORMAT (default output format)
  //    - SEMANTOS_ENDPOINT (API endpoint)
  // 3. Fill gaps with defaults: stub mode, no facet, core extension, JSON format
  // 4. Return merged config
}
```

**Config file format** (TOML):

```toml
[shell]
adapter_mode = "stub"
active_facet = "facet-3a2b"
default_extension = "trades-services"
default_format = "json"
api_endpoint = "http://localhost:8000"
```

Requirements:

- Config file path: `~/.semantos/config.toml` (user home) or `./.semantos.toml` (project root, takes precedence)
- Environment variable overrides file settings
- Defaults: stub mode, no active facet, core extension, JSON output
- Follow ConfigStore pattern (file → env vars → defaults)

Commit: `phase-19/D19.5: Shell configuration — TOML file, env var overrides, defaults`

---

### D19.6 — Interactive REPL Mode

**New file**: `packages/shell/src/repl.ts`

Readline-based REPL for interactive command execution:

```typescript
export class REPLShell {
  constructor(context: ShellContext) { }

  async repl(): Promise<void> {
    // 1. Initialize readline interface
    // 2. Show prompt with active facet: [facet-3a2b@trades] >
    // 3. Read line, parse command, execute, format output
    // 4. Tab completion: verbs, type paths, object IDs from store
    // 5. Command history (readline-based)
    // 6. Built-in commands:
    //    - help: show verb table + examples
    //    - switch <facet-id>: change active facet, update prompt
    //    - load <extension>: change active extension, update prompt
    //    - exit: quit REPL
    // 7. Loop until exit
  }
}
```

Requirements:

- Prompt reflects active facet and extension: `[facet-3a2b@trades] > `
- Tab completion for:
  - Verbs (new, patch, inspect, list, etc.)
  - Type paths (trades.job, trades.job.plumbing, governance.dispute, etc.)
  - Object IDs from LoomStore
- Command history (readline built-in)
- REPL wraps the same parser + router as single-command mode — no separate code paths
- Built-in commands (help, switch, load, exit)
- Graceful shutdown on Ctrl+C

Commit: `phase-19/D19.6: Interactive REPL — readline, tab completion, command history, built-ins`

---

## Gate Tests (T1–T18)

Create `packages/__tests__/phase19-gate.test.ts`.

### Parser Tests (T1–T4)

```
T1:  Parser correctly parses 'new trades.job.plumbing --urgency high'
     into ShellCommand with verb='new', typePath='trades.job.plumbing',
     flags={urgency: 'high'}

T2:  Parser correctly parses 'inspect job-1774'
     (no type path, just object ID)
     into ShellCommand with verb='inspect', objectId='job-1774'

T3:  Parser correctly parses 'list --type governance.dispute --status open --format json'
     into ShellCommand with verb='list', flags with multiple key-value pairs

T4:  Parser rejects malformed commands with helpful error messages
     (e.g., 'new' without args, unknown verb 'foo', suggests 'flow')
```

### Router Tests (T5–T9)

```
T5:  Router maps 'new' verb to LoomStore.createObject()
     and returns created object

T6:  Router maps 'inspect' verb to LoomStore.getObject()
     and formats output

T7:  Router maps 'flow start new-job-intake' to FlowRunner.startFlow()

T8:  Router maps 'publish job-1774' to visibility transition
     with capability check (capability 5) before executing

T9:  Router returns error if capability missing (e.g., 'publish' without cap 5)
     Error message shows which capability needed, not an exception
```

### Formatter Tests (T10–T12)

```
T10: JSON formatter outputs valid JSON parseable by 'jq'
     JSON.parse(formatter.format(data, 'json')) succeeds

T11: Table formatter outputs aligned columns for 'list' output
     Columns: ID, TYPE, VISIBILITY, OWNER, PATCHES
     Rows align to column widths

T12: CSV formatter outputs valid CSV for 'trace' output
     Headers: HASH, AUTHOR, ACTION, TIMESTAMP
     Rows are comma-separated, quoted if needed
```

### Config Tests (T13)

```
T13: Config loads from file, env vars override file, defaults fill gaps
     File: ~/.semantos/config.toml with adapter_mode = "cloud"
     Env: SEMANTOS_MODE=stub
     Result: ShellConfig.adapterMode = "stub" (env wins)
```

### REPL Tests (T14–T15)

```
T14: REPL prompt reflects active facet and extension
     Starts: [no-facet@core] > (no facet set)
     After 'switch facet-123': [facet-123@core] >
     After 'load trades-services': [facet-123@trades] >

T15: 'eval' verb returns "Lisp axiom compiler not yet available (Phase 21)"
     Does not throw, message is informative
```

### Anti-Lock Tests (T16–T18)

```
T16: Shell package has ZERO React imports
     Grep: grep -r "import.*from 'react'" packages/shell/src/
     Result: no matches

T17: Shell imports only from service layer, not from canvas/UI components
     Allowed: @semantos/loom/src/services/*, types/workbench
     Disallowed: @semantos/loom/src/canvas/*, /ui/*, /components/

T18: All shell output goes to stdout/stderr, no console.log in services
     Grep: grep -n "console\." packages/shell/src/
     Result: only in index.ts and repl.ts, not in router/parser/formatters
```

---

## What NOT to Do

1. **Do NOT import React or any UI framework in the shell package.** grep must return zero matches for 'react' in `packages/shell/src/`.
2. **Do NOT create a separate backend.** The shell uses the SAME service instances as the React loom.
3. **Do NOT implement the Lisp `eval` verb.** That's Phase 21. Just return a message.
4. **Do NOT implement tmux integration.** That's Phase 20.
5. **Do NOT implement VFS/FUSE mount.** That's Phase 20.
6. **Do NOT build a custom shell language.** Use standard CLI grammar: `<verb> <args> [--flags]`.
7. **Do NOT duplicate service logic.** The shell is a thin routing layer over existing services.

---

## Completion Criteria

- [ ] `packages/shell/package.json` exists with correct bin entry
- [ ] `packages/shell/src/index.ts` entry point detects REPL vs single-command mode
- [ ] `packages/shell/src/parser.ts` parses commands into structured ShellCommand types
- [ ] `packages/shell/src/router.ts` routes verbs to service methods with capability checks
- [ ] `packages/shell/src/formatters.ts` outputs JSON, table, cell, CSV formats
- [ ] `packages/shell/src/config.ts` loads from file + env vars with defaults
- [ ] `packages/shell/src/repl.ts` implements readline REPL with tab completion and history
- [ ] `packages/shell/src/shell.ts` coordinates parsing, routing, formatting
- [ ] Tests T1–T18 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] No React imports in shell package
- [ ] All commits follow `phase-19/D19.N:` naming convention
- [ ] Branch is `phase-19-semantic-shell`
- [ ] Errata sprint complete with `docs/prd/PHASE-19-ERRATA.md`

---

## Next Phase

Phase 19.5 wires the shell to Plexus identity: environment variable facet selection, capability checks, signed CLI requests.
