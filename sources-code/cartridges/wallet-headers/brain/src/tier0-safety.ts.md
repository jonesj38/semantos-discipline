---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/tier0-safety.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.656498+00:00
---

# cartridges/wallet-headers/brain/src/tier0-safety.ts

```ts
// Tier-0 safety policy.
//
// Tier 0 is intentionally unencumbered: the key material is available on
// the user's device without an extra factor so tiny payments and identity
// flows stay ergonomic. That only remains safe while the balance protected
// by that posture is capped. This module gives the wallet/UI a single,
// testable answer to "is the hot plaintext-key exposure still acceptable?"
// and prepares the deterministic sweep plan the tx-builder will consume.

import type { OutputRecord } from './output-store';

export const TIER0_PLAINTEXT_BALANCE_LIMIT_SATS = 1_000_000n;

export interface Tier0Exposure {
  balanceSats: bigint;
  limitSats: bigint;
  excessSats: bigint;
  plaintextUtxoCount: number;
  sweepRequired: boolean;
  sweepTargetTier: 1 | 2 | 3 | null;
}

export interface Tier0SweepPlan {
  required: boolean;
  targetTier: 1 | 2 | 3 | null;
  sweepOutpoints: string[];
  keepOutpoints: string[];
  sweepSatoshis: bigint;
  remainingPlaintextSats: bigint;
  limitSats: bigint;
  reason: 'within_limit' | 'plaintext_balance_exceeds_limit';
}

export function assessTier0PlaintextExposure(
  outputs: readonly OutputRecord[],
  limitSats: bigint = TIER0_PLAINTEXT_BALANCE_LIMIT_SATS,
): Tier0Exposure {
  const owned = tier0PlaintextOutputs(outputs);
  const balance = owned.reduce((sum, o) => sum + o.satoshis, 0n);
  const excess = balance > limitSats ? balance - limitSats : 0n;
  return {
    balanceSats: balance,
    limitSats,
    excessSats: excess,
    plaintextUtxoCount: owned.length,
    sweepRequired: excess > 0n,
    sweepTargetTier: excess > 0n ? targetTierForBalance(balance) : null,
  };
}

export function createTier0SweepPlan(
  outputs: readonly OutputRecord[],
  limitSats: bigint = TIER0_PLAINTEXT_BALANCE_LIMIT_SATS,
): Tier0SweepPlan {
  const owned = tier0PlaintextOutputs(outputs);
  const balance = owned.reduce((sum, o) => sum + o.satoshis, 0n);
  if (balance <= limitSats) {
    return {
      required: false,
      targetTier: null,
      sweepOutpoints: [],
      keepOutpoints: owned.map(outputKey),
      sweepSatoshis: 0n,
      remainingPlaintextSats: balance,
      limitSats,
      reason: 'within_limit',
    };
  }

  const sorted = owned.slice().sort((a, b) => compareBigintDesc(a.satoshis, b.satoshis));
  const sweep: OutputRecord[] = [];
  let remaining = balance;
  for (const o of sorted) {
    if (remaining <= limitSats) break;
    sweep.push(o);
    remaining -= o.satoshis;
  }
  const sweepKeys = new Set(sweep.map(outputKey));
  return {
    required: true,
    targetTier: targetTierForBalance(balance),
    sweepOutpoints: sweep.map(outputKey),
    keepOutpoints: owned.filter((o) => !sweepKeys.has(outputKey(o))).map(outputKey),
    sweepSatoshis: sweep.reduce((sum, o) => sum + o.satoshis, 0n),
    remainingPlaintextSats: remaining,
    limitSats,
    reason: 'plaintext_balance_exceeds_limit',
  };
}

function tier0PlaintextOutputs(outputs: readonly OutputRecord[]): OutputRecord[] {
  return outputs.filter((o) => {
    if (o.status !== 'unspent') return false;
    if (o.satoshis <= 0n) return false;
    // Basket insertions use zero key material. Wallet-payment outputs carry
    // a real derivedKeyHash and are spendable by this device's hot key path.
    return !allZero(o.derivedKeyHash);
  });
}

function targetTierForBalance(balance: bigint): 1 | 2 | 3 {
  if (balance <= 10_000_000n) return 1;
  if (balance <= 100_000_000n) return 2;
  return 3;
}

function compareBigintDesc(a: bigint, b: bigint): number {
  if (a === b) return 0;
  return a > b ? -1 : 1;
}

function outputKey(o: OutputRecord): string {
  return `${bytesToHex(o.outpoint.txid)}:${o.outpoint.vout}`;
}

function allZero(bytes: Uint8Array): boolean {
  for (const b of bytes) {
    if (b !== 0) return false;
  }
  return true;
}

function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

```
