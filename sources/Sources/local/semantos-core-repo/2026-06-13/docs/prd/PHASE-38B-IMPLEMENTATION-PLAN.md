---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-38B-IMPLEMENTATION-PLAN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.714697+00:00
---

# Phase 38B Implementation Plan — Handler Registry & Reference Handler

**Date**: 2026-04-17
**Precondition**: Phase 38A merged to `main` at `3faa569`. PRs #79 (settlement rename) and #80 (semantos-ir) merged or ready.
**PRD**: `docs/prd/PHASE-38B-PROMPT.md` (read this first — it is the spec)
**Goal**: Build the handler registry and one reference handler (`process.killByPort`). This unblocks 38C (host.exec verb end-to-end).

---

## Where This Fits

```
DONE ✅  38A (HostCommand + HOST_EXEC + trust-tier)
         IR scaffold (semantos-ir, PR #80)
         Settlement rename (PR #79)

► YOU ARE HERE ► 38B — handler registry + reference handler

NEXT     38C — host.exec verb end-to-end (publish→gate→execute→receipt)
         38G — Helm UI (Talk→approval→receipt) — the headline demo
```

38B is the smallest step on the hot path. It gives 38C something to dispatch to. Without it, the `host.exec` stub in `router.ts:191-198` has nowhere to go.

---

## Context: What Already Exists

Read these files at session start. They're the foundation you're building on:

| File | What it gives you |
|---|---|
| `configs/extensions/host-ops.json` | HostCommand schema, HOST_EXEC capability (id=11), trust-tier governance config. The `fields` array defines the HostCommand payload shape — `handler`, `args`, `hatId`, `hatCertId`, `hatSig`, `requestedAt`, plus outcome fields. |
| `packages/shell/src/router.ts` (lines 191-198) | The `host.exec` stub that currently returns `HOST_EXEC_NOT_IMPLEMENTED`. Your registry wires into this. 38C replaces the stub with a real dispatcher; 38B just builds the registry it dispatches to. |
| `packages/shell/src/capabilities.ts` | `'host.exec': 0x0001000b` mapping. The capability gate already fires before the router case is reached. |
| `packages/shell/src/error-codes.ts` | Error code constants. Add new ones here (e.g. `UNKNOWN_HANDLER`, `INVALID_HANDLER_ARGS`, `HANDLER_TIMEOUT`, `HANDLER_CRASHED`). |
| `packages/shell/src/types.ts` | `ShellContext` — the runtime context. Handlers receive a subset of this (hat identity, timeout). |
| `packages/shell/src/route-helpers.ts` | `isShellError`, `requireObject` patterns. Follow the same error-object convention. |
| `packages/__tests__/phase38-gate.test.ts` | 13 existing gate tests from 38A. You add to this file. Tests T1-T11b must still pass. |
| `docs/prd/PHASE-38B-PROMPT.md` | The authoritative spec. Everything below is derived from it. If this plan and the PRD disagree, the PRD wins. |

---

## Branch Setup

```bash
git fetch origin
git checkout main
git pull --ff-only origin main
# Verify main has 38A:
git log --oneline -3
# Should show 3faa569 "Phase 38A: trust-tier fields, HostCommand type, HOST_EXEC capability (#78)"
# or a later commit if PRs 79/80 have also merged

# Cut the phase branch (or reuse if it exists from 38A):
git checkout -b phase-38-voice-to-execution 2>/dev/null || git checkout phase-38-voice-to-execution
git merge --ff-only origin/main   # bring up to date
```

If PRs #79 and #80 are already merged to `main` when you start, you'll have `packages/settlement/` (renamed from paskian) and `packages/semantos-ir/` available. Neither affects 38B work — they're parallel tracks.

---

## Step 1: Handler Types & Registry (D38B.1)

### 1.1 Create `packages/shell/src/host-exec/types.ts`

The PRD specifies these types exactly. Implement them as written in `PHASE-38B-PROMPT.md` §1.1:

