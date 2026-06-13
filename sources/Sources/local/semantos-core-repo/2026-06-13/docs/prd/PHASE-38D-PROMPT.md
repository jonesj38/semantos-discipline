---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-38D-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.669970+00:00
---

# Phase 38D Execution Prompt — Audit Verification CLI

> Paste into a fresh session. **Parallel track** — starts as soon as 38C is on `phase-38-voice-to-execution`. Not on the hot path.

## Context

Every `HostCommand` is a signed, published, LINEAR object with an append-only patch chain. That's the *claim*. This sub-phase ships the CLI that *verifies* the claim — so auditors (and the user) can inspect any past command and confirm:

1. The hat identified in `hatId` really signed the canonical request bytes.
2. The object's linearity was respected (published once, patches append-only).
3. The result patch references the published object's id.
4. The handler recorded in the result is the same handler that was requested.

This is a read-only command. It runs from anywhere with access to the store.

---

## CRITICAL: READ THESE FILES FIRST

- `docs/prd/PHASE-38-VOICE-TO-EXECUTION.md` — epic
- `docs/prd/PHASE-38C-PROMPT.md` — the `host.exec` semantics you're verifying
- `packages/shell/src/parser.ts` — how to add a verb
- `packages/shell/src/commands/doc.ts` — reference for a read-only verb (routeDiff)
- `packages/shell/src/identity.ts` — signature verification entry point (look for `verifySig` or equivalent)
- `packages/loom/src/services/LoomStore.ts` — `getObject`, patch access

---

## ANTI-BULLSHIT RULES

1. **Read-only.** `host.audit` must not dispatch, mutate, or publish. Pure inspection.
2. **Verify cryptographically.** "The signature looks present" is not verification. Recompute the canonical digest, call `identity.verify(hatId, digest, hatSig)`, fail loudly if it doesn't match.
3. **Every claim is explicit.** Output a structured JSON report with a boolean for each invariant. No aggregate "looks good" verdict.
4. **Non-zero exit on failure.** If any invariant fails, the CLI exits 1. This makes it usable in CI.
5. **No network.** The CLI reads from the local store only. No Plexus calls, no remote fetches.

---

## PART 0: GIT HYGIENE

```bash
git checkout phase-38-voice-to-execution
git pull --ff-only
```

---

## Step 1: Add `host.audit` Verb (D38D.1)

### 1.1 Update `packages/shell/src/parser.ts`

Add `'host.audit'` to `KNOWN_VERBS`. No required capability (read-only). Positional arg: `<hostCommandId>`.

### 1.2 Commit

```bash
git commit -m "phase-38/D38D.1: add host.audit verb to parser"
```

---

## Step 2: Audit Router (D38D.2)

### 2.1 Create `packages/shell/src/commands/host-audit.ts`

