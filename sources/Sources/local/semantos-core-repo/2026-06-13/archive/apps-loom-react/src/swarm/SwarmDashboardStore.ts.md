---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/swarm/SwarmDashboardStore.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.959435+00:00
---

# archive/apps-loom-react/src/swarm/SwarmDashboardStore.ts

```ts
/**
 * SwarmDashboardStore — renderer-agnostic state for the Swarm God View.
 *
 * Manages WebSocket connection to the H3 Border Router, adapts incoming
 * events via h3EventAdapter, and maintains the SwarmDashboardState.
 * React's SwarmDashboardProvider wraps this via useSyncExternalStore.
 */

import { TypedEventEmitter } from '../services/TypedEventEmitter';
import {
  adaptCellEvent,
  adaptStatsEvent,
  adaptBatchEvent,
  adaptAnchorEvent,
} from './h3EventAdapter';
import {
  createInitialState,
  type SwarmDashboardState,
  type H3WsMessage,
  type HandCompletedEvent,
  type BatchAnchoredEvent,
  type NodeData,
  type PersonaStatsUpdate,
} from './types';

type StoreEvents = {
  change: [SwarmDashboardState];
};

const MAX_HANDS = 100;
const MAX_BATCHES = 10;
const MAX_TPS_HISTORY = 60;
const RECONNECT_BASE_MS = 1000;
const RECONNECT_MAX_MS = 30_000;

export class SwarmDashboardStore extends TypedEventEmitter<StoreEvents> {
  private state: SwarmDashboardState;
  private ws: WebSocket | null = null;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private reconnectDelay = RECONNECT_BASE_MS;
  private intentionalClose = false;
  private batchCounter = 0;

  constructor() {
    super();
    this.state = createInitialState();
  }

  /** Stable snapshot for useSyncExternalStore. */
  getSnapshot = (): SwarmDashboardState => this.state;

  /** Stable subscribe for useSyncExternalStore. */
  stableSubscribe = (listener: () => void): (() => void) => {
    return this.on('change', () => listener());
  };

  // ── Connection ──

  connect(url?: string): void {
    if (url) {
      this.state = { ...this.state, wsUrl: url };
    }
    this.intentionalClose = false;
    this.clearReconnect();
    this.openSocket();
  }

  disconnect(): void {
    this.intentionalClose = true;
    this.clearReconnect();
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    this.update({ connection: 'disconnected' });
  }

  selectNode(id: string | null): void {
    this.update({ selectedNodeId: id });
  }

  // ── Internal ──

  private openSocket(): void {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }

    this.update({ connection: 'connecting' });

    try {
      this.ws = new WebSocket(this.state.wsUrl);
    } catch {
      this.update({ connection: 'error' });
      this.scheduleReconnect();
      return;
    }

    this.ws.onopen = () => {
      this.reconnectDelay = RECONNECT_BASE_MS;
      this.update({ connection: 'connected', lastHeartbeat: Date.now() });
    };

    this.ws.onmessage = (event) => {
      this.handleMessage(event);
    };

    this.ws.onclose = () => {
      this.ws = null;
      if (!this.intentionalClose) {
        this.update({ connection: 'disconnected' });
        this.scheduleReconnect();
      }
    };

    this.ws.onerror = () => {
      // onclose will fire after onerror
    };
  }

  private scheduleReconnect(): void {
    this.clearReconnect();
    this.reconnectTimer = setTimeout(() => {
      this.reconnectDelay = Math.min(this.reconnectDelay * 2, RECONNECT_MAX_MS);
      this.openSocket();
    }, this.reconnectDelay);
  }

  private clearReconnect(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }

  /** Process a raw WebSocket message. Exposed for testing. */
  handleMessage(event: MessageEvent | { data: string }): void {
    let msg: H3WsMessage;
    try {
      msg = JSON.parse(typeof event.data === 'string' ? event.data : '');
    } catch {
      return;
    }

    switch (msg.type) {
      case 'welcome':
        this.update({ lastHeartbeat: Date.now() });
        break;

      case 'cell':
        this.handleCellEvent(msg);
        break;

      case 'stats':
        this.handleStatsEvent(msg);
        break;

      case 'batch':
        this.handleBatchEvent(msg);
        break;

      case 'anchor':
      case 'anchor_failed':
        this.handleAnchorEvent(msg);
        break;
    }
  }

  private handleCellEvent(msg: H3WsMessage): void {
    const adapted = adaptCellEvent(msg);
    if (!adapted) return;

    const nodes = [...this.state.nodes];
    const nodeId = adapted.sourceAddr;
    const nodeIdx = nodes.findIndex(n => n.id === nodeId);

    if (nodeIdx === -1) {
      const newNode: NodeData = {
        id: nodeId,
        persona: adapted.inferredPersona ?? 'router',
        heartbeat: adapted.receivedAt,
        uptime: 0,
        activeTable: adapted.parsed.tableId,
        cellCount: 1,
      };
      nodes.push(newNode);
    } else {
      nodes[nodeIdx] = {
        ...nodes[nodeIdx],
        heartbeat: adapted.receivedAt,
        cellCount: nodes[nodeIdx].cellCount + 1,
        activeTable: adapted.parsed.tableId ?? nodes[nodeIdx].activeTable,
      };
    }

    const edges = [...this.state.edges];
    const edgeKey = `${nodeId}->border-router`;
    const edgeIdx = edges.findIndex(e => `${e.source}->${e.target}` === edgeKey);
    if (edgeIdx === -1) {
      edges.push({ source: nodeId, target: 'border-router', cellCount: 1, lastFlash: Date.now() });
    } else {
      edges[edgeIdx] = {
        ...edges[edgeIdx],
        cellCount: edges[edgeIdx].cellCount + 1,
        lastFlash: Date.now(),
      };
    }

    this.update({ nodes, edges, lastHeartbeat: Date.now() });
  }

  private handleStatsEvent(msg: H3WsMessage): void {
    const adapted = adaptStatsEvent(msg);
    if (!adapted) return;

    const tpsHistory = ringPush(this.state.tpsHistory, adapted.tps, MAX_TPS_HISTORY);

    this.update({
      stats: adapted,
      tpsHistory,
      lastHeartbeat: Date.now(),
    });
  }

  private handleBatchEvent(msg: H3WsMessage): void {
    const adapted = adaptBatchEvent(msg);
    if (!adapted) return;

    this.batchCounter++;
    const batch: BatchAnchoredEvent = {
      ...adapted,
      batchNumber: this.batchCounter,
    };

    const batches = ringPush(this.state.batches, batch, MAX_BATCHES);
    this.update({ batches });
  }

  private handleAnchorEvent(msg: H3WsMessage): void {
    const adapted = adaptAnchorEvent(msg);
    if (!adapted) return;

    const batches = [...this.state.batches];
    const idx = batches.findIndex(b => b.merkleRoot === adapted.merkleRoot);
    if (idx !== -1 && adapted.txid) {
      batches[idx] = { ...batches[idx], bsvTxid: adapted.txid };
      this.update({ batches });
    }
  }

  // ── Synthetic Events (for demo / testing) ──

  injectHandCompleted(hand: HandCompletedEvent): void {
    const hands = ringPush(this.state.hands, hand, MAX_HANDS);
    this.update({ hands });
  }

  injectPersonaStats(update: PersonaStatsUpdate): void {
    this.update({ personaStats: update });
  }

  private update(partial: Partial<SwarmDashboardState>): void {
    this.state = { ...this.state, ...partial };
    this.emit('change', this.state);
  }
}

function ringPush<T>(arr: T[], item: T, max: number): T[] {
  const next = [item, ...arr];
  return next.length > max ? next.slice(0, max) : next;
}

```
