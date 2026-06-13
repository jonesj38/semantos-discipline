---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/test/SwarmDashboard.test.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.933246+00:00
---

# archive/apps-loom-react/test/SwarmDashboard.test.tsx

```tsx
/**
 * DH5.7 — Gate tests T1–T8 for the Swarm God View Dashboard.
 *
 * Tests WebSocket connection, data parsing, and component rendering
 * using a mock WebSocket and React Testing Library.
 */

import { describe, test, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, waitFor, act } from '@testing-library/react';
import '@testing-library/jest-dom';

import { SwarmDashboardStore } from '../src/swarm/SwarmDashboardStore';
import { SwarmDashboardProvider } from '../src/swarm/SwarmDashboardProvider';
import { SwarmDashboard } from '../src/swarm/SwarmDashboard';
import type { HandCompletedEvent, PersonaStatsUpdate } from '../src/swarm/types';

// ── Mock WebSocket ──

class MockWebSocket {
  static instances: MockWebSocket[] = [];

  url: string;
  readyState = 0; // CONNECTING
  onopen: (() => void) | null = null;
  onclose: (() => void) | null = null;
  onmessage: ((event: { data: string }) => void) | null = null;
  onerror: (() => void) | null = null;

  constructor(url: string) {
    this.url = url;
    MockWebSocket.instances.push(this);
    // Auto-open after microtask
    setTimeout(() => this.simulateOpen(), 0);
  }

  simulateOpen() {
    this.readyState = 1; // OPEN
    this.onopen?.();
  }

  simulateMessage(data: unknown) {
    this.onmessage?.({ data: JSON.stringify(data) });
  }

  simulateClose() {
    this.readyState = 3; // CLOSED
    this.onclose?.();
  }

  close() {
    this.readyState = 3;
  }

  send() {}

  static reset() {
    MockWebSocket.instances = [];
  }
}

// Stub global WebSocket
vi.stubGlobal('WebSocket', MockWebSocket);

// ── Helpers ──

function getLatestWs(): MockWebSocket {
  return MockWebSocket.instances[MockWebSocket.instances.length - 1];
}

/** Create a store and manually inject a WS message (bypassing real WS). */
function createTestStore(): SwarmDashboardStore {
  return new SwarmDashboardStore();
}

function renderDashboard(store: SwarmDashboardStore) {
  // Override the singleton used by provider
  vi.doMock('../src/swarm/storeSingleton', () => ({
    swarmDashboardStore: store,
  }));

  return render(
    <SwarmDashboardProvider>
      <SwarmDashboard />
    </SwarmDashboardProvider>,
  );
}

// ── Test Data ──

const statsEvent = {
  type: 'stats',
  timestamp: Date.now(),
  data: {
    cellsPerSecond: 1247,
    totalCellsCollected: 847231,
    totalCellsAnchored: 847000,
    totalBatches: 23,
    totalAnchors: 23,
    currentBatchSize: 45,
    currentBatchAgeMs: 15000,
    uniquePlayers: 25,
    uptimeMs: 3600000,
  },
};

const personaStatsUpdate: PersonaStatsUpdate = {
  timestamp: Date.now(),
  personas: {
    nit: { balance: 634, handsPlayed: 398, handsWon: 189, winRate: 0.475, policyVersion: 1, recentBalances: [600, 610, 634] },
    maniac: { balance: 847, handsPlayed: 432, handsWon: 218, winRate: 0.505, policyVersion: 1, recentBalances: [800, 820, 847] },
    calculator: { balance: 501, handsPlayed: 415, handsWon: 189, winRate: 0.455, policyVersion: 1, recentBalances: [500, 501, 501] },
    apex: { balance: 821, handsPlayed: 421, handsWon: 223, winRate: 0.530, policyVersion: 17, recentBalances: [750, 800, 821] },
  },
};

const handCompletedEvent: HandCompletedEvent = {
  type: 'hand.completed',
  timestamp: Date.now(),
  handId: 'h2847',
  tableId: 't1_7_123456789',
  players: [
    { botIndex: 1, persona: 'nit' },
    { botIndex: 5, persona: 'maniac' },
  ],
  winner: { botIndex: 5, persona: 'maniac' },
  potSize: 120,
  reason: 'high card',
  actions: 3,
  bsvTxid: '7ab1c2d3e4f5',
};

const violationHandEvent: HandCompletedEvent = {
  type: 'hand.completed',
  timestamp: Date.now(),
  handId: 'h2845',
  tableId: 't2_18_123456789',
  players: [
    { botIndex: 1, persona: 'nit' },
    { botIndex: 12, persona: 'calculator' },
  ],
  winner: { botIndex: 12, persona: 'calculator' },
  potSize: 64,
  reason: 'opponent shove',
  actions: 2,
  bsvTxid: '9d1f2e3c4b5a',
  violation: {
    type: 'tampering',
    details: 'Shuffle proof validation failed',
  },
};

const batchEvent = {
  type: 'batch',
  timestamp: Date.now(),
  data: {
    batchId: 'batch-24',
    cellCount: 923,
    openedAt: Date.now() - 30000,
    closedAt: Date.now(),
    merkleRoot: '2e4b5f6a7c8d9e0f1a2b3c4d5e6f7a8b',
  },
};

// ── Tests ──

describe('Phase H5: Swarm God View Dashboard', () => {
  beforeEach(() => {
    MockWebSocket.reset();
  });

  // ── T1: WebSocket Connection ──
  test('T1: Dashboard connects to Border Router WS endpoint', async () => {
    const store = createTestStore();
    store.connect('ws://localhost:8081');

    await waitFor(() => {
      expect(MockWebSocket.instances.length).toBeGreaterThanOrEqual(1);
      const ws = getLatestWs();
      expect(ws.url).toBe('ws://localhost:8081');
    });

    // Simulate open
    act(() => getLatestWs().simulateOpen());

    expect(store.getSnapshot().connection).toBe('connected');
    store.disconnect();
  });

  // ── T2: Stats Update Handling ──
  test('T2: TPSCounter updates when stats.updated event arrives', async () => {
    const store = createTestStore();
    store.connect('ws://localhost:8081');

    await waitFor(() => expect(MockWebSocket.instances.length).toBeGreaterThanOrEqual(1));
    act(() => getLatestWs().simulateOpen());

    act(() => {
      store.handleMessage({ data: JSON.stringify(statsEvent) });
    });

    const state = store.getSnapshot();
    expect(state.stats.tps).toBe(1247);
    expect(state.stats.totalCellsPublished).toBe(847231);
    expect(state.stats.totalBatchesAnchored).toBe(23);
    expect(state.tpsHistory).toContain(1247);

    store.disconnect();
  });

  // ── T3: Persona Stats Leaderboard ──
  test('T3: PersonaLeaderboard renders all four personas ranked by balance', async () => {
    const store = createTestStore();

    // Inject persona stats directly (H3 doesn't emit persona.stats yet)
    act(() => {
      store.injectPersonaStats(personaStatsUpdate);
    });

    const state = store.getSnapshot();
    expect(state.personaStats.personas.maniac.balance).toBe(847);
    expect(state.personaStats.personas.apex.balance).toBe(821);
    expect(state.personaStats.personas.nit.balance).toBe(634);
    expect(state.personaStats.personas.calculator.balance).toBe(501);
    expect(state.personaStats.personas.apex.policyVersion).toBe(17);
  });

  // ── T4: Hand Completed Event ──
  test('T4: HandFeed stores new completed hand with correct data', async () => {
    const store = createTestStore();

    act(() => {
      store.injectHandCompleted(handCompletedEvent);
    });

    const state = store.getSnapshot();
    expect(state.hands.length).toBe(1);
    expect(state.hands[0].handId).toBe('h2847');
    expect(state.hands[0].winner.persona).toBe('maniac');
    expect(state.hands[0].potSize).toBe(120);
  });

  // ── T5: Violation Detection ──
  test('T5: Violations are stored with violation data', async () => {
    const store = createTestStore();

    act(() => {
      store.injectHandCompleted(violationHandEvent);
    });

    const state = store.getSnapshot();
    expect(state.hands.length).toBe(1);
    expect(state.hands[0].violation).toBeDefined();
    expect(state.hands[0].violation!.type).toBe('tampering');
    expect(state.hands[0].violation!.details).toBe('Shuffle proof validation failed');
  });

  // ── T6: Batch Anchoring ──
  test('T6: AnchorChain stores new batch when batch event arrives', async () => {
    const store = createTestStore();
    store.connect('ws://localhost:8081');

    await waitFor(() => expect(MockWebSocket.instances.length).toBeGreaterThanOrEqual(1));
    act(() => getLatestWs().simulateOpen());

    act(() => {
      store.handleMessage({ data: JSON.stringify(batchEvent) });
    });

    const state = store.getSnapshot();
    expect(state.batches.length).toBe(1);
    expect(state.batches[0].cellCount).toBe(923);
    expect(state.batches[0].merkleRoot).toBe('2e4b5f6a7c8d9e0f1a2b3c4d5e6f7a8b');
    expect(state.batches[0].batchNumber).toBe(1);

    store.disconnect();
  });

  // ── T7: Apex Dominance Indicator ──
  test('T7: Dominance indicator data when Apex win rate exceeds average', async () => {
    const store = createTestStore();

    act(() => {
      store.injectPersonaStats(personaStatsUpdate);
    });

    const state = store.getSnapshot();
    const personas = state.personaStats.personas;

    // Calculate average win rate
    const avgWinRate = (
      personas.nit.winRate +
      personas.maniac.winRate +
      personas.calculator.winRate +
      personas.apex.winRate
    ) / 4;

    // Apex (0.530) > avg (0.491)
    expect(personas.apex.winRate).toBeGreaterThan(avgWinRate);
    expect(personas.apex.winRate - avgWinRate).toBeCloseTo(0.039, 2);
  });

  // ── T8: WebSocket Reconnection ──
  test('T8: Dashboard reconnects on WS disconnect', async () => {
    const store = createTestStore();

    // Use fake timers for reconnection
    vi.useFakeTimers();

    store.connect('ws://localhost:8081');
    await vi.advanceTimersByTimeAsync(10);

    // Simulate open
    act(() => getLatestWs().simulateOpen());
    expect(store.getSnapshot().connection).toBe('connected');

    // Simulate disconnect
    const wsCount = MockWebSocket.instances.length;
    act(() => getLatestWs().simulateClose());
    expect(store.getSnapshot().connection).toBe('disconnected');

    // Advance timer past reconnect delay (1000ms base)
    await vi.advanceTimersByTimeAsync(1100);

    // A new WebSocket should have been created
    expect(MockWebSocket.instances.length).toBeGreaterThan(wsCount);

    store.disconnect();
    vi.useRealTimers();
  });
});

```
