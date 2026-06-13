---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/chess-submitter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.657774+00:00
---

# cartridges/wallet-headers/brain/src/chess-submitter.ts

```ts
#!/usr/bin/env bun
// chess-submitter — drains the chess payout-intent queue produced by the
// brain's chess_wallet_port, building + signing + (optionally) ARC-
// broadcasting the spend tx for each intent.
//
// Reference:
//   docs/design/CHESS-DOUBLING-CUBE.md §12.6 (reactor safety: broadcast
//     happens HERE, not in the brain's verb path)
//   cartridges/chess/brain/chess_wallet_port.zig (the intent producer;
//     `writeIntent` JSON schema this submitter consumes)
//   cartridges/wallet-headers/brain/src/chess-manifest-export.ts (the
//     anchors manifest with locking_script_hex + beef_hex per anchor)
//
// Usage:
//   bun run src/chess-submitter.ts --data-dir <dir>            # dry-run
//   bun run src/chess-submitter.ts --data-dir <dir> --broadcast # for real
//
// Inputs (under <dir>/chess/):
//   manifest.json     — exported from wallet.html (anchor inventory +
//                       BEEFs + lock scripts; see chess-manifest-export.ts)
//   intents/*.intent.json — one per chess.resolve, written by the brain
//   submitter.sk.hex  — 64-hex (raw 32-byte sk) OR a base58 WIF on a
//                       single line. mode 0600. SAME identity that
//                       minted the anchors (deriveCellAnchorSk needs it).
//
// Outputs (under <dir>/chess/intents/):
//   done/<id>.intent.json — moved here on successful broadcast
//   done/<id>.txid        — sidecar with the ARC txid (hex, BE)
//
// V1 scope:
//   • Drains the queue once and exits (one-shot; cron/systemd for cadence).
//   • Dry-run by default; --broadcast is the explicit on switch.
//   • Kernel `semantos_linear_consume` is NOT called here — V1 relies on
//     on-chain double-spend rejection as the cross-process replay guard.
//     A future iteration may add the WASM-mediated kernel call once the
//     submitter embeds the cell-engine instance. Documented in chess
//     tracker.

import { readFileSync, readdirSync, writeFileSync, renameSync, mkdirSync, existsSync, statSync } from 'node:fs';
import { join } from 'node:path';
import * as secp from '@noble/secp256k1';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { hmac } from '@noble/hashes/hmac';
import { encodeDer } from './der';
import { parseBeef, buildBeefV1ChainedN, computeTxid } from './beef-codec';
import {
  computeSighash,
  serializeEFTx,
  buildP2pkhUnlockScript,
  buildP2pkhLock,
  pubkeyToHash160,
  type TxInput,
  type TxOutput,
} from './tx-builder';
import { deriveCellAnchorSk } from './cell-anchor';
import { broadcastToArc } from './arc-broadcast';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

const FEE_SATS = 200n; // single-input simplicity; multi-input adjusts proportionally

// ── Types matching chess_wallet_port + chess-manifest-export ────────────

interface ManifestAnchor {
  game_id: string;
  color: 'white' | 'black';
  type_hash_hex: string;
  anchor_index: number;
  outpoint: { txid_be: string; vout: number };
  satoshis: number;
  owner_pk_hex: string;
  derived_pk_hex: string;
  locking_script_hex: string;
  beef_hex: string;
}

interface IntentSource {
  outpoint: string; // "txid_be:vout"
  cell_path: string;
}

interface PayoutIntent {
  version: 1;
  intent_id: number;
  owner: 'white' | 'black';
  satoshis: number;
  ts_unix: number;
  sources: IntentSource[];
}

// ── Hex / WIF helpers ──────────────────────────────────────────────────

function hexToBytes(h: string): Uint8Array {
  if (h.length % 2 !== 0) throw new Error(`bad hex length: ${h.length}`);
  const out = new Uint8Array(h.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(h.slice(2 * i, 2 * i + 2), 16);
  }
  return out;
}

function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

/** Reverse big-endian txid hex → little-endian bytes (tx-builder wants LE). */
function beHexToLeBytes(beHex: string): Uint8Array {
  const be = hexToBytes(beHex);
  const le = new Uint8Array(be.length);
  for (let i = 0; i < be.length; i++) le[i] = be[be.length - 1 - i]!;
  return le;
}

/** Minimal base58 decoder for WIF strings. */
const B58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
function base58Decode(s: string): Uint8Array {
  const bytes: number[] = [0];
  for (const ch of s) {
    const v = B58.indexOf(ch);
    if (v < 0) throw new Error(`bad base58 char ${ch}`);
    let carry = v;
    for (let i = 0; i < bytes.length; i++) {
      carry += bytes[i]! * 58;
      bytes[i] = carry & 0xff;
      carry >>= 8;
    }
    while (carry > 0) {
      bytes.push(carry & 0xff);
      carry >>= 8;
    }
  }
  for (const ch of s) if (ch !== '1') break; else bytes.push(0);
  return new Uint8Array(bytes.reverse());
}

function decodeIdentitySk(raw: string): Uint8Array {
  const trim = raw.trim();
  // Heuristic: 64 hex chars ⇒ raw sk; else base58 WIF.
  if (/^[0-9a-fA-F]{64}$/.test(trim)) return hexToBytes(trim);
  const decoded = base58Decode(trim);
  if (decoded.length < 37) throw new Error(`WIF too short: ${decoded.length}`);
  // WIF: 0x80 prefix | 32-byte sk | 0x01 (optional compressed flag) | 4-byte checksum
  const body = decoded.slice(0, decoded.length - 4);
  const checksum = decoded.slice(decoded.length - 4);
  const want = nobleSha256(nobleSha256(body)).slice(0, 4);
  for (let i = 0; i < 4; i++) if (checksum[i] !== want[i]) throw new Error('WIF checksum failed');
  if (body[0] !== 0x80) throw new Error(`WIF version byte ${body[0]?.toString(16)}, expected 0x80`);
  return body.slice(1, 33);
}

// ── Source resolution: intent outpoint → manifest anchor ───────────────

interface ResolvedSource {
  anchor: ManifestAnchor;
  cell_path: string;
}

function indexManifest(m: { anchors: ManifestAnchor[] }): Map<string, ManifestAnchor> {
  const ix = new Map<string, ManifestAnchor>();
  for (const a of m.anchors) ix.set(`${a.outpoint.txid_be}:${a.outpoint.vout}`, a);
  return ix;
}

function resolveSources(intent: PayoutIntent, ix: Map<string, ManifestAnchor>): ResolvedSource[] {
  return intent.sources.map((s) => {
    const a = ix.get(s.outpoint);
    if (!a) throw new Error(`intent ${intent.intent_id}: outpoint ${s.outpoint} not in manifest`);
    return { anchor: a, cell_path: s.cell_path };
  });
}

// ── Spend tx construction ──────────────────────────────────────────────

interface PlannedSpend {
  intent: PayoutIntent;
  recipient_pk_hex: string;
  recipient_address_lock_hex: string;
  total_in: bigint;
  fee: bigint;
  payout_sats: bigint;
  rawTx: Uint8Array;
  txid_be_hex: string;
  beef: Uint8Array;
  sources: ResolvedSource[];
}

/** Recipient pk: from any source anchor whose `color === intent.owner`. In
 *  the V1 single-identity test setup both sides share an identity, so any
 *  source works; in production with two identities the winning side's
 *  anchor carries its own owner_pk. */
function pickRecipientPk(intent: PayoutIntent, sources: ResolvedSource[]): string {
  for (const s of sources) if (s.anchor.color === intent.owner) return s.anchor.owner_pk_hex;
  // Fallback: the first source's owner — covers refund-to-self / draw legs.
  return sources[0]!.anchor.owner_pk_hex;
}

function buildSpend(identitySk: Uint8Array, intent: PayoutIntent, sources: ResolvedSource[]): PlannedSpend {
  const inputs: TxInput[] = sources.map((s) => ({
    txid: beHexToLeBytes(s.anchor.outpoint.txid_be),
    vout: s.anchor.outpoint.vout,
    value: BigInt(s.anchor.satoshis),
    script: hexToBytes(s.anchor.locking_script_hex),
    sequence: 0xffffffff,
  }));
  const total_in = inputs.reduce((acc, i) => acc + i.value, 0n);
  const fee = FEE_SATS;
  // intent.satoshis is the brain's conservation-correct GROSS pot
  // (pre-fee). On-chain we must deduct the miner fee, so the actual
  // payout is total_in - fee. For V1, total_in == intent.satoshis (no
  // augments yet), so the haircut is exactly `fee`. Dust check only.
  if (total_in < fee + 546n) {
    throw new Error(
      `intent ${intent.intent_id}: total_in ${total_in} would dust after fee ${fee}`,
    );
  }
  const payout_sats = total_in - fee;
  const expected_payout = BigInt(intent.satoshis);

  const recipient_pk_hex = pickRecipientPk(intent, sources);
  const recipient_lock = buildP2pkhLock(pubkeyToHash160(hexToBytes(recipient_pk_hex)));
  const outputs: TxOutput[] = [{ script: recipient_lock, satoshis: payout_sats }];

  // Per-input signing.
  const efInputs = inputs.map((inp, i) => {
    const childSk = deriveCellAnchorSk(
      identitySk,
      hexToBytes(sources[i]!.anchor.type_hash_hex),
      sources[i]!.anchor.anchor_index,
    );
    if (!childSk) throw new Error(`intent ${intent.intent_id}: deriveCellAnchorSk null at source ${i}`);
    const digest = computeSighash(inputs, outputs, i);
    const sig = secp.sign(digest, childSk).normalizeS();
    const der = encodeDer(sig.r, sig.s);
    const unlock = buildP2pkhUnlockScript(der, secp.getPublicKey(childSk, true));
    return {
      txid: inp.txid,
      vout: inp.vout,
      unlockScript: unlock,
      sequence: 0xffffffff,
      sourceValue: inp.value,
      sourceLock: inp.script,
    };
  });

  const { rawTx, txid } = serializeEFTx(efInputs, outputs);

  // Chain BEEFs: stack each source's funding BEEF then the spend tx.
  // buildBeefV1ChainedN takes (baseBeef, additionalRawTxs[], finalTxid).
  // For multi-source, we fold each source BEEF into the base, then
  // Dedupe by anchor's parent txid. When multiple inputs come from the
  // same parent tx (the common chess case — both anchors are vouts of
  // the same split tx), one source BEEF carries all the provenance and
  // re-parsing the same blob is wasteful + has tripped parseBeef edges.
  const seenTxids = new Set<string>();
  const distinctBeefs: Uint8Array[] = [];
  for (const s of sources) {
    if (seenTxids.has(s.anchor.outpoint.txid_be)) continue;
    seenTxids.add(s.anchor.outpoint.txid_be);
    distinctBeefs.push(hexToBytes(s.anchor.beef_hex));
  }
  const baseBeef = distinctBeefs[0]!;
  const followups: Uint8Array[] = [];
  for (let i = 1; i < distinctBeefs.length; i++) {
    const parsed = parseBeef(distinctBeefs[i]!);
    for (const tx of parsed.txs) followups.push(tx.rawTx);
  }
  followups.push(rawTx);
  const beef = buildBeefV1ChainedN(baseBeef, followups, txid);

  return {
    intent,
    recipient_pk_hex,
    recipient_address_lock_hex: bytesToHex(recipient_lock),
    total_in,
    fee,
    payout_sats,
    rawTx,
    txid_be_hex: bytesToHex(new Uint8Array(txid).reverse()),
    beef,
    sources,
  };
}

// ── Drain loop ─────────────────────────────────────────────────────────

interface DrainOptions {
  data_dir: string;
  broadcast: boolean;
  arc_url: string;
  arc_api_key?: string;
}

function loadIntents(dir: string): { name: string; path: string; intent: PayoutIntent }[] {
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((n) => n.endsWith('.intent.json'))
    .map((n) => ({ name: n, path: join(dir, n) }))
    .filter((f) => statSync(f.path).isFile())
    .map((f) => ({ ...f, intent: JSON.parse(readFileSync(f.path, 'utf-8')) as PayoutIntent }));
}

function printPlanned(p: PlannedSpend): void {
  console.log(`intent #${p.intent.intent_id} (${p.intent.owner}, ${p.intent.satoshis} sats)`);
  console.log(`  txid_be:    ${p.txid_be_hex}`);
  console.log(`  total_in:   ${p.total_in} sats   fee: ${p.fee}   payout: ${p.payout_sats}`);
  console.log(`  recipient:  ${p.recipient_pk_hex}`);
  console.log(`  inputs (${p.sources.length}):`);
  for (const s of p.sources) {
    console.log(
      `    ${s.anchor.outpoint.txid_be}:${s.anchor.outpoint.vout}  ${s.anchor.satoshis} sats  ${s.anchor.color}  cell=${s.cell_path}`,
    );
  }
}

