---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-38B-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.706175+00:00
---

# Phase 38B Execution Prompt — Handler Registry & Reference Handler

> Paste this into a fresh session. Hot-path sub-phase. Requires 38A merged to `phase-38-voice-to-execution`.

## Context

`HostCommand` (38A) is inert without something to dispatch to. This sub-phase builds the handler registry and ships **one** reference handler: `process.killByPort`.

The registry is a tight allowlist. User-supplied strings never run as shell. Every handler is a typed TypeScript function, registered by name, vetted per-handler.

This is deliberately scoped to one handler. Additional handlers (fs.read, git.status, payment.send, etc.) land in Phase 38.x errata branches after the full end-to-end path is proven.

---

## CRITICAL: READ THESE FILES FIRST

- `docs/prd/PHASE-38-VOICE-TO-EXECUTION.md` — epic + acceptance test
- `docs/prd/PHASE-38A-PROMPT.md` — the schema you're dispatching to
- `configs/extensions/host-ops.json` — HostCommand schema from 38A
- `packages/shell/src/router.ts` — pattern for error objects vs exceptions
- `packages/shell/src/route-helpers.ts` — `isShellError`, `requireObject` pattern
- `packages/shell/src/commands/extract.ts` — reference for a command module using fs + path
- `packages/shell/src/error-codes.ts` — error code constants; add new ones here

---

## ANTI-BULLSHIT RULES

1. **Allowlist, never denylist.** The registry maps string IDs → typed functions. Unknown IDs return a structured error, never execute.
2. **No shell interpolation.** Handlers take structured args only. If a handler needs to call `kill`, it calls `process.kill(pid, 'SIGTERM')` — not `execSync("kill " + pid)`.
3. **Handlers are pure functions of `(args, ctx)`.** No hidden global state. No file system assumptions beyond what's declared.
4. **Output is capped.** `stdout` and `stderr` truncate to 4 KB. Longer output is hashed and the hash goes in the result cell.
5. **No background execution.** Handlers run to completion or time out in 10s. No `spawn` without `.kill()` on timeout. No promises that outlive the handler call.
6. **Errors are objects, not exceptions.** A handler returns `{ok: false, code, message}` or `{ok: true, exitCode, stdout, stderr}`. Never `throw`.
7. **Dry-run is mandatory.** Every handler must support a `dryRun: true` arg that validates args and returns the plan without side effects.

---

## PART 0: GIT HYGIENE

```bash
git checkout phase-38-voice-to-execution
git pull --ff-only
# Optionally cut a sub-branch if you want isolation:
# git checkout -b phase-38-voice-to-execution/D38B
```

---

## Step 1: Handler Types & Registry (D38B.1)

### 1.1 Create `packages/shell/src/host-exec/types.ts`

```ts
export interface HandlerArgs {
  [key: string]: unknown;
  dryRun?: boolean;
}

export interface HandlerOk {
  ok: true;
  exitCode: number;
  stdout: string;
  stderr: string;
  durationMs: number;
}

export interface HandlerError {
  ok: false;
  code: string;        // e.g. HANDLER_TIMEOUT, INVALID_ARGS, PERMISSION_DENIED
  message: string;
  details?: unknown;
}

export type HandlerResult = HandlerOk | HandlerError;

export interface HandlerContext {
  hatId: string;
  hatCertId: string;
  timeoutMs: number;   // default 10_000
}

export type Handler = (args: HandlerArgs, ctx: HandlerContext) => Promise<HandlerResult>;

export interface HandlerManifest {
  id: string;                     // e.g. "process.killByPort"
  description: string;
  argsSchema: Record<string, { type: string; required?: boolean }>;
  capabilityId: number;           // must be HOST_EXEC id from 38A
}
```

### 1.2 Create `packages/shell/src/host-exec/registry.ts`

