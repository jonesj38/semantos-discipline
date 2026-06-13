---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/relay/forfeit-template.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.437231+00:00
---

# cartridges/shared/relay/forfeit-template.ts

```ts
/**
 * D14 custody-free watchtower — primitive layer.
 *
 * CW Lift L2 (docs/canon/cw-lift-matrix.yml).
 *
 * Ports the watchtower pattern from prof-faustus/bonded-subsat-channel
 * (MIT) @ src/channel/watchtower/{tower,cluster,registry}.py.
 *
 * THE KEY PROPERTY (D14 incentive scheme):
 *   The watchtower holds NO private keys. It holds only pre-signed
 *   forfeit transactions that the channel parties signed at registration.
 *   The pre-signed forfeit pays the tower a fixed `tower_fee` in its
 *   FIRST output. Counterparties signed with `SIGHASH_ALL | FORKID`,
 *   which means the tower can only broadcast the EXACT pre-signed
 *   bytes — any modification invalidates the multisig at the
 *   interpreter level.
 *
 *   So: act (broadcast on stale-state detection) → fee.
 *       Do nothing → no fee.
 *       Tamper with the tx (redirect fee, omit output, etc.) → script
 *       interpreter rejects, no broadcast, no fee.
 *
 *   The incentive structure is enforced by the script interpreter, not
 *   by trust. Matches Craig's `craig_no_keys_on_device_stance` rule:
 *   devices verify+act, wallets sign.
 *
 * Mechanism:
 *   1. At channel-open, every party signs a forfeit tx that:
 *      - Spends the offender's bond UTXO via the forfeiture branch
 *      - Pays `tower_fee` to the watchtower's address in vout 0
 *      - Distributes the remaining bond pro-rata to honest counterparties
 *      - Is signed with SIGHASH_ALL | FORKID (pins entire tx)
 *      - Is registered with the watchtower indexed by (channelId, offendingPartyIdx)
 *   2. Per-state, parties sign an updated current-state tx with monotonic
 *      nSequence and register it with the tower.
 *   3. Watchtower observes mempool. If a tx spending the channel
 *      funding outpoint at vout 0 arrives with nSequence LOWER than the
 *      registered current state's, that's a stale broadcast →
 *      watchtower rebroadcasts the pre-signed CURRENT state, which
 *      beats the stale one under BSV's original-protocol replacement
 *      rule (higher-sequence supersedes).
 *   4. After the current-state tx confirms, watchtower broadcasts the
 *      pre-signed forfeit against the offender's bond → collects fee.
 *
 * This module ships the primitive layer:
 *   - ForfeitTemplate type — the pre-signed forfeit + binding metadata
 *   - WatchtowerRegistry interface — per-channel state + per-offender
 *     forfeit storage
 *   - detectStaleState — pure function: given a mempool tx + registry,
 *     return whether it's a stale broadcast
 *   - assertD14Incentive — validate that a forfeit tx has the tower fee
 *     pinned in vout 0 with SIGHASH_ALL
 *   - InMemoryWatchtowerRegistry — reference impl for tests + ephemeral use
 *
 * Brain-side mempool observer + actual tx broadcasting are runtime
 * integration concerns deferred to a follow-up (Zig brain code).
 */

// ── Types ───────────────────────────────────────────────────────────

/** Identifier for a payment channel. 32B hash, typically the funding
 *  tx hash. */
export type ChannelId = Uint8Array;

/** Index of a party within a channel (0..n-1, stable across the
 *  channel lifetime). */
export type PartyIndex = number;

/**
 * A pre-signed forfeit transaction. The watchtower holds the raw bytes;
 * the metadata is what the registry indexes on.
 */
export interface ForfeitTemplate {
  /** Channel this forfeit applies to. */
  readonly channelId: ChannelId;
  /** Index of the party whose bond this forfeit consumes (the
   *  "offender" — the one who would broadcast stale state). */
  readonly offendingPartyIdx: PartyIndex;
  /** Raw signed transaction bytes. The watchtower can ONLY broadcast
   *  these bytes verbatim — counterparties signed with SIGHASH_ALL,
   *  so any modification invalidates the signatures and the script
   *  interpreter rejects. */
  readonly rawTxBytes: Uint8Array;
  /** Hash of the rawTxBytes (txid). Used as a registry key. */
  readonly txid: Uint8Array;
  /** Tower fee in satoshis. The first output of rawTxBytes pays this
   *  amount to towerAddress; the D14 incentive depends on the tower
   *  having no other way to earn (acting → fee; tampering → broadcast
   *  fails). */
  readonly towerFeeSats: number;
  /** Tower's destination address that vout 0 pays. Set at registration
   *  time and pinned into the pre-signed bytes via SIGHASH_ALL. */
  readonly towerAddress: Uint8Array;
  /** Pre-signed by these party indices (used by assertD14Incentive to
   *  confirm the right counterparty quorum signed). */
  readonly signedByPartyIdxs: readonly PartyIndex[];
}

/**
 * A pre-signed channel-state transaction. The watchtower rebroadcasts
 * this when it sees a stale-state broadcast (lower-sequence) hit the
 * mempool.
 */
export interface ChannelStateTx {
  /** Channel this state belongs to. */
  readonly channelId: ChannelId;
  /** Monotonic state sequence — higher supersedes lower under BSV's
   *  original-protocol replacement rule. */
  readonly stateSequence: number;
  /** Raw signed transaction bytes spending the channel funding
   *  outpoint at vout 0. */
  readonly rawTxBytes: Uint8Array;
  /** Hash of the rawTxBytes (txid). */
  readonly txid: Uint8Array;
}

/**
 * Watchtower registry: per-channel current state + per-offender forfeit
 * templates. The watchtower holds NO keys — only signed bytes.
 */
export interface WatchtowerRegistry {
  /** Record the current state tx for a channel. New registrations with
   *  higher stateSequence REPLACE older ones; lower-sequence calls
   *  must be rejected. */
  registerCurrentState(state: ChannelStateTx): Promise<void> | void;
  /** Fetch the current state for a channel, or null if none registered. */
  getCurrentState(channelId: ChannelId): Promise<ChannelStateTx | null> | ChannelStateTx | null;
  /** Record a pre-signed forfeit template indexed by (channelId,
   *  offendingPartyIdx). */
  registerForfeit(template: ForfeitTemplate): Promise<void> | void;
  /** Fetch the forfeit template for a (channelId, offendingPartyIdx). */
  getForfeit(
    channelId: ChannelId,
    offendingPartyIdx: PartyIndex,
  ): Promise<ForfeitTemplate | null> | ForfeitTemplate | null;
}

// ── Stale-state detection ──────────────────────────────────────────

/**
 * Observation from the watchtower's mempool observer. The caller
 * (Zig brain runtime, separate from this primitive) parses the BSV
 * mempool tx and feeds the relevant fields here.
 */
export interface MempoolObservation {
  /** Channel this candidate tx is broadcasting state for. The brain
   *  identifies the channel by walking the tx's inputs and matching
   *  the funding outpoint against the registered channel set. */
  readonly channelId: ChannelId;
  /** The candidate tx's sequence number on the funding-outpoint input
   *  (the state sequence the broadcaster is asserting). */
  readonly candidateSequence: number;
  /** Hash of the candidate tx. */
  readonly candidateTxid: Uint8Array;
}

/** Result of stale-state detection. */
export type StaleStateResult =
  | { stale: false; reason: 'no_registered_state' | 'current_or_newer' }
  | {
      stale: true;
      /** The registered current state — what the tower should rebroadcast. */
      rebroadcast: ChannelStateTx;
      /** The sequence the broadcaster claimed. */
      candidateSequence: number;
      /** The registered current sequence (higher than candidate). */
      currentSequence: number;
    };

/**
 * Detect whether a mempool observation represents a stale-state
 * broadcast that the watchtower should counter with a rebroadcast of
 * the registered current state.
 *
 * Pure function — no I/O. Caller fetches the current state from the
 * registry and passes it in; we just compare sequences.
 *
 * A "stale broadcast" is one where the broadcaster is trying to
 * close the channel at a sequence that's been superseded. Under BSV's
 * original-protocol replacement rule, a higher-sequence tx beats a
 * lower-sequence one in the mempool. So the tower's response is to
 * push the registered current state.
 */
export function detectStaleState(
  observation: MempoolObservation,
  currentState: ChannelStateTx | null,
): StaleStateResult {
  if (currentState === null) {
    return { stale: false, reason: 'no_registered_state' };
  }
  if (!bytesEqual(currentState.channelId, observation.channelId)) {
    // Defensive: shouldn't happen if caller looked up by channelId,
    // but if a registry returns a wrong-channel state, treat as if
    // no state is registered for THIS channel.
    return { stale: false, reason: 'no_registered_state' };
  }
  if (observation.candidateSequence >= currentState.stateSequence) {
    return { stale: false, reason: 'current_or_newer' };
  }
  return {
    stale: true,
    rebroadcast: currentState,
    candidateSequence: observation.candidateSequence,
    currentSequence: currentState.stateSequence,
  };
}

// ── D14 incentive validation ───────────────────────────────────────

/** Result of D14 incentive check. */
export type D14CheckResult =
  | { ok: true }
  | { ok: false; code: D14Failure; message: string };

export type D14Failure =
  | 'TOWER_NOT_VOUT_0'
  | 'TOWER_FEE_MISMATCH'
  | 'TOWER_ADDRESS_MISMATCH'
  | 'INSUFFICIENT_SIGNERS'
  | 'CHANNEL_MISMATCH';

/**
 * Inputs to assertD14Incentive — caller's decoded view of the
 * pre-signed forfeit tx (this primitive doesn't include a tx parser;
 * the caller's wallet/SDK layer parses).
 */
export interface DecodedForfeitTx {
  /** vout 0 pays this address. */
  readonly vout0Address: Uint8Array;
  /** vout 0 pays this many satoshis. */
  readonly vout0Sats: number;
  /** Signer party indices verifiable on the inputs. */
  readonly verifiedSignerIdxs: readonly PartyIndex[];
}

/**
 * Validate that a pre-signed forfeit template meets the D14 incentive
 * conditions:
 *   1. The first output (vout 0) pays the registered tower address.
 *   2. The first output's value is the agreed tower_fee.
 *   3. The forfeit is signed by at least the quorum the template claims.
 *
 * Caller is responsible for verifying that SIGHASH_ALL was used on each
 * signature (this is a wallet/SDK concern; the primitive layer can't
 * re-execute the script interpreter to confirm). The convention: every
 * signature uses SIGHASH_ALL | FORKID. If a caller's verifier finds a
 * non-ALL sighash, the template must be rejected before reaching here.
 *
 * Returns { ok: true } if the template is binding-correct; otherwise
 * { ok: false, code, message } identifying which axis failed.
 */
export function assertD14Incentive(
  template: ForfeitTemplate,
  decoded: DecodedForfeitTx,
  expectedQuorum: readonly PartyIndex[],
): D14CheckResult {
  // 1. vout 0 must pay the registered tower address.
  if (!bytesEqual(decoded.vout0Address, template.towerAddress)) {
    return {
      ok: false,
      code: 'TOWER_ADDRESS_MISMATCH',
      message: 'vout 0 does not pay the template.towerAddress — tower fee not collectable',
    };
  }
  // 2. vout 0 sats must equal template.towerFeeSats.
  if (decoded.vout0Sats !== template.towerFeeSats) {
    return {
      ok: false,
      code: 'TOWER_FEE_MISMATCH',
      message: `vout 0 pays ${decoded.vout0Sats} sats; template asserts towerFeeSats=${template.towerFeeSats}`,
    };
  }
  // 3. At least the expected quorum must have signed.
  const verified = new Set(decoded.verifiedSignerIdxs);
  for (const required of expectedQuorum) {
    if (!verified.has(required)) {
      return {
        ok: false,
        code: 'INSUFFICIENT_SIGNERS',
        message: `expected signer index ${required} not in verified set [${decoded.verifiedSignerIdxs.join(',')}]`,
      };
    }
  }
  return { ok: true };
}

// ── In-memory registry (reference impl, tests + ephemeral use) ────

export class InMemoryWatchtowerRegistry implements WatchtowerRegistry {
  private readonly currentStates = new Map<string, ChannelStateTx>();
  private readonly forfeits = new Map<string, ForfeitTemplate>();

  registerCurrentState(state: ChannelStateTx): void {
    const key = bytesKey(state.channelId);
    const existing = this.currentStates.get(key);
    if (existing !== undefined && state.stateSequence <= existing.stateSequence) {
      throw new Error(
        `registerCurrentState: new state sequence ${state.stateSequence} does not supersede ` +
          `existing sequence ${existing.stateSequence} for channel ${key}`,
      );
    }
    this.currentStates.set(key, state);
  }

  getCurrentState(channelId: ChannelId): ChannelStateTx | null {
    return this.currentStates.get(bytesKey(channelId)) ?? null;
  }

  registerForfeit(template: ForfeitTemplate): void {
    const key = forfeitKey(template.channelId, template.offendingPartyIdx);
    this.forfeits.set(key, template);
  }

  getForfeit(channelId: ChannelId, offendingPartyIdx: PartyIndex): ForfeitTemplate | null {
    return this.forfeits.get(forfeitKey(channelId, offendingPartyIdx)) ?? null;
  }

  /** Convenience for tests / operational scans. */
  size(): { states: number; forfeits: number } {
    return { states: this.currentStates.size, forfeits: this.forfeits.size };
  }
}

// ── Internal helpers ───────────────────────────────────────────────

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.byteLength !== b.byteLength) return false;
  for (let i = 0; i < a.byteLength; i++) if (a[i] !== b[i]) return false;
  return true;
}

function bytesKey(b: Uint8Array): string {
  return Buffer.from(b).toString('hex');
}

function forfeitKey(channelId: ChannelId, partyIdx: PartyIndex): string {
  return `${bytesKey(channelId)}:${partyIdx}`;
}

```