```ts
export interface AuditReport {
  hostCommandId: string;
  handler: string;
  hatId: string;
  requestedAt: string;
  signatureValid: boolean;
  linearityValid: boolean;     // state is 'published', transitioned from 'draft' exactly once
  patchChainValid: boolean;    // patches are monotonic in timestamp, no rewrites of published fields
  resultAppended: boolean;     // at least one patch with kind === 'evidence_append'
  allInvariantsHold: boolean;  // AND of the above
  issues: string[];
}

export async function routeHostAudit(cmd: ShellCommand, ctx: ShellContext): Promise<AuditReport> {
  const id = cmd.args?.[0];
  if (!id) return errorReport(id, ['missing hostCommandId']);

  const obj = ctx.store.getObject(id);
  if (!obj) return errorReport(id, ['object not found']);
  if (obj.typeDefinition?.name !== 'HostCommand') return errorReport(id, ['not a HostCommand']);

  const issues: string[] = [];
  const handler = String(obj.payload.handler ?? '');
  const argsJson = String(obj.payload.args ?? '{}');
  const hatId = String(obj.payload.hatId ?? '');
  const requestedAt = String(obj.payload.requestedAt ?? '');
  const hatSig = String(obj.payload.hatSig ?? '');

  // Rebuild canonical payload exactly as host.exec signed it
  const canonical = `${handler}|${argsJson}|${hatId}|${requestedAt}`;
  const signatureValid = await ctx.identity.verify(hatId, canonical, hatSig);
  if (!signatureValid) issues.push('hatSig does not verify against canonical payload');

  const linearityValid = obj.visibility === 'published';
  if (!linearityValid) issues.push(`expected visibility=published, got ${obj.visibility}`);

  // Patch chain: timestamps monotonic; no patch rewrites a core signing field after publish
  const patches = obj.patches ?? [];
  let patchChainValid = true;
  for (let i = 1; i < patches.length; i++) {
    if (patches[i].timestamp < patches[i - 1].timestamp) {
      patchChainValid = false;
      issues.push(`patch ${i} timestamp regresses`);
    }
  }
  const sealedFields = new Set(['handler', 'args', 'hatId', 'hatCertId', 'hatSig', 'requestedAt']);
  for (const p of patches) {
    if (p.kind !== 'evidence_append' && sealedFields.has(String(p.delta?.field ?? ''))) {
      // Any mutation of sealed fields after first publish is a violation
      patchChainValid = false;
      issues.push(`patch ${p.id} mutates sealed field ${p.delta?.field}`);
    }
  }

  const resultAppended = patches.some(p => p.kind === 'evidence_append');
  if (!resultAppended) issues.push('no evidence_append patch found (no result recorded)');

  const allInvariantsHold = signatureValid && linearityValid && patchChainValid && resultAppended;

  return {
    hostCommandId: id,
    handler,
    hatId,
    requestedAt,
    signatureValid,
    linearityValid,
    patchChainValid,
    resultAppended,
    allInvariantsHold,
    issues,
  };
}
```

### 2.2 Update `packages/shell/src/router.ts`

```ts
if (cmd.verb === 'host.audit') return routeHostAudit(cmd, ctx);
```

### 2.3 Commit

```bash
git add packages/shell/src/commands/host-audit.ts packages/shell/src/router.ts packages/shell/src/parser.ts
git commit -m "phase-38/D38D.2: host.audit — cryptographic verification of HostCommand invariants"
```

---

## Step 3: Non-zero Exit on Failure (D38D.3)

### 3.1 Update `packages/shell/src/index.ts`

Where the top-level shell catches `host.audit` output: if `result.allInvariantsHold === false`, write the JSON to stdout and `process.exit(1)`. Otherwise exit 0.

Pattern: `repl.ts` and `index.ts` already distinguish success from error for existing verbs. Follow that.

### 3.2 Commit

```bash
git commit -m "phase-38/D38D.3: host.audit exits non-zero on invariant failure"
```

---

## Step 4: Gate Tests (D38D.4)

Add to `packages/__tests__/phase38-gate.test.ts`:

1. Audit a valid, signed, published `HostCommand` → `allInvariantsHold === true`, issues empty.
2. Audit with tampered `hatSig` (flip a byte) → `signatureValid: false`, `allInvariantsHold: false`.
3. Audit object still in draft → `linearityValid: false`.
4. Audit with a patch that rewrites `handler` post-publish → `patchChainValid: false`.
5. Audit with no result patch → `resultAppended: false`.
6. Audit non-existent id → structured error report, issues include "object not found".
7. CLI exit code: simulate running `host audit <bad-id>` → exit 1. Good id → exit 0.

Commit:

```bash
git commit -m "phase-38/D38D.4: gate tests for host.audit"
```

---

## Exit Criteria

- [ ] `host.audit <id>` returns a structured report with all four invariants.
- [ ] Signature verification is real (not a presence check).
- [ ] Non-zero exit on any invariant failure.
- [ ] All gates pass.

Hand off: done. 38D does not block 38G but 38G's acceptance test will call `host.audit` to verify itself.