- `HandlerArgs` — `Record<string, unknown>` with optional `dryRun: boolean`
- `HandlerOk` — `{ ok: true, exitCode: number, stdout: string, stderr: string, durationMs: number }`
- `HandlerError` — `{ ok: false, code: string, message: string, details?: unknown }`
- `HandlerResult` — `HandlerOk | HandlerError`
- `HandlerContext` — `{ hatId: string, hatCertId: string, timeoutMs: number }` (default timeout 10_000)
- `Handler` — `(args: HandlerArgs, ctx: HandlerContext) => Promise<HandlerResult>`
- `HandlerManifest` — `{ id: string, description: string, argsSchema: Record<string, { type: string; required?: boolean }>, capabilityId: number }`

### 1.2 Create `packages/shell/src/host-exec/registry.ts`

The PRD specifies the full implementation in §1.2. Key behaviors:

- `registerHandler(manifest, fn)` — throws if ID already registered (double-registration protection)
- `getHandler(id)` — returns `{ manifest, fn }` or `null`
- `listHandlers()` — returns all registered manifests
- `invokeHandler(id, args, ctx)` — the core dispatch:
  1. Unknown handler → `{ ok: false, code: 'UNKNOWN_HANDLER' }`
  2. Validate required args from manifest's `argsSchema` → `{ ok: false, code: 'INVALID_ARGS' }` on missing
  3. Run handler with `Promise.race` against timeout → `{ ok: false, code: 'HANDLER_TIMEOUT' }` on timeout
  4. Catch any thrown exception → `{ ok: false, code: 'HANDLER_CRASHED' }` (handlers should never throw, but belt-and-suspenders)

### 1.3 Create `packages/shell/src/host-exec/index.ts`

Barrel export: re-export types, `registerHandler`, `getHandler`, `listHandlers`, `invokeHandler`.

### 1.4 Add error codes

In `packages/shell/src/error-codes.ts`, add:

```typescript
export const UNKNOWN_HANDLER = 'UNKNOWN_HANDLER';
export const INVALID_HANDLER_ARGS = 'INVALID_HANDLER_ARGS';
export const HANDLER_TIMEOUT = 'HANDLER_TIMEOUT';
export const HANDLER_CRASHED = 'HANDLER_CRASHED';
```

### 1.5 Commit

```
phase-38/D38B.1: handler registry with allowlist + timeout + arg validation

- HandlerManifest, HandlerResult, HandlerContext types
- Registry: registerHandler, getHandler, listHandlers, invokeHandler
- Timeout via Promise.race (default 10s)
- Unknown handler → structured error, never exception
- Error codes: UNKNOWN_HANDLER, INVALID_HANDLER_ARGS, HANDLER_TIMEOUT, HANDLER_CRASHED
```

---

## Step 2: Reference Handler — `process.killByPort` (D38B.2)

### 2.1 Create `packages/shell/src/host-exec/handlers/process-kill-by-port.ts`

The PRD specifies the behavior in §2.1. Key requirements:

**Args validation:**
- `port: number` — required, must be integer 1–65535. Non-integer or out-of-range → `INVALID_ARGS`.
- `signal?: 'SIGTERM' | 'SIGKILL'` — optional, default `'SIGTERM'`.
- `dryRun?: boolean` — optional.

**PID resolution:**
- Use `lsof -i :<port> -sTCP:LISTEN -t` (unix only). Parse stdout as integer PIDs.
- On non-unix (Windows): return `{ ok: false, code: 'PLATFORM_UNSUPPORTED' }`.
- If no process listening: return `{ ok: true, exitCode: 0, stdout: 'no process on port <port>', stderr: '' }`.

**Dry-run mode (`dryRun: true`):**
- Resolve PIDs, return them in stdout. Do NOT kill.
- `{ ok: true, exitCode: 0, stdout: 'dry-run: PID(s) [1234, 5678] on port 9000', stderr: '', durationMs: <elapsed> }`

**Wet-run mode:**
- Resolve PID. Call `process.kill(pid, signal)` — NOT `execSync("kill " + pid)`. No shell interpolation ever.
- Wait 500ms for process to die.
- Return `{ ok: true, exitCode: 0, stdout: 'killed PID <pid> on port <port>', stderr: '', durationMs: <elapsed> }`.

