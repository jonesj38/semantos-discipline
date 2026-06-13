---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/__tests__/two-runner-e2e.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.810436+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/__tests__/two-runner-e2e.test.ts

```ts
/**
 * Two-runner E2E with an in-memory test-double transport.
 *
 * Per the prompt-20 test plan: "Two runners with a test-double
 * transport complete a full hand; assert final state + audit log
 * match recorded fixture."
 *
 * Scoped tighter than a full hand: we don't spin up real Claude
 * agents or a real PokerStateMachine here (those need wallet + ARC).
 * Instead we exercise the *transport-driven coordination* primitives
 * the runner depends on — message-queue handoff between two seats,
 * deterministic deal agreement, and audit-log shape.
 *
 * The full P2P play-by-play is covered indirectly by the legacy
 * arena scripts; this file pins the test surface the prompt-20
 * split was meant to make possible.
 */

import { afterEach, describe, expect, test } from 'bun:test';
import {
  enqueueMove,
  resetMessageQueueAtoms,
  waitForMove,
} from '../message-queue';
import {
  awaitMyTurn,
  flipTurn,
  resetTurnAtoms,
  setTurn,
} from '../turn-coordinator';
import { dealForP2P } from '../hand-shuffle';
import {
  transportPort,
  type Transport,
  type PokerControlMessage,
  type PokerMoveMessage,
} from '../transport-port';
import { renderAuditLog } from '../audit-log-renderer';

afterEach(() => {
  resetMessageQueueAtoms();
  resetTurnAtoms();
  transportPort.unbind();
});

// ── In-memory two-seat transport pair ────────────────────────────

interface Pair {
  seat0: Transport;
  seat1: Transport;
}

function makePair(gameId: string): Pair {
  let s0OnMove: ((m: PokerMoveMessage) => Promise<void> | void) | null = null;
  let s1OnMove: ((m: PokerMoveMessage) => Promise<void> | void) | null = null;
  let s0OnCtrl: ((m: PokerControlMessage) => Promise<void> | void) | null = null;
  let s1OnCtrl: ((m: PokerControlMessage) => Promise<void> | void) | null = null;

  const seat0: Transport = {
    init: async () => {},
    sendMove: async (m) => {
      // seat 0 sends → seat 1's onMove (or queue)
      if (s1OnMove) await s1OnMove(m);
      else enqueueMove(gameId, m);
    },
    sendControl: async (type, payload) => {
      if (s1OnCtrl) await s1OnCtrl({ type, payload } as PokerControlMessage);
    },
    startListening: async (om, oc) => {
      s0OnMove = om;
      s0OnCtrl = oc;
    },
    stopListening: async () => {
      s0OnMove = null;
      s0OnCtrl = null;
    },
    drainPending: async () => {},
  };
  const seat1: Transport = {
    init: async () => {},
    sendMove: async (m) => {
      if (s0OnMove) await s0OnMove(m);
      else enqueueMove(gameId, m);
    },
    sendControl: async (type, payload) => {
      if (s0OnCtrl) await s0OnCtrl({ type, payload } as PokerControlMessage);
    },
    startListening: async (om, oc) => {
      s1OnMove = om;
      s1OnCtrl = oc;
    },
    stopListening: async () => {
      s1OnMove = null;
      s1OnCtrl = null;
    },
    drainPending: async () => {},
  };
  return { seat0, seat1 };
}

const moveOf = (action: string, txid = 'tx'): PokerMoveMessage => ({
  handNumber: 1,
  phase: 'preflop',
  action,
  beef: [],
  txid,
  vout: 0,
  lockingScript: '',
  cellVersion: 1,
});

describe('two-runner E2E primitives', () => {
  test('1. seat 0 sends a move, seat 1 receives it via onMove handler', async () => {
    const pair = makePair('g1');
    const captured: PokerMoveMessage[] = [];
    await pair.seat1.startListening(
      async (m) => {
        captured.push(m);
      },
      async () => {},
    );
    await pair.seat0.sendMove(moveOf('call'));
    expect(captured).toHaveLength(1);
    expect(captured[0].action).toBe('call');
  });

  test('2. moves sent before listener arrives are buffered in the queue', async () => {
    const pair = makePair('g1');
    await pair.seat0.sendMove(moveOf('raise', 'tx-r'));
    // No listener yet → queued via the test-double's fallback.
    const got = await waitForMove('g1');
    expect(got.txid).toBe('tx-r');
    void pair;
  });

  test('3. control messages route to onControl', async () => {
    const pair = makePair('g1');
    let seen: PokerControlMessage | null = null;
    await pair.seat1.startListening(
      async () => {},
      async (m) => {
        seen = m;
      },
    );
    await pair.seat0.sendControl('handshake', { name: 'A' });
    expect(seen!.type).toBe('handshake');
    expect((seen as unknown as PokerControlMessage).payload.name).toBe('A');
  });

  test('4. both seats agree on the deck for the same gameId+hand', () => {
    const a = dealForP2P('two-runner-e2e', 1);
    const b = dealForP2P('two-runner-e2e', 1);
    expect(a.deck.map((c) => c.label)).toEqual(b.deck.map((c) => c.label));
    expect(a.seat0Cards).toEqual(b.seat0Cards);
    expect(a.seat1Cards).toEqual(b.seat1Cards);
  });

  test('5. turn coordination — seat 0 acts, awaits its turn again after flip', async () => {
    setTurn('g1', 'mine');
    flipTurn('g1');
    let resolved = false;
    const promise = awaitMyTurn('g1').then(() => {
      resolved = true;
    });
    expect(resolved).toBe(false);
    flipTurn('g1');
    await promise;
    expect(resolved).toBe(true);
  });

  test('6. audit-log render produces a stable shape from a fixture', () => {
    const out = renderAuditLog(
      'Alice',
      [{ handNumber: 1, winner: 'Alice', potSize: 30, txids: ['t1'], stateChain: ['t1'] }],
      [
        { txid: 't1', type: 'CellToken', hand: 1, detail: 'birth' },
        { txid: 't2', type: 'OP_RETURN', hand: 1, detail: 'A call' },
      ],
      { ansi: false },
    );
    expect(out).toContain('Hand #1');
    expect(out).toContain('Total: 2 transactions');
    expect(out).toContain('CellToken] t1');
    expect(out).toContain('OP_RETURN] t2');
  });
});

```
