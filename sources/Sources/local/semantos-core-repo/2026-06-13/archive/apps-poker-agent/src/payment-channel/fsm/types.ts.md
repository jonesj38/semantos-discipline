---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/fsm/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.793249+00:00
---

# archive/apps-poker-agent/src/payment-channel/fsm/types.ts

```ts
/**
 * Payment-channel FSM types — pure data shapes for the reducer.
 *
 * State set follows the CashLanes spec (`CLAUDE.md § Payment-Channel
 * FSM`):
 *
 *   UNFUNDED → FUNDING_PENDING → FUNDED → FLOW_READY → FLOW_ACTIVE →
 *   SETTLING → CLOSED
 *
 * The reducer enforces the "Idempotent, Minimal" guardrails from the
 * same doc — see `invariants.ts` for the rule numbers.
 */

/** Canonical state set. */
export type ChannelState =
  | 'UNFUNDED'
  | 'FUNDING_PENDING'
  | 'FUNDED'
  | 'FLOW_READY'
  | 'FLOW_ACTIVE'
  | 'SETTLING'
  | 'CLOSED';

/** Roles in a 2-of-2 channel. */
export type ChannelRole = 'consumer' | 'provider';

/**
 * Frozen funding artifacts captured the moment the wallet returns from
 * `createAction`. Bytes never change after FUNDING_PENDING → FUNDED.
 */
export interface ChannelArtifacts {
  /** Wallet's original tx envelope, hex-encoded. Frozen at funding. */
  envelopeHex: string;
  /** Extracted simple raw tx, hex-encoded. Frozen at funding. */
  simpleRawTx: string;
  /** SHA-256 of envelopeHex bytes. */
  envelopeHash: string;
  /** SHA-256 of simpleRawTx bytes. */
  simpleHash: string;
  /** Computed from simpleRawTx (double SHA-256). */
  txid: string;
  /** Locking script hex of the multisig output. */
  lockingScriptHex: string;
  /** Output index of the multisig in simpleRawTx (exact script match). */
  vout: number;
}

/** SPV proof envelope attached at finalization gates (FLOW_READY/SETTLING). */
export interface SpvProof {
  /** BUMP-format Merkle proof root. */
  bumpHash: string;
  /** Block hash that includes the funding tx. */
  blockHash?: string;
  /** Confirmation depth at attach time. */
  confirmations: number;
}

export interface RoleScopedKeyId {
  /** Channel role this keyID is scoped to. */
  role: ChannelRole;
  /** "<role>-<scope>:<orgId>:<ts>:<nonce>" — exact format pinned by invariant 4. */
  keyId: string;
}

/**
 * Reducer state. Every transition produces a new immutable snapshot.
 */
export interface ChannelStateValue {
  state: ChannelState;
  channelId: string;
  role: ChannelRole;
  /** Frozen funding artifacts; populated on FUNDED. */
  artifacts?: ChannelArtifacts;
  /** SPV proof; required to enter FLOW_READY (and any later "final" gate). */
  spvProof?: SpvProof;
  /** Role-scoped keyIDs the reducer has accepted. */
  keyIds: RoleScopedKeyId[];
  /** Whether the channel script is native 2-of-2 (invariant 3 forbids P2SH). */
  isNativeMultisig: boolean;
  /** Last error reason — populated when an event was rejected. */
  lastError?: string;
}

/**
 * Events the reducer accepts. Each maps to a specific transition.
 */
export type ChannelEvent =
  | { type: 'fund'; artifacts: ChannelArtifacts; isNativeMultisig: boolean; keyIds: RoleScopedKeyId[] }
  | { type: 'extract'; vout: number }
  | { type: 'attach-spv'; proof: SpvProof }
  | { type: 'flow-ready' }
  | { type: 'flow-activate' }
  | { type: 'flow-deactivate' }
  | { type: 'settle-begin'; spvProof: SpvProof }
  | { type: 'close' };

/**
 * Commands the reducer asks the effect layer to execute.
 *
 * The reducer is pure — it never makes wallet calls or broadcasts. It
 * just decides what should happen next; prompts 14/15 wire the
 * effects.
 */
export type ChannelCommand =
  | { type: 'persist-artifacts'; artifacts: ChannelArtifacts }
  | { type: 'persist-spv'; proof: SpvProof }
  | { type: 'mark-state'; state: ChannelState }
  | { type: 'emit-event'; event: ChannelEvent };

export interface ReducerResult {
  next: ChannelStateValue;
  emitted: ChannelCommand[];
}

/** Build a fresh UNFUNDED state for a new channel. */
export function initialChannelState(
  channelId: string,
  role: ChannelRole,
): ChannelStateValue {
  return {
    state: 'UNFUNDED',
    channelId,
    role,
    keyIds: [],
    isNativeMultisig: false,
  };
}

```