**Output capping:**
- `stdout` and `stderr` truncated to 4096 bytes. If truncated, append `\n[truncated, full output hash: <sha256>]`.

**Safety:**
- Port is validated as integer 1–65535 BEFORE being interpolated into the `lsof` command string.
- The `lsof` command uses `execFile` (not `exec`/`execSync`) to avoid shell injection. Arguments passed as an array, not a string.

### 2.2 Create `packages/shell/src/host-exec/handlers/index.ts`

Side-effect import barrel. Each handler file self-registers via `registerHandler()` at import time:

```typescript
// Side-effect imports — each file calls registerHandler() on import.
import './process-kill-by-port';
```

Shell startup (or lazy first-use in 38C) imports this barrel once. For 38B, the gate tests import it directly.

### 2.3 Self-registration pattern

At the bottom of `process-kill-by-port.ts`:

```typescript
import { registerHandler } from '../registry';

registerHandler(
  {
    id: 'process.killByPort',
    description: 'Send a signal to the process listening on a given TCP port',
    argsSchema: {
      port: { type: 'number', required: true },
      signal: { type: 'string' },
      dryRun: { type: 'boolean' },
    },
    capabilityId: 11,  // HOST_EXEC from host-ops.json
  },
  killByPortHandler,  // the async function defined above
);
```

### 2.4 Commit

```
phase-38/D38B.2: process.killByPort reference handler with dry-run and timeout

- PID resolution via lsof (execFile, no shell interpolation)
- Port validated as integer 1-65535 before any system call
- Dry-run returns resolved PIDs without killing
- Output capped at 4KB with hash on truncation
- Self-registers via registerHandler() on import
```

---

## Step 3: Gate Tests (D38B.3)

### 3.1 Add to `packages/__tests__/phase38-gate.test.ts`

Add a new `describe` block. The existing T1-T11b tests remain untouched.

**Tests to add (per PRD §3):**

```
T12: getHandler('process.killByPort') returns non-null manifest
T13: invokeHandler('does-not-exist', {}, ctx) returns {ok: false, code: 'UNKNOWN_HANDLER'}
T14: invokeHandler('process.killByPort', {}, ctx) returns {ok: false, code: 'INVALID_ARGS'} (missing port)
T15: invokeHandler('process.killByPort', {port: 'abc'}, ctx) returns {ok: false, code: 'INVALID_ARGS'} (non-integer)
T16: invokeHandler('process.killByPort', {port: 9000, dryRun: true}, ctx) resolves without killing
T17: handler that sleeps 20s with timeoutMs: 100 returns HANDLER_TIMEOUT
T18: registry rejects double-registration of the same handler id
```

**Test fixture for T17 (timeout test):**

Register a temporary `test.sleepy` handler inside the test that does `await new Promise(r => setTimeout(r, 20000))`, invoke it with `{ timeoutMs: 100 }`, assert `{ ok: false, code: 'HANDLER_TIMEOUT' }`. Unregister after test if the registry supports it, or accept the side-effect (it's a test-only handler that won't collide with production code).

**Test context fixture:**

```typescript
const testCtx: HandlerContext = {
  hatId: 'test-hat',
  hatCertId: 'test-cert',
  timeoutMs: 10_000,
};
```

**Import the handler barrel at the top of the test file:**

```typescript
import '../shell/src/host-exec/handlers';  // triggers self-registration
import { getHandler, invokeHandler, registerHandler } from '../shell/src/host-exec/registry';
import type { HandlerContext } from '../shell/src/host-exec/types';
```

### 3.2 Run

```bash
bun test packages/__tests__/phase38-gate.test.ts    # all T1-T18 pass
bun test packages/__tests__/                          # cumulative, no new failures
bun run check                                         # typecheck clean
```

### 3.3 Commit

```
phase-38/D38B.3: gate tests for handler registry and process.killByPort

- T12-T18: registry lookup, unknown handler, missing args, type validation,
  dry-run, timeout, double-registration rejection
- All prior T1-T11b still pass
```

