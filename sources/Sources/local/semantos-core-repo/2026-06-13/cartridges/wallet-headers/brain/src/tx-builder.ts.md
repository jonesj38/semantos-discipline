---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/tx-builder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.662641+00:00
---

# cartridges/wallet-headers/brain/src/tx-builder.ts

```ts
// BSV raw-transaction builder with BIP143/SIGHASH_FORKID signing.
//
// BSV uses SIGHASH_ALL|SIGHASH_FORKID (0x41) for all inputs since the
// November 2018 hard-fork. The preimage is the BIP143 serialisation
// with the UTXO value included, so no miner look-up is needed at
// verification time — everything required is in the BEEF.

import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { ripemd160 as nobleRipemd160 } from '@noble/hashes/ripemd160';
import { concat, hash256, writeVarInt, computeTxid } from './beef-codec';

export const SIGHASH_ALL_FORKID = 0x41; // SIGHASH_ALL | SIGHASH_FORKID

// ── Sighash preimage (BIP143 with nValue) ────────────────────────────

export interface TxInput {
  txid: Uint8Array;   // 32 bytes, internal byte order
  vout: number;
  value: bigint;      // satoshis of the UTXO being spent
  script: Uint8Array; // locking script (scriptCode)
  sequence: number;   // default 0xffffffff
}

export interface TxOutput {
  script: Uint8Array;
  satoshis: bigint;
}

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

/**
 * The BIP143 sighash PREIMAGE bytes (before the final double-SHA256).
 *
 * This is exactly what an OP_PUSH_TX covenant pushes onto the stack and
 * introspects: a script can OP_SPLIT it to read `hashOutputs` (to bind the
 * spend's outputs) or the `scriptCode` (to read the cell's current state).
 * `computeSighash` is just `hash256` of this.
 */
export function buildSighashPreimage(
  inputs: TxInput[],
  outputs: TxOutput[],
  inputIndex: number,
  version = 1,
  locktime = 0,
): Uint8Array {
  const inp = inputs[inputIndex]!;
  const hashPrevouts = hash256(concat(inputs.map(i => concat([i.txid, le4(i.vout)]))));
  const hashSequence = hash256(concat(inputs.map(i => le4(i.sequence))));
  const hashOutputs = hash256(
    concat(outputs.map(o => concat([le8(o.satoshis), writeVarInt(o.script.length), o.script]))),
  );
  return concat([
    le4(version),
    hashPrevouts,
    hashSequence,
    inp.txid,
    le4(inp.vout),
    writeVarInt(inp.script.length),
    inp.script,
    le8(inp.value),
    le4(inp.sequence),
    hashOutputs,
    le4(locktime),
    le4(SIGHASH_ALL_FORKID),
  ]);
}

export function computeSighash(
  inputs: TxInput[],
  outputs: TxOutput[],
  inputIndex: number,
  version = 1,
  locktime = 0,
): Uint8Array {
  return hash256(buildSighashPreimage(inputs, outputs, inputIndex, version, locktime));
}

// ── P2PKH unlocking script builder ───────────────────────────────────

/** Build the scriptSig for a P2PKH input:
 *  <pushdata sig+sighash> <pushdata pubkey> */
export function buildP2pkhUnlockScript(derSig: Uint8Array, pubkey: Uint8Array): Uint8Array {
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

// ── Raw transaction serializer ────────────────────────────────────────

export interface SerializedTx {
  rawTx: Uint8Array;
  txid: Uint8Array;
}

export function serializeRawTx(
  inputs: Array<{ txid: Uint8Array; vout: number; unlockScript: Uint8Array; sequence: number }>,
  outputs: TxOutput[],
  version = 1,
  locktime = 0,
): SerializedTx {
  const parts: Uint8Array[] = [le4(version)];

  parts.push(writeVarInt(inputs.length));
  for (const inp of inputs) {
    parts.push(inp.txid);
    parts.push(le4(inp.vout));
    parts.push(writeVarInt(inp.unlockScript.length));
    parts.push(inp.unlockScript);
    parts.push(le4(inp.sequence));
  }

  parts.push(writeVarInt(outputs.length));
  for (const out of outputs) {
    parts.push(le8(out.satoshis));
    parts.push(writeVarInt(out.script.length));
    parts.push(out.script);
  }

  parts.push(le4(locktime));

  const rawTx = concat(parts);
  return { rawTx, txid: computeTxid(rawTx) };
}

// ── Extended Format (EF) serializer ──────────────────────────────────
//
// EF adds a 6-byte marker after the version number and appends
// { satoshis(8) | scriptLen(varint) | lockScript } after each input's
// sequence field, so ARC can validate signatures without a UTXO lookup.
// The txid is always computed from the standard (non-EF) bytes.

// 6-byte EF marker: 00 00 00 00 00 EF
const EF_MARKER = new Uint8Array([0x00, 0x00, 0x00, 0x00, 0x00, 0xef]);

export interface EFInput {
  txid: Uint8Array;
  vout: number;
  unlockScript: Uint8Array;
  sequence: number;
  sourceValue: bigint;    // satoshis of the UTXO being spent
  sourceLock: Uint8Array; // locking script of the UTXO being spent
}

export interface EFSerializedTx {
  efTx: Uint8Array;  // EF-format bytes — send to ARC
  rawTx: Uint8Array; // standard bytes — use for BEEF chains and txid
  txid: Uint8Array;
}

export function serializeEFTx(
  inputs: EFInput[],
  outputs: TxOutput[],
  version = 1,
  locktime = 0,
): EFSerializedTx {
  // Standard raw tx (for BEEF ancestry and txid).
  const stdInputs = inputs.map(i => ({
    txid: i.txid, vout: i.vout, unlockScript: i.unlockScript, sequence: i.sequence,
  }));
  const { rawTx, txid } = serializeRawTx(stdInputs, outputs, version, locktime);

  // EF tx (for ARC broadcast).
  const parts: Uint8Array[] = [le4(version), EF_MARKER];
  parts.push(writeVarInt(inputs.length));
  for (const inp of inputs) {
    parts.push(inp.txid);
    parts.push(le4(inp.vout));
    parts.push(writeVarInt(inp.unlockScript.length));
    parts.push(inp.unlockScript);
    parts.push(le4(inp.sequence));
    parts.push(le8(inp.sourceValue));
    parts.push(writeVarInt(inp.sourceLock.length));
    parts.push(inp.sourceLock);
  }
  parts.push(writeVarInt(outputs.length));
  for (const out of outputs) {
    parts.push(le8(out.satoshis));
    parts.push(writeVarInt(out.script.length));
    parts.push(out.script);
  }
  parts.push(le4(locktime));

  return { efTx: concat(parts), rawTx, txid };
}

// ── P2PKH locking script ──────────────────────────────────────────────

export function buildP2pkhLock(hash160: Uint8Array): Uint8Array {
  const s = new Uint8Array(25);
  s[0] = 0x76; s[1] = 0xa9; s[2] = 0x14;
  s.set(hash160, 3);
  s[23] = 0x88; s[24] = 0xac;
  return s;
}

export function pubkeyToHash160(pubkey: Uint8Array): Uint8Array {
  return nobleRipemd160(nobleSha256(pubkey));
}

```