export async function drainOnce(opts: DrainOptions): Promise<{
  processed: number;
  dryRun: number;
  broadcast: number;
  failed: number;
}> {
  const chess_dir = join(opts.data_dir, 'chess');
  const intents_dir = join(chess_dir, 'intents');
  const done_dir = join(intents_dir, 'done');

  const manifest_path = join(chess_dir, 'manifest.json');
  if (!existsSync(manifest_path)) {
    throw new Error(`manifest not found: ${manifest_path}`);
  }
  const manifest = JSON.parse(readFileSync(manifest_path, 'utf-8')) as { anchors: ManifestAnchor[] };
  const ix = indexManifest(manifest);

  const wif_path = join(chess_dir, 'submitter.sk.hex');
  const wif_alt = join(chess_dir, 'submitter.wif');
  const wif_file = existsSync(wif_path) ? wif_path : existsSync(wif_alt) ? wif_alt : null;
  if (!wif_file) throw new Error(`identity key not found: tried ${wif_path} / ${wif_alt}`);
  const identitySk = decodeIdentitySk(readFileSync(wif_file, 'utf-8'));

  const intents = loadIntents(intents_dir);
  if (intents.length === 0) {
    console.log(`no intents in ${intents_dir}`);
    return { processed: 0, dryRun: 0, broadcast: 0, failed: 0 };
  }
  console.log(`found ${intents.length} intent(s) in ${intents_dir}`);
  console.log(opts.broadcast ? '=== BROADCAST MODE ===' : '=== DRY-RUN (no broadcast) — pass --broadcast to commit ===');

  let dryRun = 0,
    broadcast = 0,
    failed = 0;
  for (const f of intents) {
    try {
      const sources = resolveSources(f.intent, ix);
      const plan = buildSpend(identitySk, f.intent, sources);
      printPlanned(plan);
      if (!opts.broadcast) {
        dryRun++;
        continue;
      }
      const bcast = await broadcastToArc(plan.beef, { arcUrl: opts.arc_url, apiKey: opts.arc_api_key });
      if (!bcast.ok) {
        console.error(`  ✗ ARC broadcast failed: ${bcast.reason}`);
        failed++;
        continue;
      }
      if (!existsSync(done_dir)) mkdirSync(done_dir, { recursive: true });
      const moved = join(done_dir, f.name);
      renameSync(f.path, moved);
      writeFileSync(moved.replace(/\.intent\.json$/, '.txid'), plan.txid_be_hex + '\n');
      console.log(`  ✓ broadcast txid ${bcast.txid ?? plan.txid_be_hex}`);
      broadcast++;
    } catch (e) {
      console.error(`  ✗ intent ${f.name}: ${(e as Error).message}`);
      if ((e as Error).stack) console.error((e as Error).stack);
      failed++;
    }
  }
  return { processed: intents.length, dryRun, broadcast, failed };
}

