---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-19-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.704109+00:00
---

# Phase 19 Execution Prompt — Semantic Shell (Typed CLI Renderer)

> Paste this prompt into a fresh session to execute Phase 19.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and React loom for Bitcoin-native semantic objects (npm: `@semantos/core`). Phases 9 and 9.5 extracted services from React (LoomStore, FlowRunner, IdentityStore, ConfigStore, IntentClassifier, FlowRegistry) and built visibility/governance types. These services are renderer-agnostic — they can be consumed by any frontend.

Your task is Phase 19: build a **second renderer** — a command-line shell that exposes the same Phase 9 services through a typed CLI grammar. The semantic shell is NOT a new backend. It's a new frontend: `semantos <verb> [<type-path>] [--flags] [<object-id>]`.

Both the React loom and the semantic shell consume the same services. They are two different ways to interact with the same system.

### The Thesis

**CLI is for commitment. Conversation is for discovery.**

The conversation UI (Phase 4–9) handles ambiguity: it classifies natural language intent, runs flows to collect missing parameters, and returns a resolved command. The shell is where users express **already-resolved intents** directly via grammar, as if typing to a system that understands types, evidence chains, and capabilities natively.

Examples:
- Conversation: "I need a plumber for a leaking tap" → classified, flow-executed, object created
- Shell: `semantos new trades.job.plumbing --urgency high` → direct semantic operation

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. If you haven't read them, you will miss the architecture, duplicate work, or break the phase.

**Read first** (the PRDs — your requirements):
- `docs/prd/PHASE-19-SEMANTIC-SHELL.md` — Phase 19 spec with deliverables D19.1–D19.6, TDD gate T1–T18, completion criteria

**Read second** (the architecture — understand the vision):
- `docs/prd/SEMANTIC-SHELL-ARCHITECTURE.md` — Shell architecture, verb grammar, Unix composability, tmux console, Lisp integration

