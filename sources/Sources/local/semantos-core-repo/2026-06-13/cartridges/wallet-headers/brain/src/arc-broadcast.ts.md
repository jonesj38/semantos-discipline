---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/arc-broadcast.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.646533+00:00
---

# cartridges/wallet-headers/brain/src/arc-broadcast.ts

```ts
// arc-broadcast.ts — POST a raw transaction or BEEF to the ARC miner API.
//
// ARC spec: https://arc.taal.com (POST /v1/tx).
// Accepts either a raw tx (hex in `rawTx` field) or a BEEF blob (same field —
// ARC detects the BEEF magic prefix and resolves the parent chain internally).
// Sending BEEF eliminates "missing inputs" errors for unconfirmed parent chains.
//
// Auth: pass an API key to use the Taal paid tier (Authorization: Bearer <key>).
// When ARC returns 401/403, falls back to WoC broadcast (network transport only —
// all SPV verification uses headers.semantos.me, not WoC).

import { BEEF_V1_MAGIC, BEEF_V2_MAGIC, BEEF_V2_MAGIC_SDK, ATOMIC_BEEF_MAGIC } from './beef-codec';

export interface BroadcastOptions {
  arcUrl?: string;
  apiKey?: string;
}

export interface ArcResponse {
  txid?: string;
  status?: number;
  title?: string;
  detail?: string;
  extraInfo?: string;
}

const WOC_BROADCAST = 'https://api.whatsonchain.com/v1/bsv/main/tx/raw';

function isBeef(tx: Uint8Array): boolean {
  if (tx.length < 4) return false;
  const magic = new DataView(tx.buffer, tx.byteOffset, 4).getUint32(0, true);
  return (
    magic === BEEF_V1_MAGIC ||
    magic === BEEF_V2_MAGIC ||
    magic === BEEF_V2_MAGIC_SDK ||
    magic === ATOMIC_BEEF_MAGIC
  );
}

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function tryArc(
  tx: Uint8Array,
  arcUrl: string,
  apiKey?: string,
): Promise<{ ok: true; txid: string } | { ok: false; reason: string; status?: number }> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (apiKey) headers['Authorization'] = `Bearer ${apiKey}`;

  let res: Response;
  try {
    res = await fetch(`${arcUrl}/v1/tx`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ rawTx: toHex(tx) }),
    });
  } catch (e) {
    return { ok: false, reason: `network error: ${(e as Error).message}` };
  }

  let data: ArcResponse;
  try {
    data = (await res.json()) as ArcResponse;
  } catch {
    return { ok: false, reason: `ARC ${res.status}: non-JSON response`, status: res.status };
  }

  if (res.ok && data.txid) return { ok: true, txid: data.txid };
  const detail = [data.detail ?? data.title ?? `ARC HTTP ${res.status}`, data.extraInfo]
    .filter(Boolean).join(' — ');
  return { ok: false, reason: detail, status: res.status };
}

/**
 * Query ARC for a tx's status (RECEIVED → STORED → ANNOUNCED_TO_NETWORK →
 * SEEN_ON_NETWORK → MINED, or REJECTED). GET /v1/tx/{txid}. Tells us whether an
 * accepted tx actually propagated, vs. just being received.
 */
export async function getArcTxStatus(
  txid: string,
  opts: BroadcastOptions = {},
): Promise<{ ok: boolean; status?: string; blockHeight?: number; detail?: string }> {
  const arcUrl = opts.arcUrl ?? 'https://arc.taal.com';
  const headers: Record<string, string> = {};
  if (opts.apiKey) headers['Authorization'] = `Bearer ${opts.apiKey}`;
  try {
    const res = await fetch(`${arcUrl}/v1/tx/${txid}`, { headers });
    const data = (await res.json()) as { txStatus?: string; blockHeight?: number; extraInfo?: string; detail?: string; title?: string };
    return { ok: res.ok, status: data.txStatus, blockHeight: data.blockHeight, detail: data.extraInfo ?? data.detail ?? data.title };
  } catch (e) {
    return { ok: false, detail: (e as Error).message };
  }
}

async function tryWoc(
  rawTx: Uint8Array,
): Promise<{ ok: true; txid: string } | { ok: false; reason: string }> {
  let res: Response;
  try {
    res = await fetch(WOC_BROADCAST, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ txhex: toHex(rawTx) }),
    });
  } catch (e) {
    return { ok: false, reason: `WoC network error: ${(e as Error).message}` };
  }
  let body: string;
  try {
    body = await res.text();
  } catch {
    return { ok: false, reason: `WoC ${res.status}: unreadable response` };
  }
  // WoC returns a 64-char hex txid as plain text, or a JSON error
  if (res.ok && body.length === 64) return { ok: true, txid: body };
  try {
    const json = JSON.parse(body) as { txid?: string; error?: string };
    if (json.txid) return { ok: true, txid: json.txid };
    return { ok: false, reason: `WoC: ${json.error ?? body}` };
  } catch {
    return { ok: false, reason: `WoC ${res.status}: ${body.slice(0, 120)}` };
  }
}

/**
 * Broadcast a raw tx or BEEF blob to ARC, with WoC fallback on 401/403.
 *
 * Pass the BEEF (not just the raw tx) when the spending tx has an unconfirmed
 * parent — ARC reads the full chain from the BEEF and doesn't need to look up
 * the parent in its own mempool.
 */
export async function broadcastToArc(
  tx: Uint8Array,
  arcUrlOrOpts: string | BroadcastOptions = 'https://arc.taal.com',
): Promise<{ ok: true; txid: string } | { ok: false; reason: string }> {
  const opts: BroadcastOptions =
    typeof arcUrlOrOpts === 'string' ? { arcUrl: arcUrlOrOpts } : arcUrlOrOpts;
  const arcUrl = opts.arcUrl ?? 'https://arc.taal.com';
  const apiKey = opts.apiKey;

  const arcResult = await tryArc(tx, arcUrl, apiKey);
  if (arcResult.ok) return arcResult;

  // Fall back to WoC on auth failure — only works for standard raw tx,
  // not BEEF or EF (WoC only accepts plain hex).
  if ((arcResult.status === 401 || arcResult.status === 403) && !isBeef(tx)) {
    return await tryWoc(tx);
  }

  return { ok: false, reason: arcResult.reason };
}

```
