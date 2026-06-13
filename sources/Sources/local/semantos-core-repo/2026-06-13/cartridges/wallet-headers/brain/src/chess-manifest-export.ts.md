---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/chess-manifest-export.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.656198+00:00
---

# cartridges/wallet-headers/brain/src/chess-manifest-export.ts

```ts
// chess-manifest-export — build the JSON manifest the brain ingests
// to populate `chess_wallet_port.Manifest`.
//
// Reference:
//   cartridges/chess/brain/chess_wallet_port.zig (loadManifestJson —
//     the brain-side reader; the schema below MUST match what that
//     parser expects, field-for-field, hex length-for-length)
//   cartridges/wallet-headers/brain/src/test-chess-stake.ts (the
//     mint path that wrote these records to outputStore)
//
// What this does:
//
//   Pulls every UNSPENT cell-anchor tagged `['chess','stake',…]` from
//   the wallet's outputStore, normalises the on-disk shape (bigint
//   sats, LE txid, byte pubkeys, byte typeHash) into the JSON layout
//   the brain reads. Each anchor's `game_id` and `color` come from
//   the tag list (test-chess-stake.ts wrote tags
//   `['chess','stake',<color>,<gameId>]`).
//
//   No I/O beyond `outputStore.listOutputs` — caller chooses how to
//   surface the result (download, postMessage to brain, etc.).

import { outputStore, type OutputRecord } from './output-store';

interface ChessManifestAnchor {
  game_id: string;
  color: 'white' | 'black';
  type_hash_hex: string; // 64 hex (32 bytes)
  anchor_index: number;
  outpoint: { txid_be: string; vout: number }; // txid_be is big-endian (block-explorer) hex
  satoshis: number;
  owner_pk_hex: string; // 66 hex (33 bytes)
  derived_pk_hex: string; // 66 hex (33 bytes)
  /** Submitter-only fields. The brain parser ignores them; the headless
   *  chess-submitter consumes them to build + sign + ARC-broadcast the
   *  spend tx without any IndexedDB / wallet-UI dependency. */
  locking_script_hex: string; // P2PKH lock on derived_pk
  beef_hex: string; // funding BEEF proving the anchor UTXO is real on chain
}

interface ChessManifest {
  version: 1;
  anchors: ChessManifestAnchor[];
}

function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

/** Wallet stores txid in LE (Bitcoin internal); explorers display BE.
 *  The brain parser's `txid_be` field expects the BE hex, so reverse. */
function leTxidToBeHex(le: Uint8Array): string {
  const rev = new Uint8Array(le.length);
  for (let i = 0; i < le.length; i++) rev[i] = le[le.length - 1 - i]!;
  return bytesToHex(rev);
}

function pickColor(tags: string[]): 'white' | 'black' | null {
  if (tags.includes('white')) return 'white';
  if (tags.includes('black')) return 'black';
  return null;
}

/** Extract the gameId from the chess tag list. test-chess-stake.ts
 *  writes tags exactly as `['chess','stake',<color>,<gameId>]`, so the
 *  gameId is the first non-keyword tag. */
function pickGameId(tags: string[]): string | null {
  const keywords = new Set(['chess', 'stake', 'augment', 'white', 'black']);
  for (const t of tags) if (!keywords.has(t)) return t;
  return null;
}

function isChessStake(rec: OutputRecord): boolean {
  return rec.basket === 'cell-anchors' &&
    rec.tags.includes('chess') &&
    rec.tags.includes('stake');
}

/** Build the manifest. Optional `gameId` filters to anchors for one game. */
export async function buildChessManifest(gameId?: string): Promise<ChessManifest> {
  const all = await outputStore.listOutputs({ basket: 'cell-anchors', status: 'unspent' });
  const anchors: ChessManifestAnchor[] = [];
  for (const rec of all) {
    if (!isChessStake(rec)) continue;
    if (!rec.typeHash) continue; // chess anchors carry one
    const color = pickColor(rec.tags);
    const gid = pickGameId(rec.tags);
    if (!color || !gid) continue;
    if (gameId && gid !== gameId) continue;
    anchors.push({
      game_id: gid,
      color,
      type_hash_hex: bytesToHex(rec.typeHash),
      anchor_index: Number(rec.derivationContext.index),
      outpoint: { txid_be: leTxidToBeHex(rec.outpoint.txid), vout: rec.outpoint.vout },
      satoshis: Number(rec.satoshis),
      owner_pk_hex: bytesToHex(rec.derivationContext.counterparty),
      derived_pk_hex: bytesToHex(rec.derivedKeyHash),
      locking_script_hex: bytesToHex(rec.lockingScript),
      beef_hex: bytesToHex(rec.beef),
    });
  }
  return { version: 1, anchors };
}

/** Pretty-printed JSON, ready to feed `chess_wallet_port.loadManifestJson`. */
export async function buildChessManifestJson(gameId?: string): Promise<string> {
  const m = await buildChessManifest(gameId);
  return JSON.stringify(m, null, 2);
}

```