**Read third** (the services you are consuming — understand them completely):
- `packages/loom/src/services/LoomStore.ts` — Object creation, patching, transition, inspection
- `packages/loom/src/services/FlowRunner.ts` — Flow execution, step advancement
- `packages/loom/src/services/FlowRegistry.ts` — Flow lookup, definition retrieval
- `packages/loom/src/services/IdentityStore.ts` — Identity and facet management
- `packages/loom/src/services/ConfigStore.ts` — Config loading, extension lookup
- `packages/loom/src/services/IntentClassifier.ts` — Intent classification (you won't use this directly, but understand the pattern)

**Read fourth** (the types your shell must work with):
- `packages/loom/src/types/workbench.ts` — Cell, Header, LoomObject, Identity, Facet types

**Read fifth** (the extension configs — your test data):
- `configs/extensions/core.json` — Governance types and flows
- `configs/extensions/trades-services.json` — Real extension for testing

**Read sixth** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-19-semantic-shell`. Commits as `phase-19/D19.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. NO STUBS

Every function must do real work. If a function body is `throw new Error("not implemented")`, `return undefined`, or `return hardcoded value`, you have failed. The shell is not a mock — it routes to real services.

### 2. NO REACT IMPORTS IN THE SHELL PACKAGE

`packages/shell/src/` must have ZERO React imports. Verify with `grep -r "import.*react" packages/shell/src/`. It should return nothing. The shell is a standalone CLI package that happens to import from `@semantos/loom/src/services/`, not from the UI layer.

### 3. NO SEPARATE BACKEND

The shell uses the SAME service instances as the loom. If you create a separate LoomStore or IdentityStore in the shell, you have broken the pattern. Both renderers consume shared services.

### 4. NO MOCK DATA

Tests must use real extension configs. No hardcoded test objects. The shell reads from ConfigStore, tests real object types, verifies real flows.

### 5. NO EASY TESTS

Tests that check `expect(result).toBeDefined()` are worthless. Write tests that verify real behavior: parse a command, route it, check the output format, verify capability checks work.

### 6. NO TESTS THAT MATCH BROKEN CODE

If your command parser produces wrong output, FIX THE PARSER. Don't change the test.

### 7. RENDERER AGNOSTICISM IS NOT OPTIONAL

`packages/shell/src/` is plain TypeScript. It never imports from React, canvas, conversation, or any UI components. The services it imports from (`LoomStore.ts`, `IdentityStore.ts`) are also free of React — this is Phase 9's job, not shell's to enforce.

### 8. EVAL VERB IS RESERVED, NOT IMPLEMENTED

The `eval` verb is for Phase 21 (Lisp axiom compiler). In Phase 19, it returns: "Lisp axiom compiler not yet available (Phase 21)". Do not implement it.

### 9. UNIX COMPOSABILITY IS NOT OPTIONAL

The shell outputs valid JSON by default, CSV for evidence chains, hex for cell bytes. All output goes to stdout. Errors go to stderr. This means `semantos list | jq '.[]'` must work. `semantos trace job-1774 --format csv | head -1` must give headers. Test these pipes.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`. Discard stale files.

### 0.3 Verify prerequisites are complete

```bash
# Services exist and are not stubbed
ls packages/loom/src/services/LoomStore.ts
ls packages/loom/src/services/FlowRunner.ts
ls packages/loom/src/services/FlowRegistry.ts
ls packages/loom/src/services/IdentityStore.ts
ls packages/loom/src/services/ConfigStore.ts
ls packages/loom/src/services/IntentClassifier.ts
ls packages/loom/src/services/SettingsStore.ts

# Types exist
ls packages/loom/src/types/workbench.ts

# Extension configs exist
ls configs/extensions/core.json
ls configs/extensions/trades-services.json
```

All files must exist and be real implementations (not stubs). If anything is missing, STOP.

### 0.4 Create Phase 19 branch

```bash
git checkout -b phase-19-semantic-shell
```

---

## Step 1: Shell Package Scaffold (D19.1)

Create `packages/shell/` directory structure:

```
packages/shell/
  package.json
  tsconfig.json
  src/
    index.ts
    shell.ts
  dist/
```

Create `packages/shell/package.json` as specified in the PRD.

Create `packages/shell/tsconfig.json` (extend root tsconfig):

```json
{
  "extends": "../../tsconfig.json",
  "compilerOptions": {
    "outDir": "./dist",
    "rootDir": "./src",
    "declaration": true,
    "declarationMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

Create `packages/shell/src/index.ts` as specified in the PRD — detect REPL vs single-command mode.

Create `packages/shell/src/shell.ts` — the Shell class coordinating parsing, routing, formatting:

```typescript
import { ShellCommand } from './parser';
import { ShellContext } from './types';

export class Shell {
  constructor(private ctx: ShellContext) {}

  async execute(args: string[]): Promise<string> {
    const cmd = parseCommand(args);
    const result = await route(cmd, this.ctx);
    return formatResult(result, cmd.flags.format || 'json');
  }

  async repl(): Promise<void> {
    // Implement REPL mode (D19.6)
  }
}
```

Create `packages/shell/src/types.ts` for internal types:

```typescript
import { LoomStore } from '@semantos/loom/services';
import { FlowRunner } from '@semantos/loom/services';
// ... other imports

export interface ShellContext {
  store: LoomStore;
  flowRunner: FlowRunner;
  // ... other service refs
  activeExtension: string;
  activeFacetId: string | null;
}
```

Commit: `phase-19/D19.1: Shell package scaffold — CLI binary, entry point, REPL loop`

---

## Step 2: Command Grammar Parser (D19.2)

Create `packages/shell/src/parser.ts` as specified in the PRD.

Implement `parseCommand(args: string[]): ShellCommand`:

1. **Extract verb**: first arg that is not a flag (doesn't start with `--`)
2. **Validate verb**: must be one of the 14 known verbs. If not, suggest closest match.
3. **Collect flags**: all `--key value` and `--boolean` pairs
4. **Remaining args**: type path + object ID (or just object ID for some verbs)
5. **Return ShellCommand** with all fields populated

Test case: `['new', 'trades.job.plumbing', '--urgency', 'high']`
Expected: `{ verb: 'new', typePath: 'trades.job.plumbing', objectId: undefined, flags: { urgency: 'high' } }`

Test case: `['inspect', 'job-1774']`
Expected: `{ verb: 'inspect', typePath: undefined, objectId: 'job-1774', flags: {} }`

Test case: `['list', '--type', 'governance.dispute', '--status', 'open', '--format', 'json']`
Expected: `{ verb: 'list', typePath: undefined, objectId: undefined, flags: { type: 'governance.dispute', status: 'open', format: 'json' } }`

Helpful error messages:
- Unknown verb `'foo'` → "Unknown verb 'foo'. Did you mean 'flow'? Available verbs: new, patch, transition, inspect, trace, verify, sign, publish, revoke, stake, vote, dispute, transfer, flow, eval, list"

Commit: `phase-19/D19.2: Command grammar parser — structured ShellCommand output, helpful errors`

---

## Step 3: Verb Router (D19.3)

Create `packages/shell/src/router.ts` as specified in the PRD.

Implement `route(cmd: ShellCommand, ctx: RouterContext): Promise<unknown>`:

For each verb:

- **new**: `ctx.store.createObject(cmd.typePath, cmd.flags)` with ownerId = active facet
- **patch**: `ctx.store.applyPatch(cmd.objectId, cmd.flags)`
- **transition**: `ctx.store.transitionObject(cmd.objectId, cmd.flags)`
- **inspect**: `ctx.store.getObject(cmd.objectId)`
- **trace**: get object + evidence chain (via store or separate method)
- **verify**: verify evidence chain hash integrity
- **sign**: attach facet signature to patches
- **publish**: `ctx.store.transitionObject(cmd.objectId, { visibility: 'published' })` + check capability 5
- **revoke**: `ctx.store.transitionObject(cmd.objectId, { visibility: 'revoked' })` + check capability 4
- **stake**: delegate to FlowRunner for governance flow
- **vote**: delegate to FlowRunner for voting flow
- **dispute**: delegate to FlowRunner for dispute flow
- **transfer**: `ctx.store.transitionObject(cmd.objectId, { owner: cmd.flags.to })` (stub-safe, works without Phase 14)
- **flow**: `ctx.flowRunner.startFlow(cmd.flags.flow)` or `ctx.flowRunner.advanceFlow(...)`
- **list**: `ctx.store.listObjects({ type: cmd.flags.type, ... })` with filters from flags
- **eval**: return `{ message: "Lisp axiom compiler not yet available (Phase 21)" }`

Capability checks:
- Before executing mutations, call `ctx.identity.hasCapability(ctx.activeFacetId, capabilityFlag)`
- If missing, return error (not exception): `{ error: "Missing capability X (publish) to perform this action" }`
- Show which capability is needed and which facet would need it

`--dry-run` flag: show what would execute without executing

Commit: `phase-19/D19.3: Verb router — service dispatch with capability checks, provenance, stub-safe`

---

## Step 4: Output Formatters (D19.4)

Create `packages/shell/src/formatters.ts` as specified in the PRD.

Implement `OutputFormatter.format(data: unknown, format: OutputFormat): string`:

- **json**: `JSON.stringify(data, null, 2)` — must be valid JSON parseable by `jq`
- **table**: aligned columns for arrays (list output)
  ```
  ID             TYPE                    VISIBILITY  OWNER         PATCHES
  job-1774       trades.job.plumbing     draft       facet-3a2b    3
  job-1775       trades.job.electrical   published   facet-3a2b    2
  ```
  - Responsive to terminal width (80–120 chars)
  - Right-align numbers, left-align strings
- **cell**: hex dump of cell bytes (for `inspect --format cell`)
  ```
  00000000  48 65 6c 6c 6f 20 57 6f 72 6c 64 21 00 00 00 00
  00000010  ...
  ```
- **csv**: for trace output (evidence chain)
  ```
  HASH,AUTHOR,ACTION,TIMESTAMP
  7f3a2b...1e,facet-3a2b,create,2026-03-29T14:32:15Z
  a91c4d...3f,facet-3a2b,patch,2026-03-29T14:32:16Z
  ```

All output to stdout. Errors to stderr.

Commit: `phase-19/D19.4: Output formatters — JSON, table, cell, CSV for Unix pipes`

---

## Step 5: Shell Configuration (D19.5)

Create `packages/shell/src/config.ts` as specified in the PRD.

Implement `loadConfig(): ShellConfig`:

1. Try to load `~/.semantos/config.toml`
2. Try to load `./.semantos.toml` in current directory (takes precedence)
3. Override with environment variables:
   - `SEMANTOS_MODE`: 'stub' | 'local' | 'cloud'
   - `SEMANTOS_FACET`: active facet ID
   - `SEMANTOS_EXTENSION`: default extension name
   - `SEMANTOS_FORMAT`: output format
   - `SEMANTOS_ENDPOINT`: API endpoint (optional)
4. Fill gaps with defaults: stub mode, no facet, core extension, JSON format

Config file (TOML):

```toml
[shell]
adapter_mode = "stub"
active_facet = "facet-3a2b"
default_extension = "trades-services"
default_format = "json"
api_endpoint = "http://localhost:8000"
```

Test: Create a config file with `adapter_mode = "cloud"`, set env var `SEMANTOS_MODE=stub`, verify result is `stub` mode (env wins).

Commit: `phase-19/D19.5: Shell configuration — TOML file, env var overrides, defaults`

---

## Step 6: Interactive REPL Mode (D19.6)

Create `packages/shell/src/repl.ts` as specified in the PRD.

Implement `REPLShell.repl(): Promise<void>`:

1. Initialize readline (Node.js `readline` module)
2. Set up prompt: `[facet-3a2b@trades] > ` (shows active facet and extension)
3. Read line from user
4. Parse command (reuse D19.2 parser)
5. Route and execute (reuse D19.3 router)
6. Format and output result (reuse D19.4 formatters)
7. Loop until 'exit'

Built-in commands:
- **help**: show verb table + examples
- **switch <facet-id>**: change active facet, update prompt
- **load <extension>**: change active extension, update prompt
- **exit**: quit REPL

Tab completion:
- Pressing TAB shows available completions for:
  - Verbs (new, patch, inspect, list, ...)
  - Type paths (trades.job, trades.job.plumbing, governance.dispute, ...)
  - Object IDs from current LoomStore

Command history: readline built-in (arrow keys navigate history)

Exit gracefully on Ctrl+C (SIGINT).

Commit: `phase-19/D19.6: Interactive REPL — readline, tab completion, command history, built-ins`

---

## Step 7: Gate Tests

Create `packages/__tests__/phase19-gate.test.ts`.

Implement all 18 tests as specified in the PRD:

- **T1–T4**: Parser tests (command parsing, error messages)
- **T5–T9**: Router tests (service dispatch, capability checks)
- **T10–T12**: Formatter tests (JSON, table, CSV output)
- **T13**: Config loading (file + env vars + defaults)
- **T14–T15**: REPL tests (prompt, eval verb)
- **T16–T18**: Anti-lock tests (no React imports, service-only imports, stdout/stderr)

Commit: `phase-19/T1-T18: full gate test suite — parser, router, formatters, config, REPL, anti-lock`

---

## Step 8: CI Gate Extension

Verify the existing `.github/workflows/gate.yml` will pick up `packages/__tests__/phase19-gate.test.ts` automatically.

Add a lint check specific to Phase 19:

```bash
# No React imports in shell package
if grep -rn "import.*from.*react" packages/shell/src/ --include="*.ts" --include="*.tsx" | grep -v "node_modules"; then
  echo "FAIL: React imports found in shell package"
  exit 1
fi

# No canvas/UI imports in shell package
if grep -rn "from.*@semantos/loom.*canvas\|from.*@semantos/loom.*ui\|from.*@semantos/loom.*components" packages/shell/src/ --include="*.ts"; then
  echo "FAIL: UI imports found in shell package"
  exit 1
fi
```

This can be added to the lint job in `.github/workflows/gate.yml`.

Commit: `phase-19/CI: anti-lock lint checks for React and UI containment`

---

## Step 9: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. **Adversarial review** of every new and modified file
2. Check for:
   - Any function that is a stub or returns hardcoded data
   - Parser errors for edge cases (e.g., `--flag` with no value, duplicate flags)
   - Router errors that are exceptions instead of error responses
   - Formatter output that is not valid for intended consumption (e.g., JSON that jq can't parse)
   - Config loading that doesn't respect file precedence (project .semantos.toml should win over ~/.semantos/config.toml? Or vice versa?)
   - REPL prompt that doesn't update when facet/extension changes
   - Tab completion that crashes on missing objects
   - Commands that call React hooks or import React
   - Output that mixes stdout and stderr (tests should verify stderr is used for errors)

3. Write errata doc as `docs/prd/PHASE-19-ERRATA.md`

---

## Completion Criteria

- [ ] `packages/shell/` exists with package.json, tsconfig.json, src/ directory
- [ ] `packages/shell/src/index.ts` detects REPL vs single-command mode
- [ ] `packages/shell/src/parser.ts` parses commands into ShellCommand types with helpful errors
- [ ] `packages/shell/src/router.ts` routes verbs to services with capability checks
- [ ] `packages/shell/src/formatters.ts` outputs JSON, table, cell, CSV
- [ ] `packages/shell/src/config.ts` loads from file + env vars with correct precedence
- [ ] `packages/shell/src/repl.ts` implements readline REPL with tab completion and history
- [ ] `packages/shell/src/shell.ts` coordinates parsing, routing, formatting
- [ ] Tests T1–T18 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] `grep -r "import.*react" packages/shell/src/` returns nothing
- [ ] All commits follow `phase-19/D19.N:` naming convention
- [ ] Branch is `phase-19-semantic-shell`
- [ ] Errata sprint complete with `docs/prd/PHASE-19-ERRATA.md`

---

## Next Phase

Phase 19.5 adds Plexus identity auth to the shell: `SEMANTOS_FACET` environment variable, capability checks via PlexusService, BRC-100 signed requests.
