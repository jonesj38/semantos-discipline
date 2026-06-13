---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/game-state-db-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.773206+00:00
---

# archive/apps-poker-agent/src/game-state-db/game-state-db-facade.ts

```ts
/**
 * Thin facade composing the per-table stores. Public method shape
 * matches the legacy `GameStateDB` exactly so consumers (game-loop,
 * p2p-agent-runner, agent-runtime) keep compiling unchanged.
 */

import { Database } from 'bun:sqlite';

import { ActionStore, type ActionInsert } from './action-store';
import type { DatabaseHandle } from './db-types';
import { CellTokenRefStore, type CellTokenRefInsert } from './celltoken-ref-store';
import { ContextBuilder } from './context-builder';
import { HandStore } from './hand-store';
import { MemoryStore } from './memory-store';
import { applySchema } from './schema';
import { makeSeqCounter, type SeqCounter } from './seq-counter';
import { SessionStore, type PlayerInsert, type SessionConfig } from './session-store';
import { SnapshotStore, type SnapshotInsert } from './snapshot-store';
import type {
  ActionRow,
  CellTokenRefRow,
  GameHistory,
  HandContext,
  StateSnapshotRow,
} from './types';

export class GameStateDB {
  private readonly db: DatabaseHandle;
  private readonly seq: SeqCounter;
  private readonly sessions: SessionStore;
  private readonly hands: HandStore;
  private readonly actions: ActionStore;
  private readonly snapshots: SnapshotStore;
  private readonly cellTokens: CellTokenRefStore;
  private readonly memory: MemoryStore;
  private readonly context: ContextBuilder;

  constructor(dbPath?: string) {
    this.db = new Database(dbPath ?? ':memory:');
    this.db.exec('PRAGMA journal_mode=WAL');
    applySchema(this.db);
    this.seq = makeSeqCounter(this.db);
    this.sessions = new SessionStore(this.db);
    this.hands = new HandStore(this.db);
    this.actions = new ActionStore(this.db, this.seq);
    this.snapshots = new SnapshotStore(this.db, this.seq);
    this.cellTokens = new CellTokenRefStore(this.db, this.seq);
    this.memory = new MemoryStore(this.db);
    this.context = new ContextBuilder(this.db);
  }

  // ── Sessions / Players ─────────────────────────────────────

  createSession(gameId: string, config: SessionConfig): void {
    this.sessions.createSession(gameId, config);
  }
  addPlayer(gameId: string, player: PlayerInsert): void {
    this.sessions.addPlayer(gameId, player);
  }

  // ── Hands ──────────────────────────────────────────────────

  startHand(gameId: string, handNumber: number, dealerSeat: number): number {
    return this.hands.startHand(gameId, handNumber, dealerSeat);
  }
  endHand(handId: number, winnerId: string, potTotal: number): void {
    this.hands.endHand(handId, winnerId, potTotal);
  }

  // ── Actions / Snapshots / CellTokens ───────────────────────

  recordAction(handId: number, action: ActionInsert): number {
    return this.actions.recordAction(handId, action);
  }
  recordSnapshot(handId: number, snapshot: SnapshotInsert): number {
    return this.snapshots.recordSnapshot(handId, snapshot);
  }
  recordCellToken(handId: number, ref: CellTokenRefInsert): number {
    return this.cellTokens.recordCellToken(handId, ref);
  }

  // ── Agent memory ───────────────────────────────────────────

  setMemory(agentName: string, key: string, value: string): void {
    this.memory.setMemory(agentName, key, value);
  }
  getMemory(agentName: string, key: string): string | null {
    return this.memory.getMemory(agentName, key);
  }
  getAllMemory(agentName: string): Record<string, string> {
    return this.memory.getAllMemory(agentName);
  }

  // ── Context queries ────────────────────────────────────────

  getActionsSince(sinceSeq: number, handId?: number): ActionRow[] {
    return this.actions.getActionsSince(sinceSeq, handId);
  }
  getSnapshotsSince(sinceSeq: number): StateSnapshotRow[] {
    return this.snapshots.getSnapshotsSince(sinceSeq);
  }
  getCurrentHandContext(gameId: string, agentName: string): HandContext | null {
    return this.context.getCurrentHandContext(gameId, agentName);
  }
  getGameHistory(gameId: string, agentName: string, recentN: number = 10): GameHistory {
    return this.context.getGameHistory(gameId, agentName, recentN);
  }
  getCellTokens(handId: number): CellTokenRefRow[] {
    return this.cellTokens.getCellTokens(handId);
  }

  // ── Lifecycle ──────────────────────────────────────────────

  getSeq(): number {
    return this.seq.current();
  }
  close(): void {
    this.db.close();
  }
}

```
