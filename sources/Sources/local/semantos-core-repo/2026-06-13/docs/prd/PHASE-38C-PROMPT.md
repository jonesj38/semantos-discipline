---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-38C-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.715808+00:00
---

# Phase 38C Execution Prompt — `host.exec` Shell Verb

> Paste into a fresh session. Hot-path sub-phase. Requires 38A + 38B on `phase-38-voice-to-execution`.

## Context

This is where a `HostCommand` becomes real: the shell verb `host.exec` parses args, gates on `HOST_EXEC` capability, creates a draft `HostCommand` object, signs it with the active hat's cert, **publishes it**, then invokes the handler, then appends the result patch.

Publish-before-execute is deliberate — even if the handler crashes, the request is already evidence. You can always answer "did this hat try to kill port 9000?" by reading the object chain.

---

## CRITICAL: READ THESE FILES FIRST

- `docs/prd/PHASE-38-VOICE-TO-EXECUTION.md` — epic
- `docs/prd/PHASE-38A-PROMPT.md` — HostCommand schema
- `docs/prd/PHASE-38B-PROMPT.md` — registry API
- `packages/shell/src/parser.ts` — `KNOWN_VERBS`, `parseCommand` — how to add a verb
- `packages/shell/src/router.ts` — dispatch pattern; `route(cmd, ctx)`
- `packages/shell/src/capabilities.ts` — `CAPABILITY_MAP`, `getRequiredCapability`, `MUTATION_VERBS`
- `packages/shell/src/commands/doc.ts` — reference for a command module that creates + signs + publishes
- `packages/shell/src/identity.ts` — how existing verbs get `ctx.identity.getActiveFacet()` + cert
- `packages/loom/src/services/LoomStore.ts` — `createObjectFromType`, `dispatch`, publish transition
- `packages/shell/src/error-codes.ts` — add new codes here

---

## ANTI-BULLSHIT RULES

1. **Publish before execute.** The sequence is: create draft → sign → publish → invoke handler → append result patch. NOT invoke-then-record. If publish fails, the handler is never called.
2. **Capability check is non-negotiable.** Gate via `PlexusService.presentCapability(HOST_EXEC)` before any side effect. On failure, return a structured error; nothing is written to the store.
3. **The signature covers the exact bytes.** `hatSig = sign(sha256(handler || "|" || canonicalArgs || "|" || hatId || "|" || requestedAt))`. Canonical args = `JSON.stringify(args, Object.keys(args).sort())`. Use whatever existing signing helper the identity layer exposes (do NOT roll your own ECDSA).
4. **Result patch is a new patch on the published object.** Publish is LINEAR; the result patch is APPEND-ONLY metadata, not a state rewrite.
5. **No `--dry-run` shortcut bypass.** `--dry-run` still goes through the capability gate. It does NOT skip the publish step (a dry-run is still a recorded intent).
6. **Handler crashes must not corrupt the object.** If the handler returns `{ok: false}` or the registry reports a timeout, the result patch records the failure. The published object stays intact.

---

## PART 0: GIT HYGIENE

```bash
git checkout phase-38-voice-to-execution
git pull --ff-only
```

---

## Step 1: Parser — Add `host.exec` Verb (D38C.1)

### 1.1 Update `packages/shell/src/parser.ts`

Add `'host.exec'` to `KNOWN_VERBS`. Verb arguments:

- Positional: `<handler>` (required)
- Flags: `--arg <key=value>` (repeatable), `--dry-run`, `--facet <id>`, `--timeout <ms>`

`parseCommand` should put structured `args` into the resulting `ShellCommand`. Reuse existing flag parsing; do not fork.

### 1.2 Commit

```bash
git commit -m "phase-38/D38C.1: add host.exec verb to parser"
```

---

## Step 2: Router & Capability Gate (D38C.2)

### 2.1 Update `packages/shell/src/capabilities.ts`

- Add `host.exec` to `MUTATION_VERBS`.
- Add `host.exec` → `HOST_EXEC` in `CAPABILITY_MAP`.

### 2.2 Create `packages/shell/src/commands/host-exec.ts`

Export `routeHostExec(cmd, ctx)`:

