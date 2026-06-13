---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/interfaces.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.845277+00:00
---

# core/protocol-types/src/interfaces.ts

```ts
/**
 * Cell-engine-specific interfaces — NOT duplicates of @semantos/core types.
 */

export interface BCAInput {
  publicKey: Uint8Array;
  modifier: Uint8Array;
  subnetPrefix: Uint8Array;
  /** Security parameter (0–7). Encoded in 3 MSBs of interface ID byte 0. Default: 2. */
  sec?: number;
}

export interface BCAOutput {
  ipv6Address: Uint8Array;
  collisionCount: number;
}

export interface BCAVerifyInput {
  publicKey: Uint8Array;
  ipv6Address: Uint8Array;
  modifier: Uint8Array;
  subnetPrefix: Uint8Array;
}

export interface ScriptContext {
  lockingScript: Uint8Array;
  unlockingScript: Uint8Array;
  txVersion: number;
  locktime: number;
  sequence: number;
}

export interface ScriptResult {
  success: boolean;
  typeClassification: number;
  opcodeCount: number;
  error: string | null;
}

export interface LinearityOperation {
  operation: "DUP" | "DROP" | "SWAP" | "OVER";
  typeClassification: number;
}

export interface LinearityResult {
  allowed: boolean;
  reason: string | null;
}

export interface CapabilityTokenRef {
  tokenId: string;
  type: string;
  ownerPubKey: string;
  outpoint: string | null;
}

```
