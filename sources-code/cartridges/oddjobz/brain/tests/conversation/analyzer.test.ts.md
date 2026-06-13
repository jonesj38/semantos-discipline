---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/conversation/analyzer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.488183+00:00
---

# cartridges/oddjobz/brain/tests/conversation/analyzer.test.ts

```ts
/**
 * D-O7 — periodic conversation analyzer tests.
 *
 * Acceptance:
 *  - confirmed phase escalates.
 *  - high decision-readiness escalates.
 *  - disengaged phase drops.
 *  - stale-after-N-minutes drops.
 *  - low scope + no contact drops.
 *  - everything else is keep_warm.
 */

import { describe, expect, test } from 'bun:test';
import {
  analyzeConversations,
  decideForSession,
  DEFAULT_ANALYZER_CONFIG,
  type ConversationSnapshot,
} from '../../src/conversation/analyzer.js';
import {
  emptyJobState,
  type AccumulatedJobState,
} from '../../src/conversation/accumulated-job-state.js';

const NOW = '2026-05-01T09:00:00Z';
const RECENT = '2026-05-01T08:30:00Z'; // 30min ago

const snap = (
  state: Partial<AccumulatedJobState>,
  lastTurnAt: string = RECENT,
): ConversationSnapshot => ({
  chatSessionId: 'sess-test',
  state: { ...emptyJobState(), ...state },
  lastTurnAt,
  nowIso: NOW,
});

describe('D-O7 — analyzer — escalate branches', () => {
  test('confirmed phase escalates to helm', () => {
    const d = decideForSession(snap({ conversationPhase: 'confirmed' }));
    expect(d.kind).toBe('escalate_to_helm');
  });

  test('high decision-readiness escalates to helm', () => {
    const d = decideForSession(
      snap({
        decisionReadiness:
          DEFAULT_ANALYZER_CONFIG.escalateAtDecisionReadiness,
      }),
    );
    expect(d.kind).toBe('escalate_to_helm');
  });
});

describe('D-O7 — analyzer — drop branches', () => {
  test('disengaged phase drops', () => {
    const d = decideForSession(snap({ conversationPhase: 'disengaged' }));
    expect(d.kind).toBe('drop');
  });

  test('stale session (older than dropStaleAfterMinutes) drops', () => {
    const oneWeekPlusAgo = '2026-04-23T08:00:00Z'; // 8+ days ago
    const d = decideForSession(snap({}, oneWeekPlusAgo));
    expect(d.kind).toBe('drop');
    if (d.kind === 'drop') {
      expect(d.reason).toMatch(/stale_after/);
    }
  });

  test('low scope + no contact drops', () => {
    const d = decideForSession(
      snap({
        scopeClarity: 5,
        customerName: null,
        customerPhone: null,
        customerEmail: null,
      }),
    );
    expect(d.kind).toBe('drop');
  });

  test('low scope WITH contact does NOT drop', () => {
    const d = decideForSession(
      snap({
        scopeClarity: 5,
        customerPhone: '0400123',
      }),
    );
    expect(d.kind).toBe('keep_warm');
  });
});

describe('D-O7 — analyzer — keep_warm fallback', () => {
  test('mid-progress conversation is kept warm', () => {
    const d = decideForSession(
      snap({
        scopeClarity: 50,
        decisionReadiness: 30,
        conversationPhase: 'providing_details',
      }),
    );
    expect(d.kind).toBe('keep_warm');
  });
});

describe('D-O7 — analyzer — analyzeConversations batch', () => {
  test('emits per-session decisions + correct summary counts', () => {
    const out = analyzeConversations([
      snap({ conversationPhase: 'confirmed' }),
      snap({ conversationPhase: 'disengaged' }),
      snap({ scopeClarity: 50, decisionReadiness: 30 }),
      snap({ scopeClarity: 5 }),
    ]);
    expect(out.totalCount).toBe(4);
    expect(out.summary.escalated).toBe(1);
    expect(out.summary.dropped).toBe(2);
    expect(out.summary.keptWarm).toBe(1);
    expect(out.perSession.length).toBe(4);
  });
});

```
