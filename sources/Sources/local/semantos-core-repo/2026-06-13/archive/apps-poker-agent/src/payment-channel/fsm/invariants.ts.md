---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/fsm/invariants.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.793814+00:00
---

# archive/apps-poker-agent/src/payment-channel/fsm/invariants.ts

```ts
/**
 * CashLanes guardrails — the four invariants pinned in
 * `CLAUDE.md § Payment-Channel FSM` and `§ Byte Pipeline`. Each
 * function is referenced by its rule number in the reducer + tests.
 *
 * Pure: no `await`, no `Date.now()`, no `Math.random()`, no `this`.
 */

import type {
  ChannelArtifacts,
  ChannelStateValue,
  RoleScopedKeyId,
  SpvProof,
} from './types';

/**
 * **Invariant 1 (freeze bytes at funding)**
 *
 * Once `state >= FUNDED`, `envelopeHex` and `simpleRawTx` must never
 * change. The reducer rejects any subsequent `fund` event that would
 * mutate them.
 */
export function assertArtifactsImmutable(
  current: ChannelArtifacts | undefined,
  next: ChannelArtifacts,
): { ok: true } | { ok: false; reason: string } {
  if (!current) return { ok: true };
  if (current.envelopeHex !== next.envelopeHex) {
    return { ok: false, reason: 'invariant 1: envelopeHex is frozen at FUNDED' };
  }
  if (current.simpleRawTx !== next.simpleRawTx) {
    return { ok: false, reason: 'invariant 1: simpleRawTx is frozen at FUNDED' };
  }
  if (current.txid !== next.txid) {
    return { ok: false, reason: 'invariant 1: txid is frozen at FUNDED' };
  }
  return { ok: true };
}

/**
 * **Invariant 2 (advance only on real wallet success / SPV proof)**
 *
 * FLOW_READY and SETTLING are "final" gates — the reducer must not
 * advance into them without an attached SPV proof. The proof itself
 * must be byte-shaped (non-empty bumpHash) to count as real.
 */
export function assertSpvAttached(
  proof: SpvProof | undefined,
): { ok: true } | { ok: false; reason: string } {
  if (!proof) {
    return { ok: false, reason: 'invariant 2: SPV proof must be attached before FLOW_READY/SETTLING' };
  }
  if (typeof proof.bumpHash !== 'string' || proof.bumpHash.length === 0) {
    return { ok: false, reason: 'invariant 2: SPV proof has empty bumpHash — not a real proof' };
  }
  return { ok: true };
}

/**
 * **Invariant 3 (no P2SH)**
 *
 * Channel funding must use a native 2-of-2 multisig output. P2SH
 * outputs are rejected outright at `fund`.
 */
export function assertNoP2SH(isNativeMultisig: boolean): { ok: true } | { ok: false; reason: string } {
  if (!isNativeMultisig) {
    return { ok: false, reason: 'invariant 3: channel funding must be native 2-of-2 (no P2SH)' };
  }
  return { ok: true };
}

/**
 * **Invariant 4 (role-scoped keyID format)**
 *
 * Every accepted keyID must follow `<role>-<scope>:<orgId>:<ts>:<nonce>`
 * where `<role>` matches the channel role.
 */
const KEY_ID_PATTERN = /^(consumer|provider)(?:-[a-z0-9]+)?:[A-Za-z0-9_.-]+:[0-9]+:[A-Za-z0-9_-]+$/;

export function assertRoleScopedKeyId(
  keyId: RoleScopedKeyId,
): { ok: true } | { ok: false; reason: string } {
  if (!KEY_ID_PATTERN.test(keyId.keyId)) {
    return {
      ok: false,
      reason: `invariant 4: keyID "${keyId.keyId}" does not match <role>(-<scope>)?:<orgId>:<ts>:<nonce>`,
    };
  }
  if (!keyId.keyId.startsWith(keyId.role)) {
    return {
      ok: false,
      reason: `invariant 4: keyID role prefix "${keyId.keyId.split(':')[0]}" must match channel role "${keyId.role}"`,
    };
  }
  return { ok: true };
}

/** Run all keyID checks; first failure short-circuits. */
export function assertKeyIds(
  keyIds: RoleScopedKeyId[],
): { ok: true } | { ok: false; reason: string } {
  for (const k of keyIds) {
    const result = assertRoleScopedKeyId(k);
    if (!result.ok) return result;
  }
  return { ok: true };
}

/**
 * Bundle the funding-time invariants (1, 3, 4). Called by the reducer
 * before transitioning into FUNDED. Also enforces that every supplied
 * keyID's `role` matches the channel's role — a refinement of
 * invariant 4.
 */
export function assertFundingInvariants(args: {
  current: ChannelStateValue;
  artifacts: ChannelArtifacts;
  isNativeMultisig: boolean;
  keyIds: RoleScopedKeyId[];
}): { ok: true } | { ok: false; reason: string } {
  const noP2sh = assertNoP2SH(args.isNativeMultisig);
  if (!noP2sh.ok) return noP2sh;
  for (const k of args.keyIds) {
    if (k.role !== args.current.role) {
      return {
        ok: false,
        reason: `invariant 4: keyID role "${k.role}" does not match channel role "${args.current.role}"`,
      };
    }
  }
  const keyOk = assertKeyIds(args.keyIds);
  if (!keyOk.ok) return keyOk;
  const frozenOk = assertArtifactsImmutable(args.current.artifacts, args.artifacts);
  if (!frozenOk.ok) return frozenOk;
  return { ok: true };
}

```