---

## Step 4: Verification

Before pushing, verify everything:

```bash
# Typecheck
bun run check

# Phase 38 gate tests (should be 18+ now)
bun test packages/__tests__/phase38-gate.test.ts

# Full cumulative suite (no new failures vs baseline)
bun test packages/__tests__/

# Confirm the registry is importable and handler is registered
bun -e "
  import './packages/shell/src/host-exec/handlers';
  import { listHandlers } from './packages/shell/src/host-exec/registry';
  console.log(JSON.stringify(listHandlers(), null, 2));
"
# Should print: [{ id: 'process.killByPort', description: '...', ... }]
```

---

## Anti-Bullshit Checklist (from PRD)

Before committing, verify each of these. If any fails, fix it before pushing:

- [ ] **Allowlist, never denylist.** Unknown handler IDs return a structured error object. No fallthrough, no default execution.
- [ ] **No shell interpolation.** `process-kill-by-port.ts` uses `execFile` with an argument array, never `exec`/`execSync` with string interpolation. The port is validated as integer before appearing in any system call.
- [ ] **Handlers are pure functions of `(args, ctx)`.** No global state, no file system assumptions beyond `lsof`.
- [ ] **Output capped at 4KB.** `stdout` and `stderr` truncated with hash suffix if over 4096 bytes.
- [ ] **No background execution.** Handler runs to completion or times out. No `spawn` without `kill` on timeout. No promises that outlive the handler call.
- [ ] **Errors are objects, not exceptions.** Every error path returns `{ ok: false, code, message }`. The `invokeHandler` wrapper catches any thrown exception and converts to `HANDLER_CRASHED`.
- [ ] **Dry-run is mandatory.** `process.killByPort` with `dryRun: true` resolves PIDs and returns without killing.

---

## What This Does NOT Do

- **Does not replace the `host.exec` router stub.** The stub at `router.ts:191-198` still returns `HOST_EXEC_NOT_IMPLEMENTED`. That's 38C's job — wiring the registry into the router with publish-then-execute semantics.
- **Does not add additional handlers.** Only `process.killByPort`. Additional handlers (fs.read, git.status, etc.) land in Phase 38.x errata per the risk register.
- **Does not modify the HostCommand schema.** `host-ops.json` is untouched.
- **Does not touch Helm UI.** That's 38G.

---

## Exit Criteria

- [ ] `packages/shell/src/host-exec/` directory exists with `types.ts`, `registry.ts`, `index.ts`, `handlers/index.ts`, `handlers/process-kill-by-port.ts`
- [ ] Registry allowlist enforced: unknown handler → `UNKNOWN_HANDLER` error object, no exception
- [ ] `process.killByPort` handler registered, dry-run works without side effect
- [ ] Timeout honored (default 10s, overridable via `ctx.timeoutMs`)
- [ ] 7 new gate tests pass (T12-T18)
- [ ] All prior gate tests still pass (T1-T11b)
- [ ] `bun run check` clean
- [ ] Branch: `phase-38-voice-to-execution`, 3 commits (D38B.1, D38B.2, D38B.3)

Hand off to 38C.

---

## How This Sequences With the Semantic IR

The Semantic IR architecture (`docs/SEMANTIC-IR-ARCHITECTURE.md`) classifies `host.exec` as a **Power** — an exercise of authority to change relations (specifically, to execute a whitelisted host handler). The handler registry you're building is the enforcement mechanism for that power: the allowlist is a structural prohibition (only registered handlers can execute), the capability gate is a permission (you need HOST_EXEC), and the timeout + dry-run are conditions.

The SIR doesn't affect 38B code. It's a design document for Windows 3+. But when `host.exec` eventually gets a SIR node (Window 4-5), the handler registry is the infrastructure that backs the `action: 'host.exec'` field on the SIR Power node. The handler manifest (`id`, `argsSchema`, `capabilityId`) maps directly to the SIR constraint structure. This is intentional — the registry was always the enforcement layer for execution powers; the SIR just gives it a name.