// ── CLI entry ──────────────────────────────────────────────────────────

function parseArgs(argv: string[]): DrainOptions {
  let data_dir: string | null = null;
  let broadcast = false;
  let arc_url = 'https://arc.taal.com';
  let arc_api_key: string | undefined;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === '--data-dir') data_dir = argv[++i] ?? null;
    else if (a === '--broadcast') broadcast = true;
    else if (a === '--arc-url') arc_url = argv[++i] ?? arc_url;
    else if (a === '--arc-api-key') arc_api_key = argv[++i];
    else if (a === '--help' || a === '-h') {
      console.log('chess-submitter --data-dir <dir> [--broadcast] [--arc-url <url>] [--arc-api-key <key>]');
      process.exit(0);
    }
  }
  if (!data_dir) {
    console.error('error: --data-dir <dir> is required');
    process.exit(2);
  }
  return { data_dir, broadcast, arc_url, arc_api_key };
}

if (import.meta.main) {
  const opts = parseArgs(process.argv.slice(2));
  drainOnce(opts)
    .then((r) => {
      console.log(`done: processed=${r.processed} dryRun=${r.dryRun} broadcast=${r.broadcast} failed=${r.failed}`);
      if (r.failed > 0) process.exit(1);
    })
    .catch((e) => {
      console.error(`fatal: ${(e as Error).message}`);
      process.exit(1);
    });
}

```
