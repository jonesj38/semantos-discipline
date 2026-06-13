---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/confidence-threshold.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.539380+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/confidence-threshold.test.ts

```ts
/**
 * D-OJ-conv-confidence-threshold — Confidence-gated outbound state tests.
 *
 * Tests:
 *   CT1  — replyConfidence: 0.90, ratificationThreshold: 0.85 → outboundState: 'approved'
 *   CT2  — replyConfidence: 0.70, ratificationThreshold: 0.85 → outboundState: 'proposed'
 *   CT3  — replyConfidence: undefined, ratificationThreshold: 0.85 → outboundState: 'proposed'
 *   CT4  — ratificationThreshold absent from args → uses default (0.85), replyConfidence: 0.90 → 'approved'
 *   CT5  — exact threshold (replyConfidence: 0.85, ratificationThreshold: 0.85) → 'approved' (≥, not >)
 *   CT6  — operator role (outboundParticipantRole: 'operator'), high confidence → outboundState: 'drafted'
 *   CT7  — loadRatificationConfig reads ratificationThreshold from a temp JSON file correctly
 *   CT8  — loadRatificationConfig with missing field → returns DEFAULT_RATIFICATION_THRESHOLD (0.85)
 *   CT9  — loadRatificationConfig with invalid value (string) → returns DEFAULT_RATIFICATION_THRESHOLD
 *   CT10 — meetsRatificationThreshold(0.86, 0.85) → true; (0.84, 0.85) → false; (undefined, 0.85) → false
 */

import {
  describe,
  expect,
  test,
} from 'bun:test';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInMemoryLogger } from '@semantos/intent';
import {
  recordIntakeTurn,
  makeJsonlConversationSink,
  type OddjobzConversationTurnPayload,
} from '../conversation-turn-patch.js';
import {
  loadRatificationConfig,
  meetsRatificationThreshold,
  DEFAULT_RATIFICATION_THRESHOLD,
} from '../ratification-config.js';

// ────────────────────────────────────────────────────────────
// Test deps factory
// ────────────────────────────────────────────────────────────

let _idCounter = 0;

function makeDeps(
  sinks: Partial<{
    semObjectSink: (turn: OddjobzConversationTurnPayload) => Promise<void> | void;
  }> = {},
  opts: { tmpDir?: string } = {},
) {
  const tmpDir = opts.tmpDir ?? mkdtempSync(join(tmpdir(), 'oj-ct-test-'));
  return {
    write: makeJsonlConversationSink(join(tmpDir, 'conversation.jsonl')) as never,
    logger: createInMemoryLogger(),
    generatePatchId: () => `patch-${++_idCounter}`,
    generateCorrelationId: () => `corr-${_idCounter}`,
    now: () => 1_700_000_000_000,
    ...sinks,
  };
}

const baseArgs = {
  objectId: 'conv-ct-test',
  hatId: 'hat-op',
  message: 'Can you quote a fence?',
  reply: 'Happy to help — what length?',
  action: { type: 'gather_info' },
  model: 'claude-haiku-4-5',
  assembledPrompt: 'BASE_SYSTEM v1\n\nOddjobz intake prompt',
  surface: 'widget' as const,
};

// Helper: capture all turns emitted by recordIntakeTurn.
async function captureTurns(
  args: typeof baseArgs & Record<string, unknown>,
): Promise<OddjobzConversationTurnPayload[]> {
  const captured: OddjobzConversationTurnPayload[] = [];
  const deps = makeDeps({
    semObjectSink: async (turn) => { captured.push(turn); },
  });
  await recordIntakeTurn(args, deps);
  return captured;
}

// ────────────────────────────────────────────────────────────
// CT1 — high confidence meets threshold → 'approved'
// ────────────────────────────────────────────────────────────

describe('CT1 — replyConfidence 0.90 >= threshold 0.85 → approved', () => {
  test('outbound AI turn has outboundState: approved', async () => {
    const turns = await captureTurns({
      ...baseArgs,
      replyConfidence: 0.90,
      ratificationThreshold: 0.85,
    });
    const outbound = turns.find((t) => t.direction === 'outbound');
    expect(outbound).toBeDefined();
    expect(outbound?.outboundState).toBe('approved');
  });
});

// ────────────────────────────────────────────────────────────
// CT2 — low confidence below threshold → 'proposed'
// ────────────────────────────────────────────────────────────

describe('CT2 — replyConfidence 0.70 < threshold 0.85 → proposed', () => {
  test('outbound AI turn has outboundState: proposed', async () => {
    const turns = await captureTurns({
      ...baseArgs,
      replyConfidence: 0.70,
      ratificationThreshold: 0.85,
    });
    const outbound = turns.find((t) => t.direction === 'outbound');
    expect(outbound).toBeDefined();
    expect(outbound?.outboundState).toBe('proposed');
  });
});

// ────────────────────────────────────────────────────────────
// CT3 — undefined confidence → 'proposed'
// ────────────────────────────────────────────────────────────

describe('CT3 — replyConfidence undefined → proposed', () => {
  test('outbound AI turn has outboundState: proposed when confidence absent', async () => {
    const turns = await captureTurns({
      ...baseArgs,
      replyConfidence: undefined,
      ratificationThreshold: 0.85,
    });
    const outbound = turns.find((t) => t.direction === 'outbound');
    expect(outbound).toBeDefined();
    expect(outbound?.outboundState).toBe('proposed');
  });
});

// ────────────────────────────────────────────────────────────
// CT4 — no ratificationThreshold in args → uses default 0.85
// ────────────────────────────────────────────────────────────

describe('CT4 — ratificationThreshold absent → uses DEFAULT_RATIFICATION_THRESHOLD (0.85)', () => {
  test('high confidence (0.90) with no threshold arg → approved (default 0.85)', async () => {
    // No ratificationThreshold key in args → buildCanonicalTurns uses DEFAULT
    const turns = await captureTurns({
      ...baseArgs,
      replyConfidence: 0.90,
      // ratificationThreshold intentionally absent
    });
    const outbound = turns.find((t) => t.direction === 'outbound');
    expect(outbound).toBeDefined();
    expect(outbound?.outboundState).toBe('approved');
  });
});

// ────────────────────────────────────────────────────────────
// CT5 — exact threshold edge case: ≥ not >
// ────────────────────────────────────────────────────────────

describe('CT5 — exact threshold (0.85 >= 0.85) → approved', () => {
  test('replyConfidence exactly equal to threshold → approved (≥, not >)', async () => {
    const turns = await captureTurns({
      ...baseArgs,
      replyConfidence: 0.85,
      ratificationThreshold: 0.85,
    });
    const outbound = turns.find((t) => t.direction === 'outbound');
    expect(outbound).toBeDefined();
    expect(outbound?.outboundState).toBe('approved');
  });
});

// ────────────────────────────────────────────────────────────
// CT6 — operator role ignores confidence → 'drafted'
// ────────────────────────────────────────────────────────────

describe('CT6 — operator role with high confidence → drafted (not approved)', () => {
  test('operator outbound turn always gets drafted, regardless of confidence', async () => {
    const turns = await captureTurns({
      ...baseArgs,
      outboundParticipantRole: 'operator',
      replyConfidence: 0.99,
      ratificationThreshold: 0.85,
    });
    const outbound = turns.find((t) => t.direction === 'outbound');
    expect(outbound).toBeDefined();
    expect(outbound?.outboundState).toBe('drafted');
  });
});

// ────────────────────────────────────────────────────────────
// CT7 — loadRatificationConfig reads from file
// ────────────────────────────────────────────────────────────

describe('CT7 — loadRatificationConfig reads ratificationThreshold from file', () => {
  test('reads the field correctly', () => {
    const tmpDir = mkdtempSync(join(tmpdir(), 'oj-ct7-'));
    const jsonPath = join(tmpDir, 'cartridge.json');
    writeFileSync(jsonPath, JSON.stringify({ ratificationThreshold: 0.92 }), 'utf8');
    const config = loadRatificationConfig(jsonPath);
    expect(config.ratificationThreshold).toBe(0.92);
  });
});

// ────────────────────────────────────────────────────────────
// CT8 — missing field → default
// ────────────────────────────────────────────────────────────

describe('CT8 — loadRatificationConfig with missing field → DEFAULT', () => {
  test('returns DEFAULT_RATIFICATION_THRESHOLD when field absent', () => {
    const tmpDir = mkdtempSync(join(tmpdir(), 'oj-ct8-'));
    const jsonPath = join(tmpDir, 'cartridge.json');
    writeFileSync(jsonPath, JSON.stringify({ id: 'oddjobz', name: 'Oddjobz' }), 'utf8');
    const config = loadRatificationConfig(jsonPath);
    expect(config.ratificationThreshold).toBe(DEFAULT_RATIFICATION_THRESHOLD);
  });

  test('returns DEFAULT_RATIFICATION_THRESHOLD when file not found', () => {
    const config = loadRatificationConfig('/nonexistent/path/cartridge.json');
    expect(config.ratificationThreshold).toBe(DEFAULT_RATIFICATION_THRESHOLD);
  });
});

// ────────────────────────────────────────────────────────────
// CT9 — invalid value (string) → default
// ────────────────────────────────────────────────────────────

describe('CT9 — loadRatificationConfig with invalid value → DEFAULT', () => {
  test('string value for ratificationThreshold → DEFAULT_RATIFICATION_THRESHOLD', () => {
    const tmpDir = mkdtempSync(join(tmpdir(), 'oj-ct9-'));
    const jsonPath = join(tmpDir, 'cartridge.json');
    writeFileSync(
      jsonPath,
      JSON.stringify({ ratificationThreshold: 'high' }),
      'utf8',
    );
    const config = loadRatificationConfig(jsonPath);
    expect(config.ratificationThreshold).toBe(DEFAULT_RATIFICATION_THRESHOLD);
  });

  test('null value for ratificationThreshold → DEFAULT_RATIFICATION_THRESHOLD', () => {
    const tmpDir = mkdtempSync(join(tmpdir(), 'oj-ct9b-'));
    const jsonPath = join(tmpDir, 'cartridge.json');
    writeFileSync(
      jsonPath,
      JSON.stringify({ ratificationThreshold: null }),
      'utf8',
    );
    const config = loadRatificationConfig(jsonPath);
    expect(config.ratificationThreshold).toBe(DEFAULT_RATIFICATION_THRESHOLD);
  });

  test('out-of-range value (2.0) for ratificationThreshold → DEFAULT_RATIFICATION_THRESHOLD', () => {
    const tmpDir = mkdtempSync(join(tmpdir(), 'oj-ct9c-'));
    const jsonPath = join(tmpDir, 'cartridge.json');
    writeFileSync(
      jsonPath,
      JSON.stringify({ ratificationThreshold: 2.0 }),
      'utf8',
    );
    const config = loadRatificationConfig(jsonPath);
    expect(config.ratificationThreshold).toBe(DEFAULT_RATIFICATION_THRESHOLD);
  });
});

// ────────────────────────────────────────────────────────────
// CT10 — meetsRatificationThreshold pure function tests
// ────────────────────────────────────────────────────────────

describe('CT10 — meetsRatificationThreshold pure function', () => {
  test('0.86 >= 0.85 → true', () => {
    expect(meetsRatificationThreshold(0.86, 0.85)).toBe(true);
  });

  test('0.84 >= 0.85 → false', () => {
    expect(meetsRatificationThreshold(0.84, 0.85)).toBe(false);
  });

  test('undefined → false (regardless of threshold)', () => {
    expect(meetsRatificationThreshold(undefined, 0.85)).toBe(false);
  });

  test('exactly at threshold (0.85 >= 0.85) → true', () => {
    expect(meetsRatificationThreshold(0.85, 0.85)).toBe(true);
  });

  test('0.0 >= 0.85 → false', () => {
    expect(meetsRatificationThreshold(0.0, 0.85)).toBe(false);
  });

  test('1.0 >= 0.85 → true', () => {
    expect(meetsRatificationThreshold(1.0, 0.85)).toBe(true);
  });
});

```
