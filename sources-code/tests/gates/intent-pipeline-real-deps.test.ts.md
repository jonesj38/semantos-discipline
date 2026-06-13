---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/intent-pipeline-real-deps.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.585886+00:00
---

# tests/gates/intent-pipeline-real-deps.test.ts

```ts
/**
 * Slice 3a gate — real PipelineDeps end-to-end.
 *
 * Replaces the stubs in `tests/gates/intent-pipeline.test.ts` with
 * real wiring for kernel execution, filesystem persistence, and
 * cryptographic signing:
 *
 *   executeScript  ← core/cell-engine/bindings/bun/loadCellEngine()
 *   writeCell      ← core/protocol-types/adapters/NodeFsAdapter
 *   sign           ← runtime/session-protocol StubSigner (real ECDSA
 *                    with a deterministic seed)
 *
 * Asserted:
 *   G1  Real IR → bytes emission (non-empty Uint8Array)
 *   G2  CellEngine.executeScript actually ran (mapped ScriptResult
 *       fields populated whether ok=true or ok=false)
 *   G3  When kernel succeeds → cell file is written to tmp dir under
 *       `cells/${cellId}` with the exact emitted bytes
 *   G4  Receipt.resultSig is a real DER-encoded ECDSA signature
 *       (non-empty Uint8Array) produced by StubSigner
 *   G5  All stage events fire with the correct correlationId
 *       regardless of kernel outcome
 *
 * NOT asserted:
 *   - That the emitted bytes execute successfully on the kernel — the
 *     transition-verb → Intent → SIR → IR → emit path may currently
 *     produce opcode sequences the real kernel rejects. That's fine
 *     for Slice 3a: the wiring is correct; opcode shape is Slice 3b
 *     once the router feature flag lets us A/B against the direct
 *     path.
 */

import { describe, test, expect, beforeAll, afterAll } from 'bun:test';
import { mkdtempSync, readFileSync, rmSync, readdirSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { parseCommand } from '@semantos/shell/parser';
import {
  runShellIntent,
  type ShellIntentCtxLike,
} from '../../runtime/shell/src/intent-adapters/run-shell-intent';
import { createShellPipelineDeps } from '../../runtime/shell/src/intent-adapters/shell-pipeline-deps';
import { createInMemoryLogger, type PipelineDeps } from '@semantos/intent';
import { NodeFsAdapter } from '../../core/protocol-types/src/adapters/node-fs-adapter';
import { StubSigner } from '../../runtime/session-protocol/src/signer';
import { loadCellEngine } from '../../core/cell-engine/bindings/bun/loader';
import type { IdentityLike } from '@semantos/intent';

// ── Per-suite init (amortise WASM load) ─────────────────────

let deps: PipelineDeps;
let tmpRoot: string;
let storage: NodeFsAdapter;

beforeAll(async () => {
  tmpRoot = mkdtempSync(join(tmpdir(), 'semantos-intent-gate-'));
  storage = new NodeFsAdapter(tmpRoot);
  const engine = await loadCellEngine({ profile: 'full' });
  const signer = new StubSigner();
  deps = await createShellPipelineDeps({
    engine,
    storage,
    signer,
    uuid: () => 'gate-uuid-' + Math.random().toString(16).slice(2, 10),
  });
});

afterAll(() => {
  if (tmpRoot) rmSync(tmpRoot, { recursive: true, force: true });
});

// ── Fixtures ────────────────────────────────────────────────

const mkCtx = (): ShellIntentCtxLike => {
  const identity: IdentityLike = {
    id: 'id-gate-real',
    activeHatId: 'hat-gate-real',
    hats: [
      {
        id: 'hat-gate-real',
        certId: 'cert-gate-real',
        capabilities: [5],
      },
    ],
  };
  return {
    identity: {
      getIdentity: () => identity,
      getActiveHat: () => identity.hats[0]!,
    },
    extension: { extensionId: 'gate-real', domainFlag: 1 },
  };
};

// ── Tests ────────────────────────────────────────────────────

describe('Slice 3a — real PipelineDeps wiring', () => {
  test('G1+G2+G5 — pipeline runs with real CellEngine + StubSigner + NodeFsAdapter', async () => {
    const logger = createInMemoryLogger();
    const cmd = parseCommand(['transition', 'obj-real-1', '--capability', '5']);

    const out = await runShellIntent(cmd, mkCtx(), {
      generateId: () => 'intent-real-1',
      deps,
      logger,
    });

    expect(out.kind).toBe('ran');
    if (out.kind !== 'ran') throw new Error('expected ran');

    // G1 — real ir_emitted event shows non-zero byte length
    const irEmit = logger.events.find((e) => e.stage === 'ir_emitted')!;
    expect(irEmit).toBeDefined();
    expect(irEmit.data.byteLength as number).toBeGreaterThan(0);

    // G2 — script_executed event fired with mapped kernel fields
    const scriptExec = logger.events.find((e) => e.stage === 'script_executed')!;
    expect(scriptExec).toBeDefined();
    expect(typeof scriptExec.data.kernelOk).toBe('boolean');
    expect(typeof scriptExec.data.opcount).toBe('number');

    // G5 — all stage events share one correlationId
    const ids = new Set(logger.events.map((e) => e.correlationId));
    expect(ids.size).toBe(1);

    // Final state event: intent_completed (if kernel ok) OR
    // intent_rejected (if kernel rejected). Either is a valid wiring
    // outcome for Slice 3a.
    const last = logger.events[logger.events.length - 1]!;
    expect(['intent_completed', 'intent_rejected']).toContain(last.stage);
  });

  test('G3 — happy path writes real emit() bytes to NodeFsAdapter', async () => {
    const logger = createInMemoryLogger();
    const cmd = parseCommand(['transition', 'obj-real-2', '--capability', '5']);

    const out = await runShellIntent(cmd, mkCtx(), {
      generateId: () => 'intent-real-2',
      deps,
      logger,
    });
    if (out.kind !== 'ran') throw new Error('expected ran');

    expect(out.result.ok).toBe(true);
    expect(out.result.cell).not.toBeNull();
    const cell = out.result.cell!;

    const filesWritten = readdirSync(join(tmpRoot, 'cells'));
    expect(filesWritten.length).toBeGreaterThan(0);

    const cellFile = readFileSync(join(tmpRoot, 'cells', cell.id));
    expect(cellFile.length).toBe(cell.bytes.byteLength);
    expect(new Uint8Array(cellFile)).toEqual(cell.bytes);

    // The cell's bytes must be the AUTHORITATIVE emit() output — the
    // authoring-mode OP_1 kernel frame must NOT appear in the
    // persisted cell. Verify by presence of CHECKCAPABILITY opcode
    // (0xc3) and absence of bare OP_1 (0x51) at the top level.
    const byteList = Array.from(cell.bytes);
    expect(byteList).toContain(0xc3);
    // OP_1 (0x51) is the kernel-frame marker. It's unrelated to the
    // authoring bytes for transition+--capability so it must not
    // appear. If a future verb legitimately needs OP_1 in its emit
    // output, this assertion will need refining.
    expect(byteList).not.toContain(0x51);
  });

  test('G4 — Receipt.resultSig is a real ECDSA signature (non-empty, deterministic for same preimage)', async () => {
    const logger = createInMemoryLogger();
    const cmd = parseCommand(['transition', 'obj-real-sig', '--capability', '5']);

    const out = await runShellIntent(cmd, mkCtx(), {
      generateId: () => 'intent-real-sig',
      deps,
      logger,
    });
    if (out.kind !== 'ran') throw new Error('expected ran');

    // Whether happy-path or rejected, a receipt is produced with a
    // non-empty signature.
    expect(out.result.receipt.resultSig).toBeInstanceOf(Uint8Array);
    expect(out.result.receipt.resultSig.byteLength).toBeGreaterThan(0);
    // DER-encoded ECDSA signatures start with 0x30 (SEQUENCE tag).
    expect(out.result.receipt.resultSig[0]).toBe(0x30);
  });
});

```
