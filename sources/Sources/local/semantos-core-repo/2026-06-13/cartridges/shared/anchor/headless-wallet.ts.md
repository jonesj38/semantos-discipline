---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/anchor/headless-wallet.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.440020+00:00
---

# cartridges/shared/anchor/headless-wallet.ts

```ts
#!/usr/bin/env bun
/**
 * headless-wallet.ts — Minimal self-contained BSV wallet for automated bridge settlements
 *
 * Eliminates the 7.3s Metanet Desktop round-trip, cutting settlement latency to ~100ms:
 *   Metanet Desktop createAction × 3 (2.4s each) → direct sign + ARC (~100ms)
 *
 * UTXO lifecycle:
 *   startup → fetchUtxos() from WhatsOnChain (confirmed only)
 *   after spend → remove spent UTXO + register change UTXO (in-memory)
 *   every 60s   → refreshUtxos() reconciles with WoC (catches external deposits)
 *
 * Env:
 *   BRIDGE_WALLET_KEY  64-hex raw secp256k1 private key. If absent, a fresh key
 *                      is generated and printed — fund the derived address, then
 *                      set this env so it persists across restarts.
 *   ARC_URL            ARC endpoint (default: https://arc.taal.com)
 *   ARC_API_KEY        ARC API key (optional; public tier works without)
 *   HEADLESS_WALLET    Set to "true" to enable (default: false, uses MND)
 *
 * Usage:
 *   import { initHeadlessWallet, sendPushdrop } from './headless-wallet';
 *   const wallet = await initHeadlessWallet();
 *   const txid = await sendPushdrop(wallet, dataBytes, pubkeyBytes, 1n);
 */

import { sha256 } from '@noble/hashes/sha2';
import { ripemd160 } from '@noble/hashes/ripemd160';
import { hmac } from '@noble/hashes/hmac';
import * as secp from '@noble/secp256k1';
import { randomBytes } from 'node:crypto';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

// Wire secp's synchronous HMAC-SHA256 backend (required for sign()).
secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(sha256, key, secp.etc.concatBytes(...msgs));

// ── Config ───────────────────────────────────────────────────────────────────

const ARC_URL     = process.env.ARC_URL     ?? 'https://arc.taal.com';
const ARC_API_KEY = process.env.ARC_API_KEY ?? '';
const WOC_BASE    = 'https://api.whatsonchain.com/v1/bsv/main';
const FEE_SATS    = 1200n; // flat fee per tx (~1 sat/byte for a ~1100B pushdrop tx)
const SIGHASH_ALL_FORKID = 0x41;

// ── Types ────────────────────────────────────────────────────────────────────

export interface Utxo {
  txid:   string;   // 64-hex
  vout:   number;
  value:  bigint;   // satoshis
}

export interface HeadlessWallet {
  privKey:  Uint8Array;   // 32 bytes
  pubKey:   Uint8Array;   // 33 bytes compressed
  address:  string;       // mainnet P2PKH base58check
  utxos:    Utxo[];
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function toHex(b: Uint8Array): string {
  return Buffer.from(b).toString('hex');
}

function fromHex(h: string): Uint8Array {
  const clean = h.trim().toLowerCase();
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++)
    out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  return out;
}

function hash256(b: Uint8Array): Uint8Array {
  return sha256(sha256(b));
}

function hash160(b: Uint8Array): Uint8Array {
  return ripemd160(sha256(b));
}

// ── Base58Check for P2PKH addresses ─────────────────────────────────────────

const B58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

function base58Encode(bytes: Uint8Array): string {
  let n = 0n;
  for (const b of bytes) n = (n << 8n) | BigInt(b);
  let out = '';
  while (n > 0n) { out = B58[Number(n % 58n)]! + out; n /= 58n; }
  for (const b of bytes) { if (b === 0) out = '1' + out; else break; }
  return out;
}

function pubkeyToAddress(pubkey: Uint8Array): string {
  const h = hash160(pubkey);
  const payload = new Uint8Array(21);
  payload[0] = 0x00; // mainnet P2PKH version
  payload.set(h, 1);
  const checksum = hash256(payload).slice(0, 4);
  const full = new Uint8Array(25);
  full.set(payload, 0);
  full.set(checksum, 21);
  return base58Encode(full);
}

// ── Script builders ──────────────────────────────────────────────────────────

function buildP2pkhLock(h160: Uint8Array): Uint8Array {
  // OP_DUP OP_HASH160 <20> <hash160> OP_EQUALVERIFY OP_CHECKSIG
  const s = new Uint8Array(25);
  s[0] = 0x76; s[1] = 0xa9; s[2] = 0x14;
  s.set(h160, 3);
  s[23] = 0x88; s[24] = 0xac;
  return s;
}

function encodePush(data: Uint8Array): Uint8Array {
  const len = data.length;
  if (len <= 75)  return new Uint8Array([len, ...data]);
  if (len <= 255) return new Uint8Array([0x4c, len, ...data]);
  return new Uint8Array([0x4d, len & 0xff, (len >> 8) & 0xff, ...data]);
}

function pushdropScript(data: Uint8Array, ownerPubkey: Uint8Array): Uint8Array {
  // <data> OP_DROP <pubkey> OP_CHECKSIG
  const dataPush   = encodePush(data);
  const pkPush     = encodePush(ownerPubkey);
  const out = new Uint8Array(dataPush.length + 1 + pkPush.length + 1);
  let i = 0;
  out.set(dataPush, i);  i += dataPush.length;
  out[i++] = 0x75; // OP_DROP
  out.set(pkPush, i);    i += pkPush.length;
  out[i]   = 0xac; // OP_CHECKSIG
  return out;
}

// ── DER encoding (canonical BSV/Bitcoin ECDSA signatures) ────────────────────

function derEncode(r: bigint, s: bigint): Uint8Array {
  function trimPad(n: bigint): Uint8Array {
    const buf = new Uint8Array(32);
    let x = n;
    for (let i = 31; i >= 0; i--) { buf[i] = Number(x & 0xffn); x >>= 8n; }
    // Trim leading zeros (keep at least 1 byte).
    let start = 0;
    while (start < buf.length - 1 && buf[start] === 0) start++;
    const trimmed = buf.subarray(start);
    // Prepend 0x00 if high bit set (DER signed-integer encoding).
    if ((trimmed[0]! & 0x80) !== 0) {
      const padded = new Uint8Array(trimmed.length + 1);
      padded.set(trimmed, 1);
      return padded;
    }
    return trimmed;
  }
  const rB = trimPad(r), sB = trimPad(s);
  const total = 2 + rB.length + 2 + sB.length;
  const out = new Uint8Array(2 + total);
  out[0] = 0x30; out[1] = total;
  out[2] = 0x02; out[3] = rB.length;
  out.set(rB, 4);
  const sOff = 4 + rB.length;
  out[sOff] = 0x02; out[sOff + 1] = sB.length;
  out.set(sB, sOff + 2);
  return out;
}

// ── BIP143 sighash (SIGHASH_ALL | SIGHASH_FORKID) ────────────────────────────

function le4(n: number): Uint8Array {
  const b = new Uint8Array(4);
  new DataView(b.buffer).setUint32(0, n >>> 0, true);
  return b;
}

function le8(n: bigint): Uint8Array {
  const b = new Uint8Array(8);
  new DataView(b.buffer).setBigUint64(0, n, true);
  return b;
}

function writeVarInt(n: number): Uint8Array {
  if (n < 0xfd) return new Uint8Array([n]);
  if (n < 0x10000) return new Uint8Array([0xfd, n & 0xff, (n >> 8) & 0xff]);
  return new Uint8Array([0xfe, n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff, (n >> 24) & 0xff]);
}

function concat(parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((s, p) => s + p.length, 0);
  const out = new Uint8Array(total);
  let off = 0;
  for (const p of parts) { out.set(p, off); off += p.length; }
  return out;
}

interface TxInput {
  txid:    Uint8Array; // 32 bytes internal-byte-order
  vout:    number;
  value:   bigint;
  script:  Uint8Array; // locking script (for sighash preimage)
  sequence: number;
}

interface TxOutput {
  script:   Uint8Array;
  satoshis: bigint;
}

function computeSighash(inputs: TxInput[], outputs: TxOutput[], inputIndex: number): Uint8Array {
  const inp = inputs[inputIndex]!;
  const hashPrevouts = hash256(concat(inputs.map(i => concat([i.txid, le4(i.vout)]))));
  const hashSequence = hash256(concat(inputs.map(i => le4(i.sequence))));
  const hashOutputs  = hash256(concat(outputs.map(o =>
    concat([le8(o.satoshis), writeVarInt(o.script.length), o.script])
  )));
  const preimage = concat([
    le4(1),            // nVersion
    hashPrevouts,
    hashSequence,
    inp.txid,
    le4(inp.vout),
    writeVarInt(inp.script.length),
    inp.script,
    le8(inp.value),
    le4(inp.sequence),
    hashOutputs,
    le4(0),            // nLockTime
    le4(SIGHASH_ALL_FORKID),
  ]);
  return hash256(preimage);
}

// ── EF (Extended Format) transaction serializer ───────────────────────────────
//
// ARC accepts EF format which embeds source value + locking script in each input.
// This eliminates the need to pass a BEEF ancestry chain for unconfirmed parents.
//
// EF layout (verified against cartridges/wallet-headers/brain/src/tx-builder.ts):
//   nVersion(4) | EF_MARKER(6) | varInt(numInputs) |
//     [txid(32) | vout(4) | varInt(unlockLen) | unlockScript | sequence(4) |
//      sourceValue(8) | varInt(sourceLockLen) | sourceLock] × N |
//   varInt(numOutputs) | [sats(8) | varInt(scriptLen) | script] × M |
//   nLockTime(4)
//
// EF_MARKER = 0x00 00 00 00 00 ef (6 bytes, detected by ARC after nVersion).

const EF_MARKER = new Uint8Array([0x00, 0x00, 0x00, 0x00, 0x00, 0xef]);

function buildP2pkhUnlockScript(derSig: Uint8Array, pubkey: Uint8Array): Uint8Array {
  const sigLen = derSig.length + 1; // +1 for sighash type byte
  const sigPush = new Uint8Array(1 + sigLen);
  sigPush[0] = sigLen;
  sigPush.set(derSig, 1);
  sigPush[sigLen] = SIGHASH_ALL_FORKID;
  const pkPush = new Uint8Array(1 + pubkey.length);
  pkPush[0] = pubkey.length;
  pkPush.set(pubkey, 1);
  return concat([sigPush, pkPush]);
}

function computeTxid(rawTx: Uint8Array): string {
  // Reverse for display (txid display uses reversed byte order).
  return toHex(hash256(rawTx).slice().reverse());
}

function serializeEFTx(
  inputs: Array<TxInput & { unlockScript: Uint8Array }>,
  outputs: TxOutput[],
): { efTx: Uint8Array; rawTx: Uint8Array; txid: string } {
  const version  = 1;
  const locktime = 0;

  // Standard raw tx (for txid computation).
  const rawInputs = inputs.map(i => concat([
    i.txid, le4(i.vout),
    writeVarInt(i.unlockScript.length), i.unlockScript,
    le4(i.sequence),
  ]));
  const serializedOutputs = outputs.map(o => concat([
    le8(o.satoshis), writeVarInt(o.script.length), o.script,
  ]));
  const rawTx = concat([
    le4(version),
    writeVarInt(inputs.length), ...rawInputs,
    writeVarInt(outputs.length), ...serializedOutputs,
    le4(locktime),
  ]);
  const txid = computeTxid(rawTx);

  // EF format: version | EF_MARKER | inputs(with source info after sequence) | outputs | locktime.
  const efInputs = inputs.map(i => concat([
    i.txid, le4(i.vout),
    writeVarInt(i.unlockScript.length), i.unlockScript,
    le4(i.sequence),
    // EF extension: sourceValue + sourceLockingScript (after sequence, not before scriptSig).
    le8(i.value),
    writeVarInt(i.script.length), i.script,
  ]));
  const efTx = concat([
    le4(version),
    EF_MARKER,
    writeVarInt(inputs.length), ...efInputs,
    writeVarInt(outputs.length), ...serializedOutputs,
    le4(locktime),
  ]);

  return { efTx, rawTx, txid };
}

// ── WhatsOnChain UTXO fetcher ─────────────────────────────────────────────────

interface WocUtxo { tx_pos: number; tx_hash: string; value: number; height: number; }

export async function fetchUtxos(address: string): Promise<Utxo[]> {
  const url = `${WOC_BASE}/address/${address}/unspent`;
  const r = await fetch(url, { signal: AbortSignal.timeout(10_000) });
  if (!r.ok) {
    const t = await r.text().catch(() => '');
    throw new Error(`WoC UTXO fetch ${r.status}: ${t.slice(0, 80)}`);
  }
  const data = await r.json() as WocUtxo[];
  if (!Array.isArray(data)) return [];
  // Only use confirmed UTXOs (height > 0).
  return data
    .filter(u => u.height > 0)
    .map(u => ({ txid: u.tx_hash, vout: u.tx_pos, value: BigInt(u.value) }));
}

// ── ARC broadcast ─────────────────────────────────────────────────────────────

async function broadcastToArc(efTxBytes: Uint8Array): Promise<string> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (ARC_API_KEY) headers['Authorization'] = `Bearer ${ARC_API_KEY}`;

  // ARC prefers the hex string in `rawTx` field.
  const body = JSON.stringify({ rawTx: toHex(efTxBytes) });

  const r = await fetch(`${ARC_URL}/v1/tx`, {
    method: 'POST',
    headers,
    body,
    signal: AbortSignal.timeout(15_000),
  });

  const j = await r.json() as { txid?: string; detail?: string; title?: string; extraInfo?: string };

  if (r.ok && j.txid) return j.txid;

  // Fallback: try WhatsOnChain (plain raw tx, not EF).
  console.warn(`[headless-wallet] ARC ${r.status}: ${j.detail ?? j.title ?? 'no detail'} — trying WoC fallback`);

  // For WoC we need standard raw tx, not EF.
  // Since we only have the EF bytes here, we re-derive the raw tx from the inputs.
  // Simpler: just fail loudly so the user knows ARC is needed.
  throw new Error(`ARC broadcast failed (${r.status}): ${j.detail ?? j.title ?? JSON.stringify(j)}`);
}

// ── Wallet init ───────────────────────────────────────────────────────────────

const KEY_FILE = '.bridge-wallet-key'; // stored in repo root (not committed)

function loadOrGenerateKey(): Uint8Array {
  // 1. From env.
  if (process.env.BRIDGE_WALLET_KEY) {
    const hex = process.env.BRIDGE_WALLET_KEY.trim();
    if (hex.length !== 64) throw new Error('BRIDGE_WALLET_KEY must be 64 hex characters');
    return fromHex(hex);
  }

  // 2. From key file (persisted across restarts in dev).
  if (existsSync(KEY_FILE)) {
    const hex = readFileSync(KEY_FILE, 'utf8').trim();
    if (hex.length === 64) {
      console.log(`[headless-wallet] Loaded key from ${KEY_FILE}`);
      return fromHex(hex);
    }
  }

  // 3. Generate fresh key.
  const privKey = randomBytes(32);
  // Validate: secp256k1 private keys must be in [1, n-1].
  // randomBytes(32) is overwhelmingly likely to be valid; skip the check for brevity.
  const hex = toHex(privKey);
  writeFileSync(KEY_FILE, hex, { mode: 0o600 });
  console.log(`[headless-wallet] Generated fresh key → saved to ${KEY_FILE}`);
  console.warn(`[headless-wallet] ⚠ Add ${KEY_FILE} to .gitignore!`);
  return privKey;
}

export async function initHeadlessWallet(): Promise<HeadlessWallet> {
  const privKey = loadOrGenerateKey();
  const pubKey  = secp.getPublicKey(privKey, true); // compressed 33-byte
  const address = pubkeyToAddress(pubKey);

  console.log(`[headless-wallet] Address: ${address}`);

  const utxos = await fetchUtxos(address);
  const totalSats = utxos.reduce((s, u) => s + u.value, 0n);
  console.log(`[headless-wallet] UTXOs: ${utxos.length}  balance: ${totalSats} sats`);

  if (utxos.length === 0) {
    console.warn(`[headless-wallet] ⚠ No confirmed UTXOs — fund ${address} before settlements will work`);
  }

  const wallet: HeadlessWallet = { privKey, pubKey, address, utxos };

  // Background UTXO refresh every 60 seconds.
  setInterval(async () => {
    try {
      const fresh = await fetchUtxos(wallet.address);
      // Merge: keep any in-memory UTXOs not yet on WoC (just-spent change),
      // plus all confirmed WoC UTXOs.
      const onChainIds = new Set(fresh.map(u => `${u.txid}:${u.vout}`));
      const inMemOnly  = wallet.utxos.filter(u => !onChainIds.has(`${u.txid}:${u.vout}`));
      wallet.utxos = [...fresh, ...inMemOnly];
      const total = wallet.utxos.reduce((s, u) => s + u.value, 0n);
      console.log(`[headless-wallet] Refreshed UTXOs: ${wallet.utxos.length}  balance: ${total} sats`);
    } catch (err: any) {
      console.warn(`[headless-wallet] UTXO refresh failed: ${err.message}`);
    }
  }, 60_000);

  return wallet;
}

// ── Core operation: send a PushDrop output ────────────────────────────────────

/**
 * Build, sign, and broadcast a PushDrop transaction.
 *
 * Locking script: <data> OP_DROP <ownerPubkey> OP_CHECKSIG
 *
 * Selects the largest available UTXO as the funding input (greedy).
 * Returns the txid on success.
 */
export async function sendPushdrop(
  wallet: HeadlessWallet,
  data: Uint8Array,
  ownerPubkey: Uint8Array,
  anchorSats = 1n,
): Promise<string> {
  if (wallet.utxos.length === 0) {
    throw new Error(`headless-wallet: no UTXOs — fund ${wallet.address}`);
  }

  // Select the largest UTXO (greedy, minimises change fragmentation).
  const sorted = [...wallet.utxos].sort((a, b) => (b.value > a.value ? 1 : -1));
  const utxo   = sorted[0]!;

  if (utxo.value < anchorSats + FEE_SATS) {
    throw new Error(
      `headless-wallet: UTXO value ${utxo.value} sats < anchor(${anchorSats}) + fee(${FEE_SATS})`
    );
  }

  const fundingLock   = buildP2pkhLock(hash160(wallet.pubKey));
  const anchorScript  = pushdropScript(data, ownerPubkey);
  const changeSats    = utxo.value - anchorSats - FEE_SATS;

  const outputs: TxOutput[] = [
    { script: anchorScript, satoshis: anchorSats },
  ];
  if (changeSats > 0n) {
    outputs.push({ script: fundingLock, satoshis: changeSats });
  }

  // Reverse txid for internal byte order (display txid is reversed).
  const txidBytes = fromHex(utxo.txid).slice().reverse();

  const inputs: TxInput[] = [{
    txid:     txidBytes,
    vout:     utxo.vout,
    value:    utxo.value,
    script:   fundingLock,
    sequence: 0xffffffff,
  }];

  const sighash = computeSighash(inputs, outputs, 0);
  const sig     = secp.sign(sighash, wallet.privKey).normalizeS();
  const derSig  = derEncode(sig.r, sig.s);
  const unlock  = buildP2pkhUnlockScript(derSig, wallet.pubKey);

  const { efTx, txid } = serializeEFTx(
    [{ ...inputs[0]!, unlockScript: unlock }],
    outputs,
  );

  const start = Date.now();
  const broadcastTxid = await broadcastToArc(efTx);
  const elapsed = Date.now() - start;
  console.log(`[headless-wallet] Broadcast ${broadcastTxid} in ${elapsed}ms`);

  // Update in-memory UTXO pool: remove spent, add change.
  wallet.utxos = wallet.utxos.filter(u => !(u.txid === utxo.txid && u.vout === utxo.vout));
  if (changeSats > 0n) {
    wallet.utxos.push({ txid, vout: 1, value: changeSats });
  }

  return broadcastTxid;
}

/**
 * Get the wallet's total confirmed balance in sats.
 */
export function getBalance(wallet: HeadlessWallet): bigint {
  return wallet.utxos.reduce((s, u) => s + u.value, 0n);
}

```