```ts
export async function routeHostExec(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  // 1. Parse args from cmd
  const handlerId = cmd.args?.[0];
  if (!handlerId) return shellError('MISSING_HANDLER', 'host.exec requires a handler id');

  // 2. Active facet
  const facet = ctx.identity.getActiveFacet();
  if (!facet) return shellError('NO_ACTIVE_FACET', 'no active hat');
  if (!facet.certId) return shellError('NO_HAT_CERT', 'active hat has no BRC-100 cert');

  // 3. Capability gate (Plexus)
  const granted = await ctx.plexus.presentCapability(HOST_EXEC_ID, facet.id);
  if (!granted.ok) return shellError('CAPABILITY_CHECK_FAILED', granted.reason);

  // 4. Canonicalize args, build request fields
  const args = collectArgFlags(cmd); // --arg key=value pairs → object
  const requestedAt = new Date().toISOString();
  const canonical = canonicalize({ handler: handlerId, args, hatId: facet.id, requestedAt });
  const hatSig = await ctx.identity.sign(facet.id, canonical);

  // 5. Create draft HostCommand
  const typeDef = ctx.config.getConfig()?.objectTypes.find(t => t.name === 'HostCommand');
  if (!typeDef) return shellError('NO_CONFIG', 'HostCommand type not loaded');
  const objId = ctx.store.createObjectFromType(typeDef, undefined, facet.id, facet.capabilities, false);
  for (const [k, v] of Object.entries({
    handler: handlerId, args: JSON.stringify(args),
    hatId: facet.id, hatCertId: facet.certId,
    hatSig, requestedAt,
  })) {
    ctx.store.dispatch({ type: 'UPDATE_PAYLOAD', objectId: objId, field: k, value: v });
  }

  // 6. Publish (LINEAR transition)
  const pub = ctx.store.publishObject(objId, facet.id, facet.capabilities);
  if (!pub.ok) return shellError('PUBLISH_FAILED', pub.reason);

  // 7. Dry-run short-circuit: do NOT invoke handler
  if (cmd.flags['dry-run']) {
    return { ok: true, hostCommandId: objId, dryRun: true };
  }

  // 8. Invoke handler
  const timeoutMs = Number(cmd.flags.timeout ?? 10_000);
  const result = await invokeHandler(handlerId, args, { hatId: facet.id, hatCertId: facet.certId, timeoutMs });

  // 9. Append result patch (append-only, does not rewrite state)
  ctx.store.dispatch({
    type: 'ADD_PATCH',
    objectId: objId,
    patch: {
      id: `patch-${Date.now()}-result`,
      kind: 'evidence_append',
      timestamp: Date.now(),
      delta: result,       // full handler result object
      facetId: facet.id,
    },
  });
  // Also update payload fields startedAt/finishedAt/exitCode/stdout/stderr for quick reads.
  // …

  return { ok: true, hostCommandId: objId, result };
}
```

### 2.3 Update `packages/shell/src/router.ts`

Add the dispatch case:

```ts
if (cmd.verb === 'host.exec') return routeHostExec(cmd, ctx);
```

### 2.4 Update `packages/shell/src/browser.ts`

Re-export `routeHostExec` if needed for testing from loom. (Usually `route()` is enough — only add the explicit export if a test imports it directly.)

### 2.5 Commit

```bash
git add packages/shell/src/commands/host-exec.ts packages/shell/src/router.ts packages/shell/src/capabilities.ts
git commit -m "phase-38/D38C.2: host.exec router — capability gate, sign, publish, invoke, append result"
```

---

## Step 3: Error Codes (D38C.3)

Add to `packages/shell/src/error-codes.ts`:

```ts
export const MISSING_HANDLER = 'MISSING_HANDLER';
export const NO_HAT_CERT = 'NO_HAT_CERT';
export const HANDLER_INVOKE_FAILED = 'HANDLER_INVOKE_FAILED';
```

(`CAPABILITY_CHECK_FAILED`, `NO_ACTIVE_FACET`, `NO_CONFIG`, `PUBLISH_FAILED` already exist.)

Commit:

```bash
git commit -m "phase-38/D38C.3: error codes for host.exec"
```

---

## Step 4: Gate Tests (D38C.4)

Add to `packages/__tests__/phase38-gate.test.ts`:

1. `parseCommand(['host.exec', 'process.killByPort', '--arg', 'port=9000'])` returns a valid `ShellCommand` with the right verb and args.
2. Without `HOST_EXEC` capability: `route(cmd, ctx)` returns `{code: 'CAPABILITY_CHECK_FAILED'}`, no object created.
3. With `HOST_EXEC` + unknown handler: object IS published (request is evidence), result patch has `code: 'UNKNOWN_HANDLER'`.
4. With `HOST_EXEC` + `process.killByPort` + `--dry-run`: object published, no handler side effect, dry-run flag recorded.
5. Signature validation: the published object's `hatSig` verifies against the canonical payload.
6. `ADD_PATCH` with `kind: 'evidence_append'` does NOT rewind the object's published state (linearity invariant).
7. Round-trip: after `host.exec`, `ctx.store.getObject(id)?.visibility === 'published'`.

Use a **test handler** that never touches real processes. Register it under a fixture id like `test.echo` in test setup.

Commit:

```bash
git commit -m "phase-38/D38C.4: gate tests for host.exec — capability gate, publish, sign, dry-run"
```

---

## Exit Criteria

- [ ] `host.exec` in `KNOWN_VERBS`, mapped to `HOST_EXEC` capability.
- [ ] Capability check fires before publish; no object created on deny.
- [ ] Publish happens before handler invocation.
- [ ] Result is append-only patch; object state stays LINEAR/published.
- [ ] `--dry-run` publishes but does not invoke.
- [ ] `hatSig` verifies.
- [ ] All gates pass.

Hand off to 38D, 38G.
