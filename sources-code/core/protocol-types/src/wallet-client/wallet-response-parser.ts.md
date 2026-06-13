---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/wallet-response-parser.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.872823+00:00
---

# core/protocol-types/src/wallet-client/wallet-response-parser.ts

```ts
/**
 * Pure per-method response parsers — mirror the request builders.
 *
 * Each parser takes the raw JSON the transport returned and reduces
 * it to the public shape the facade exposes. Error envelopes
 * (`{status: 'error'}`) are detected via {@link throwIfError} before
 * a parser ever runs.
 */

import type {
  CreateActionResult,
  WalletOutputEntry,
} from './types';

export function parseIsAuthenticated(res: unknown): boolean {
  if (typeof res === 'boolean') return res;
  return Boolean((res as { authenticated?: boolean })?.authenticated);
}

export function parseGetHeight(res: unknown): number {
  if (typeof res === 'number') return res;
  return Number((res as { height?: number })?.height ?? 0);
}

export function parseGetNetwork(res: unknown): 'mainnet' | 'testnet' {
  if (res === 'mainnet' || res === 'testnet') return res;
  const n = (res as { network?: 'mainnet' | 'testnet' })?.network;
  return n ?? 'mainnet';
}

export function parseGetPublicKey(res: unknown): string {
  if (typeof res === 'string') return res;
  return (res as { publicKey?: string })?.publicKey ?? '';
}

export function parseListOutputs(res: unknown): WalletOutputEntry[] {
  if (Array.isArray(res)) return res as WalletOutputEntry[];
  const outputs = (res as { outputs?: WalletOutputEntry[] })?.outputs;
  return outputs ?? [];
}

export function parseCreateAction(res: unknown): CreateActionResult {
  const r = res as Partial<CreateActionResult> | undefined;
  return {
    txid: r?.txid ?? '',
    ...(r?.tx !== undefined ? { tx: r.tx } : {}),
    ...(r?.rawTx !== undefined ? { rawTx: r.rawTx } : {}),
    ...(r?.proof !== undefined ? { proof: r.proof } : {}),
    ...(r?.signableTransaction !== undefined
      ? { signableTransaction: r.signableTransaction }
      : {}),
  };
}

export function parseSignAction(res: unknown): CreateActionResult {
  const r = res as Partial<CreateActionResult> | undefined;
  return {
    txid: r?.txid ?? '',
    ...(r?.tx !== undefined ? { tx: r.tx } : {}),
    ...(r?.rawTx !== undefined ? { rawTx: r.rawTx } : {}),
    ...(r?.proof !== undefined ? { proof: r.proof } : {}),
  };
}

export function parseCreateSignature(res: unknown): { signature: number[] } {
  const r = res as { signature?: number[] } | undefined;
  return { signature: r?.signature ?? (Array.isArray(res) ? (res as number[]) : []) };
}

export function parseInternalizeAction(res: unknown): { accepted: boolean } {
  const accepted = (res as { accepted?: boolean })?.accepted;
  return { accepted: accepted ?? true };
}

```
