---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/context-builder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.772499+00:00
---

# archive/apps-poker-agent/src/game-state-db/context-builder.ts

```ts
/**
 * Cross-table context queries — `getCurrentHandContext` +
 * `getGameHistory`. These join across hands / players / actions /
 * state_snapshots and don't fit cleanly inside any single store
 * file, so the prompt-21 spec gives them their own home.
 *
 * SQL is allowed here because the queries are inherently
 * cross-table. Per-table CRUD lives in the individual store files.
 */

import type { DatabaseHandle } from './db-types';

import {
  mapActionRow,
  mapHandRow,
  mapPlayerRow,
  mapStateSnapshotRow,
  parseCommunityCards,
} from './row-mappers';
import type {
  ActionRow,
  GameHistory,
  HandContext,
  HandRow,
  HandSummary,
  PlayerRow,
  StateSnapshotRow,
} from './types';

export class ContextBuilder {
  constructor(private readonly db: DatabaseHandle) {}

  /**
   * Build everything an agent needs to make a decision for the
   * current hand. `myCards` and `legalActions` are filled by the
   * caller (hole cards stay private; legal-actions come from the
   * engine, not the DB).
   */
  getCurrentHandContext(gameId: string, agentName: string): HandContext | null {
    const hand = this.latestHand(gameId);
    if (!hand) return null;
    const me = this.player(gameId, agentName);
    if (!me) return null;
    const opponent = this.opponentPlayer(gameId, agentName);
    const snapshot = this.latestSnapshot(hand.hand_id);
    const actions = this.actionsForHand(gameId, hand.hand_id);

    const myLastAction = actions.filter((a) => a.player_id === me.player_id).pop();
    const myChips = myLastAction?.chips_after ?? me.starting_chips;
    const opLastAction = opponent
      ? actions.filter((a) => a.player_id === opponent.player_id).pop()
      : null;
    const opponentChips = opLastAction?.chips_after ?? opponent?.starting_chips ?? 0;

    return {
      handNumber: hand.hand_number,
      dealerSeat: hand.dealer_seat,
      myCards: [],
      communityCards: snapshot ? parseCommunityCards(snapshot) : [],
      phase: snapshot?.phase ?? 'preflop',
      pot: snapshot?.pot ?? 0,
      myChips,
      opponentChips,
      actions: actions.map((a) => ({
        seq: a.seq,
        player: a.agent_name,
        action: a.action_type,
        amount: a.amount,
        phase: a.phase,
      })),
      legalActions: [],
    };
  }

  /**
   * Aggregate per-hand outcomes into a strategic summary —
   * "am I ahead overall? How has opponent been playing?"
   */
  getGameHistory(gameId: string, agentName: string, recentN: number = 10): GameHistory {
    const me = this.player(gameId, agentName);
    const hands = this.completedHands(gameId, recentN);

    let myWins = 0;
    let opponentWins = 0;
    const recentHands: HandSummary[] = [];

    for (const h of hands) {
      const isMyWin = h.winner_id === me?.player_id;
      if (isMyWin) myWins++;
      else opponentWins++;
      const dominant = this.dominantAction(h.hand_id, me?.player_id ?? '');
      recentHands.push({
        handNumber: h.hand_number,
        winner: isMyWin ? agentName : 'opponent',
        potSize: h.pot_total,
        showdown: !dominant || dominant !== 'fold',
        myAction: dominant ?? 'unknown',
      });
    }

    const currentChipsRow = this.db
      .prepare('SELECT chips_after FROM actions WHERE player_id = ? ORDER BY seq DESC LIMIT 1')
      .get(me?.player_id ?? '') as { chips_after: number } | null;
    const currentChips = currentChipsRow?.chips_after ?? me?.starting_chips ?? 0;

    return {
      handsPlayed: hands.length,
      myWins,
      opponentWins,
      myChipDelta: currentChips - (me?.starting_chips ?? 0),
      recentHands,
    };
  }

  // ── Internal helpers (cross-table SQL lives here) ───────────────

  private latestHand(gameId: string): HandRow | null {
    const raw = this.db
      .prepare('SELECT * FROM hands WHERE game_id = ? ORDER BY hand_number DESC LIMIT 1')
      .get(gameId);
    return raw ? mapHandRow(raw) : null;
  }

  private completedHands(gameId: string, recentN: number): HandRow[] {
    const rows = this.db
      .prepare(
        `SELECT * FROM hands WHERE game_id = ? AND ended_at IS NOT NULL
         ORDER BY hand_number DESC LIMIT ?`,
      )
      .all(gameId, recentN) as unknown[];
    return rows.map(mapHandRow);
  }

  private player(gameId: string, agentName: string): PlayerRow | null {
    const raw = this.db
      .prepare('SELECT * FROM players WHERE game_id = ? AND agent_name = ?')
      .get(gameId, agentName);
    return raw ? mapPlayerRow(raw) : null;
  }

  private opponentPlayer(gameId: string, agentName: string): PlayerRow | null {
    const raw = this.db
      .prepare('SELECT * FROM players WHERE game_id = ? AND agent_name != ?')
      .get(gameId, agentName);
    return raw ? mapPlayerRow(raw) : null;
  }

  private latestSnapshot(handId: number): StateSnapshotRow | null {
    const raw = this.db
      .prepare('SELECT * FROM state_snapshots WHERE hand_id = ? ORDER BY seq DESC LIMIT 1')
      .get(handId);
    return raw ? mapStateSnapshotRow(raw) : null;
  }

  private actionsForHand(
    gameId: string,
    handId: number,
  ): (ActionRow & { agent_name: string })[] {
    const rows = this.db
      .prepare(
        `SELECT a.*, p.agent_name FROM actions a
         JOIN players p ON a.player_id = p.player_id AND p.game_id = ?
         WHERE a.hand_id = ? ORDER BY a.seq`,
      )
      .all(gameId, handId) as unknown[];
    return rows.map((r) => {
      const mapped = mapActionRow(r);
      return { ...mapped, agent_name: String((r as { agent_name: string }).agent_name) };
    });
  }

  private dominantAction(handId: number, playerId: string): string | null {
    const row = this.db
      .prepare(
        `SELECT action_type, COUNT(*) as cnt FROM actions
         WHERE hand_id = ? AND player_id = ?
         GROUP BY action_type ORDER BY cnt DESC LIMIT 1`,
      )
      .get(handId, playerId) as { action_type: string; cnt: number } | null;
    return row?.action_type ?? null;
  }
}

```