```ts
import type { Handler, HandlerManifest, HandlerResult, HandlerContext, HandlerArgs } from './types';

const handlers = new Map<string, { manifest: HandlerManifest; fn: Handler }>();

export function registerHandler(manifest: HandlerManifest, fn: Handler): void {
  if (handlers.has(manifest.id)) {
    throw new Error(`Handler already registered: ${manifest.id}`);
  }
  handlers.set(manifest.id, { manifest, fn });
}

export function getHandler(id: string): { manifest: HandlerManifest; fn: Handler } | null {
  return handlers.get(id) ?? null;
}

export function listHandlers(): HandlerManifest[] {
  return [...handlers.values()].map(h => h.manifest);
}

export async function invokeHandler(
  id: string,
  args: HandlerArgs,
  ctx: HandlerContext,
): Promise<HandlerResult> {
  const entry = handlers.get(id);
  if (!entry) {
    return { ok: false, code: 'UNKNOWN_HANDLER', message: `No handler registered: ${id}` };
  }
  // Validate args against manifest (required fields present, basic types)
  for (const [k, spec] of Object.entries(entry.manifest.argsSchema)) {
    if (spec.required && args[k] === undefined) {
      return { ok: false, code: 'INVALID_ARGS', message: `Missing required arg: ${k}` };
    }
  }
  try {
    return await Promise.race([
      entry.fn(args, ctx),
      new Promise<HandlerResult>(resolve =>
        setTimeout(
          () => resolve({ ok: false, code: 'HANDLER_TIMEOUT', message: `Timeout after ${ctx.timeoutMs}ms` }),
          ctx.timeoutMs,
        ),
      ),
    ]);
  } catch (err) {
    return {
      ok: false,
      code: 'HANDLER_CRASHED',
      message: err instanceof Error ? err.message : String(err),
    };
  }
}
```

### 1.3 Commit

```bash
git add packages/shell/src/host-exec/types.ts packages/shell/src/host-exec/registry.ts
git commit -m "phase-38/D38B.1: handler registry with allowlist + timeout + arg validation"
```

---

## Step 2: Reference Handler — `process.killByPort` (D38B.2)

### 2.1 Create `packages/shell/src/host-exec/handlers/process-kill-by-port.ts`

Behavior:

- Args: `{port: number, signal?: 'SIGTERM' | 'SIGKILL'}` (default SIGTERM)
- Dry-run: resolves the PID(s) listening on the port, returns them, does NOT kill.
- Wet-run: resolves PID, calls `process.kill(pid, signal)`, waits 500ms, returns the PID and final exit status.
- Linux/macOS only for Phase 38. Windows returns `PLATFORM_UNSUPPORTED`.

Resolve PIDs via `lsof -i :<port> -sTCP:LISTEN -t` on unix, parsed as integers. Do NOT shell-interpolate the port — validate it's an integer 1–65535 first.

Register in the same file:

```ts
registerHandler(
  {
    id: 'process.killByPort',
    description: 'Send a signal to the process listening on a given TCP port',
    argsSchema: {
      port: { type: 'number', required: true },
      signal: { type: 'string' },
      dryRun: { type: 'boolean' },
    },
    capabilityId: HOST_EXEC_ID,
  },
  async (args, ctx) => { /* … */ },
);
```

Import the HOST_EXEC id from wherever 38A exported it (or read from config).

### 2.2 Auto-register handlers

Create `packages/shell/src/host-exec/handlers/index.ts` that side-effect-imports each handler file. Register call happens at import. Shell startup (or lazy first-use) imports this barrel once.

### 2.3 Commit

```bash
git add packages/shell/src/host-exec/handlers/
git commit -m "phase-38/D38B.2: process.killByPort reference handler with dry-run and timeout"
```

---

## Step 3: Gate Tests (D38B.3)

Add to `packages/__tests__/phase38-gate.test.ts`:

1. `getHandler('process.killByPort')` returns a non-null manifest.
2. `invokeHandler('does-not-exist', {}, ctx)` returns `{ok: false, code: 'UNKNOWN_HANDLER'}`.
3. `invokeHandler('process.killByPort', {}, ctx)` returns `{ok: false, code: 'INVALID_ARGS'}` (missing port).
4. `invokeHandler('process.killByPort', {port: 'abc'}, ctx)` returns `{ok: false, code: 'INVALID_ARGS'}` (non-integer).
5. `invokeHandler('process.killByPort', {port: 9000, dryRun: true}, ctx)` resolves without killing. Stdout contains the resolved PIDs (or empty if port not in use).
6. Timeout: a handler that sleeps 20s with `timeoutMs: 100` returns `HANDLER_TIMEOUT`.
7. Handler registry rejects double-registration of the same id.

Commit:

```bash
git add packages/__tests__/phase38-gate.test.ts
git commit -m "phase-38/D38B.3: gate tests for handler registry and process.killByPort"
```

---

## Exit Criteria

- [ ] Registry allowlist enforced; unknown → `UNKNOWN_HANDLER` object, no exception.
- [ ] `process.killByPort` handler registered, dry-run works without side effect.
- [ ] Timeout honored (10s default).
- [ ] All gate tests pass.
- [ ] All prior gates still pass.

Hand off to 38C.
