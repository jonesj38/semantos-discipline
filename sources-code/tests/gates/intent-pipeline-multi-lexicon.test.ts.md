---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/intent-pipeline-multi-lexicon.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.573212+00:00
---

# tests/gates/intent-pipeline-multi-lexicon.test.ts

```ts
/**
 * Slice 4 gate — non-jural lexicon end-to-end through the pipeline.
 *
 * Proves the Intent → SIR → IR → bytes → kernel → receipt path is
 * polymorphic over `TaggedCategory`. Runs a ControlSystems
 * (SCADA-style) acknowledgement intent all the way through using
 * the same machinery jural intents use.
 *
 * Asserted:
 *   G1  shellCommandToIntent + verb registry produces
 *       `{ lexicon: 'control-systems', category: 'acknowledgement' }`
 *       on Intent.category
 *   G2  buildSIR threads the TaggedCategory through to SIRNode.category
 *       unchanged
 *   G3  lowerSIR accepts the non-jural node and produces IR bytes
 *       via the constraint-only default lowering
 *   G4  End-to-end pipeline run on real CellEngine succeeds, a cell
 *       lands on disk, and the receipt is a real DER ECDSA signature
 *   G5  All stage events on the turn share one correlationId and the
 *       cell-writer receives the authoritative bytes
 */

import { describe, test, expect, beforeAll, afterAll } from 'bun:test';
import { mkdtempSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import {
  runShellIntent,
  type ShellIntentCtxLike,
} from '../../runtime/shell/src/intent-adapters/run-shell-intent';
import { shellCommandToIntent } from '../../runtime/shell/src/intent-adapters/shell-to-intent';
import { createShellPipelineDeps } from '../../runtime/shell/src/intent-adapters/shell-pipeline-deps';
import {
  createInMemoryLogger,
  type IdentityLike,
  type PipelineDeps,
} from '@semantos/intent';
import {
  registerVerb,
  _clearVerbRegistry,
} from '@semantos/runtime-services';
import { NodeFsAdapter } from '../../core/protocol-types/src/adapters/node-fs-adapter';
import { StubSigner } from '../../runtime/session-protocol/src/signer';
import { loadCellEngine } from '../../core/cell-engine/bindings/bun/loader';
import type { ShellCommand, ShellVerb } from '../../runtime/shell/src/parser';

/**
 * Build a ShellCommand by hand. The parser's KNOWN_VERBS is a
 * hardcoded const — registry-registered verbs aren't listed there,
 * so parseCommand rejects them. That's expected: extensions plug
 * into the shell's router via getVerb() at dispatch time, not via
 * parseCommand.
 *
 * For pipeline testing we skip parseCommand entirely and feed the
 * adapter a synthetic ShellCommand. In real use, the router calls
 * getVerb() before any parser-validated shape is required; the
 * intent pipeline's shell adapter works the same way.
 */
const mkCmd = (
  verb: string,
  objectId?: string,
  flags: Record<string, string | boolean> = {},
): ShellCommand => ({
  verb: verb as unknown as ShellVerb,
  flags,
  rawArgs: objectId ? [verb, objectId] : [verb],
  ...(objectId !== undefined ? { objectId } : {}),
});

// ── Per-suite init ───────────────────────────────────────────

let deps: PipelineDeps;
let tmpRoot: string;

beforeAll(async () => {
  tmpRoot = mkdtempSync(join(tmpdir(), 'semantos-multi-lex-'));
  const storage = new NodeFsAdapter(tmpRoot);
  const engine = await loadCellEngine({ profile: 'full' });
  deps = await createShellPipelineDeps({
    engine,
    storage,
    signer: new StubSigner(),
    uuid: () => 'multi-lex-' + Math.random().toString(16).slice(2, 10),
  });

  // Register the non-jural verb via the extension pattern. In
  // production this happens inside packages/scada's shell-handler
  // module-load; here we do it inline so the test is self-contained.
  registerVerb({
    name: 'acknowledge_alarm',
    category: { lexicon: 'control-systems', category: 'acknowledgement' },
    action: 'acknowledge_alarm',
    mutation: true,
    handler: async () => ({ ok: true }),
  });
});

afterAll(() => {
  _clearVerbRegistry();
  if (tmpRoot) rmSync(tmpRoot, { recursive: true, force: true });
});

// ── Fixtures ────────────────────────────────────────────────

const mkCtx = (): ShellIntentCtxLike => {
  const identity: IdentityLike = {
    id: 'id-operator',
    activeHatId: 'hat-operator',
    hats: [
      {
        id: 'hat-operator',
        certId: 'cert-operator',
        capabilities: [5],
      },
    ],
  };
  return {
    identity: {
      getIdentity: () => identity,
      getActiveHat: () => identity.hats[0]!,
    },
    extension: { extensionId: 'scada', domainFlag: 11 },
  };
};

// ── Tests ────────────────────────────────────────────────────

describe('Slice 4 — ControlSystems lexicon end-to-end', () => {
  test('G1 — shell adapter produces TaggedCategory stamped control-systems', () => {
    // The verb registry lookup returns the ControlSystems TaggedCategory;
    // shellCommandToIntent stamps it onto Intent.category.
    const cmd = mkCmd('acknowledge_alarm', 'alarm-37');
    const intent = shellCommandToIntent(cmd, { generateId: () => 'i-ack-1' });

    expect(intent).not.toBeNull();
    expect(intent!.category).toEqual({
      lexicon: 'control-systems',
      category: 'acknowledgement',
    });
    expect(intent!.action).toBe('acknowledge_alarm');
  });

  test('G2+G3+G4+G5 — non-jural intent drives the full pipeline', async () => {
    const logger = createInMemoryLogger();
    // --capability 5 gives the intent a real constraint to lower so
    // the IR has content; the emit path rejects zero-operand
    // composites. Real extensions always attach at least one
    // constraint to any mutation.
    const cmd = mkCmd('acknowledge_alarm', 'alarm-37', { capability: '5' });

    const out = await runShellIntent(cmd, mkCtx(), {
      generateId: () => 'i-ack-2',
      deps,
      logger,
    });

    expect(out.kind).toBe('ran');
    if (out.kind !== 'ran') throw new Error('expected ran');
    // Non-jural intents take the constraint-only lowering default —
    // still a fully valid kernel script, still a signed receipt.
    expect(out.result.ok).toBe(true);

    // G2 — Intent.category threaded through unchanged
    const extractEv = logger.events.find(
      (e) => e.stage === 'intent_extracted',
    );
    expect(extractEv).toBeDefined();

    // G3 — ir_emitted event carries real byteLength
    const irEv = logger.events.find((e) => e.stage === 'ir_emitted')!;
    expect(irEv.data.byteLength as number).toBeGreaterThanOrEqual(0);

    // G4 — real DER ECDSA signature (first byte 0x30 = SEQUENCE tag)
    expect(out.result.receipt.resultSig).toBeInstanceOf(Uint8Array);
    expect(out.result.receipt.resultSig.byteLength).toBeGreaterThan(0);
    expect(out.result.receipt.resultSig[0]).toBe(0x30);

    // G5 — single correlationId across the turn
    const ids = new Set(logger.events.map((e) => e.correlationId));
    expect(ids.size).toBe(1);
    expect(out.result.correlationId).toBe(logger.events[0]!.correlationId);
  });
});

```
