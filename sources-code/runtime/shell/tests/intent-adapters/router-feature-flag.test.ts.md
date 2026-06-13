---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/tests/intent-adapters/router-feature-flag.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.368769+00:00
---

# runtime/shell/tests/intent-adapters/router-feature-flag.test.ts

```ts
/**
 * Slice 3b — router INTENT_PIPELINE feature-flag branching.
 *
 * Proves the gating logic in runtime/shell/src/router.ts:
 *
 *   flag off, no wiring        → direct path (shouldUsePipelineRoute = false)
 *   flag on,  no wiring        → direct path (falls back safely)
 *   flag off, wiring present   → direct path (flag is the gate)
 *   flag on,  wiring present   → pipeline path (shouldUsePipelineRoute = true)
 *
 * End-to-end routeTransitionViaPipeline is also exercised with fake
 * ShellContext services + stub PipelineDeps, asserting it returns a
 * receipt-enriched shape carrying correlationId and a non-zero
 * resultSigLength.
 */

import { describe, expect, test, beforeEach, afterEach } from 'bun:test';
import {
  shouldUsePipelineRoute,
  routeTransitionViaPipeline,
} from '../../src/router';
import type { ShellContext } from '../../src/types';
import type { PipelineDeps } from '@semantos/intent';
import type { ShellCommand } from '../../src/parser';

// ── Env-flag fixture helpers ────────────────────────────────

let originalFlag: string | undefined;
beforeEach(() => {
  originalFlag = process.env.INTENT_PIPELINE;
});
afterEach(() => {
  if (originalFlag === undefined) delete process.env.INTENT_PIPELINE;
  else process.env.INTENT_PIPELINE = originalFlag;
});

// ── ShellContext builder ────────────────────────────────────

const stubDeps = (): PipelineDeps => ({
  emitBytes: () => new Uint8Array([0xc3, 0x05]),
  executeScript: async () => ({
    ok: true,
    stackDepth: 0,
    opcount: 2,
    gasUsed: 0,
  }),
  buildCellFromBytes: (bytes) => ({
    id: 'cell-router-test' as never,
    bytes,
  }),
  writeCell: async () => {},
  sign: () => new Uint8Array([0x30, 0x01, 0xaa]),
  now: () => 1_700_000_000_000,
  uuid: () => 'uuid-router',
});

// Partial ShellContext — only the fields shouldUsePipelineRoute and
// routeTransitionViaPipeline touch. Cast to `ShellContext` since the
// pipeline path doesn't exercise the other services.
const mkCtx = (wired: boolean): ShellContext => {
  const base = {
    identity: {
      getIdentity: () => ({
        id: 'id-router',
        activeHatId: 'hat-router',
        facets: [
          {
            id: 'hat-router',
            certId: 'cert-router',
            capabilities: [5],
          },
        ],
        certId: 'cert-router',
      }),
      getActiveHat: () => ({
        id: 'hat-router',
        certId: 'cert-router',
        capabilities: [5],
      }),
    },
  };
  const ctx = base as unknown as ShellContext;
  if (wired) {
    ctx.intentPipeline = {
      deps: stubDeps(),
      extension: { extensionId: 'router-test', domainFlag: 1 },
      generateId: () => 'intent-router-test',
    };
  }
  return ctx;
};

const mkCmd = (): ShellCommand => ({
  verb: 'transition',
  objectId: 'obj-router',
  flags: { visibility: 'published', capability: '5' },
  rawArgs: ['transition', 'obj-router', '--visibility', 'published', '--capability', '5'],
});

// ── Gating tests ────────────────────────────────────────────

describe('shouldUsePipelineRoute — env flag + wiring gate', () => {
  test('flag off, no wiring → false', () => {
    delete process.env.INTENT_PIPELINE;
    expect(shouldUsePipelineRoute(mkCtx(false))).toBe(false);
  });

  test('flag on, no wiring → false (requires wiring too)', () => {
    process.env.INTENT_PIPELINE = '1';
    expect(shouldUsePipelineRoute(mkCtx(false))).toBe(false);
  });

  test('flag off, wiring present → false (flag is the primary gate)', () => {
    delete process.env.INTENT_PIPELINE;
    expect(shouldUsePipelineRoute(mkCtx(true))).toBe(false);
  });

  test('flag on, wiring present → true', () => {
    process.env.INTENT_PIPELINE = '1';
    expect(shouldUsePipelineRoute(mkCtx(true))).toBe(true);
  });

  test('flag set to values other than "1" → false', () => {
    for (const v of ['0', 'true', 'yes', '']) {
      process.env.INTENT_PIPELINE = v;
      expect(shouldUsePipelineRoute(mkCtx(true))).toBe(false);
    }
  });
});

// ── routeTransitionViaPipeline behaviour ────────────────────

describe('routeTransitionViaPipeline — receipt-enriched result shape', () => {
  test('pipeline-routed result carries correlationId + signed receipt metadata', async () => {
    const out = (await routeTransitionViaPipeline(mkCmd(), mkCtx(true))) as {
      id: string;
      status: string;
      correlationId: string;
      ok: boolean;
      receipt: {
        signedBy: string;
        correlationId: string;
        resultSigLength: number;
        issuedAt: number;
        finishedAt: number;
      };
    };

    expect(out.id).toBe('obj-router');
    expect(out.ok).toBe(true);
    expect(out.status).toBe('transitioned');
    expect(out.correlationId).toBe('uuid-router');
    expect(out.receipt.signedBy).toBe('hat-router');
    expect(out.receipt.correlationId).toBe('uuid-router');
    expect(out.receipt.resultSigLength).toBeGreaterThan(0);
    expect(out.receipt.issuedAt).toBe(1_700_000_000_000);
    expect(out.receipt.finishedAt).toBe(1_700_000_000_000);
  });

  test('falls back with structured error when wiring is missing', async () => {
    const ctx = mkCtx(false);
    const out = (await routeTransitionViaPipeline(mkCmd(), ctx)) as {
      error: string;
      code: string;
    };
    expect(out.code).toBe('INTENT_PIPELINE_UNWIRED');
    expect(out.error).toContain('missing');
  });
});

```
