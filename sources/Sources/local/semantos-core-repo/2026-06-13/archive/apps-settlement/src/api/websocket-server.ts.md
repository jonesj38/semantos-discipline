---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/api/websocket-server.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.714982+00:00
---

# archive/apps-settlement/src/api/websocket-server.ts

```ts
/**
 * WebSocketServer — Live event stream for the Border Router.
 *
 * Clients connect to ws://host:port and receive JSON-framed events
 * for new cells, closed batches, anchor submissions, and periodic stats.
 *
 * Event types:
 *   cell       — new cell collected and validated
 *   batch      — batch completed with Merkle root
 *   anchor     — batch anchored to BSV
 *   stats      — periodic stats update (every 10s)
 */

import { WebSocketServer as WsServer, WebSocket } from 'ws';

import type {
  CollectedCell,
  CellBatch,
  MerkleAnchor,
  LiveStats,
} from '../services/border-router-types';

// ── Message Types ────────────────────────────────────────────────────

interface WsMessage {
  type: 'cell' | 'batch' | 'anchor' | 'anchor_failed' | 'stats' | 'welcome';
  data: unknown;
  timestamp: number;
}

// ── WebSocketServer ──────────────────────────────────────────────────

export class BorderRouterWebSocket {
  private wss: WsServer | null = null;
  private port: number;
  private heartbeatInterval: ReturnType<typeof setInterval> | null = null;

  constructor(port: number) {
    this.port = port;
  }

  async start(): Promise<void> {
    return new Promise((resolve) => {
      this.wss = new WsServer({ port: this.port }, () => {
        console.log(`[WebSocket] Listening on port ${this.port}`);
        resolve();
      });

      this.wss.on('connection', (ws) => {
        // Send welcome message
        const welcome: WsMessage = {
          type: 'welcome',
          data: { message: 'Connected to Semantos Border Router live stream' },
          timestamp: Date.now(),
        };
        ws.send(JSON.stringify(welcome));
      });

      // Heartbeat ping/pong every 30s
      this.heartbeatInterval = setInterval(() => {
        this.wss?.clients.forEach((ws) => {
          if (ws.readyState === WebSocket.OPEN) {
            ws.ping();
          }
        });
      }, 30_000);
    });
  }

  async stop(): Promise<void> {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }

    if (!this.wss) return;

    // Close all connections
    this.wss.clients.forEach((ws) => {
      ws.close(1000, 'Server shutting down');
    });

    return new Promise((resolve) => {
      this.wss!.close(() => {
        console.log('[WebSocket] Stopped');
        resolve();
      });
    });
  }

  broadcastCell(cell: CollectedCell): void {
    this.broadcast({
      type: 'cell',
      data: {
        cellId: cell.cellId,
        semanticPath: cell.semanticPath,
        sourceAddr: cell.sourceAddr,
        receivedAt: cell.receivedAt,
        linearity: cell.linearity,
        contentHash: cell.contentHash.toString('hex'),
      },
      timestamp: Date.now(),
    });
  }

  broadcastBatch(batch: CellBatch, merkleRoot: Buffer): void {
    this.broadcast({
      type: 'batch',
      data: {
        batchId: batch.batchId,
        cellCount: batch.cells.length,
        openedAt: batch.openedAt,
        closedAt: batch.closedAt,
        merkleRoot: merkleRoot.toString('hex'),
      },
      timestamp: Date.now(),
    });
  }

  broadcastAnchor(anchor: MerkleAnchor): void {
    this.broadcast({
      type: 'anchor',
      data: {
        batchId: anchor.batchId,
        merkleRoot: anchor.merkleRoot.toString('hex'),
        txid: anchor.txid,
        leafCount: anchor.leafCount,
        status: anchor.status,
      },
      timestamp: Date.now(),
    });
  }

  broadcastAnchorFailed(anchor: MerkleAnchor, error: Error): void {
    this.broadcast({
      type: 'anchor_failed',
      data: {
        batchId: anchor.batchId,
        merkleRoot: anchor.merkleRoot.toString('hex'),
        error: error.message,
      },
      timestamp: Date.now(),
    });
  }

  broadcastStats(stats: LiveStats): void {
    this.broadcast({
      type: 'stats',
      data: stats,
      timestamp: Date.now(),
    });
  }

  getConnectionCount(): number {
    return this.wss?.clients.size ?? 0;
  }

  // ── Private ────────────────────────────────────────────────────────

  private broadcast(message: WsMessage): void {
    if (!this.wss) return;

    const payload = JSON.stringify(message);
    this.wss.clients.forEach((ws) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(payload);
      }
    });
  }
}

```
