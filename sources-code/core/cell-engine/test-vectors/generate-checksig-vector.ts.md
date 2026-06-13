---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/test-vectors/generate-checksig-vector.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.992740+00:00
---

# core/cell-engine/test-vectors/generate-checksig-vector.ts

```ts
/**
 * Generate a CHECKSIG test vector by manually constructing a signed BSV transaction.
 *
 * Uses @bsv/sdk for key/signature operations only, and manually builds the raw
 * transaction bytes to ensure compatibility with sighash.zig's BIP-143 parser.
 *
 * Run: bun packages/cell-engine/test-vectors/generate-checksig-vector.ts
 */

import { PrivateKey, Hash, Signature, BigNumber } from '@bsv/sdk';
import { writeFileSync } from 'fs';
import { join } from 'path';

// Deterministic key (test fixture, NOT a secret)
const privkey = PrivateKey.fromWif('L1RrrnXkcKut5DEMwtDthjwRcTTwED36thyL1DebVrKuwvohjMNi');
const pubkey = privkey.toPublicKey();
const pubkeyBytes = new Uint8Array(pubkey.toDER());
const pubkeyHash = Hash.hash160(pubkeyBytes);

// ── Build P2PKH locking script ──
// OP_DUP(76) OP_HASH160(a9) OP_PUSH20(14) <20 bytes> OP_EQUALVERIFY(88) OP_CHECKSIG(ac)
const lockScript = new Uint8Array(25);
lockScript[0] = 0x76; // OP_DUP
lockScript[1] = 0xa9; // OP_HASH160
lockScript[2] = 0x14; // OP_PUSHBYTES_20
lockScript.set(new Uint8Array(pubkeyHash), 3);
lockScript[23] = 0x88; // OP_EQUALVERIFY
lockScript[24] = 0xac; // OP_CHECKSIG

// ── Build a funding "transaction" ──
// We just need its txid. Build a minimal valid structure.
const fundingTxVersion = new Uint8Array([0x01, 0x00, 0x00, 0x00]);
const fundingInputCount = new Uint8Array([0x01]);
const fundingPrevTxid = new Uint8Array(32); // coinbase
const fundingPrevVout = new Uint8Array([0xff, 0xff, 0xff, 0xff]);
const fundingScriptSig = new Uint8Array([0x01, 0x00]); // len=1, OP_0
const fundingSequence = new Uint8Array([0xff, 0xff, 0xff, 0xff]);
const fundingOutputCount = new Uint8Array([0x01]);
const fundingValue = new Uint8Array(8);
new DataView(fundingValue.buffer).setBigUint64(0, BigInt(50000), true);
const fundingScriptPubKeyLen = new Uint8Array([lockScript.length]);
const fundingLocktime = new Uint8Array([0x00, 0x00, 0x00, 0x00]);

const fundingTxBin = new Uint8Array([
  ...fundingTxVersion,
  ...fundingInputCount,
  ...fundingPrevTxid, ...fundingPrevVout, ...fundingScriptSig, ...fundingSequence,
  ...fundingOutputCount, ...fundingValue, ...fundingScriptPubKeyLen, ...lockScript,
  ...fundingLocktime,
]);

// Compute funding txid = SHA256D(raw), reversed for display (but NOT for outpoint)
const fundingTxid = Hash.sha256(Hash.sha256(fundingTxBin));

// ── Compute BIP-143 sighash for the spending tx ──
const SIGHASH_ALL_FORKID = 0x41;
const prevoutValue = BigInt(50000);
const sequence = 0xFFFFFFFF;

// hashPrevouts = SHA256D(prevTxid + prevVout)
const prevoutData = new Uint8Array(36);
prevoutData.set(new Uint8Array(fundingTxid), 0);
const pvDv = new DataView(prevoutData.buffer);
pvDv.setUint32(32, 0, true); // vout = 0
const hashPrevouts = Hash.sha256(Hash.sha256(prevoutData));

// hashSequence = SHA256D(nSequence)
const seqData = new Uint8Array(4);
new DataView(seqData.buffer).setUint32(0, sequence, true);
const hashSequence = Hash.sha256(Hash.sha256(seqData));

// hashOutputs: one output: 49000 sats to same lock script
const outValue = new Uint8Array(8);
new DataView(outValue.buffer).setBigUint64(0, BigInt(49000), true);
const outputData = new Uint8Array(8 + 1 + lockScript.length);
outputData.set(outValue, 0);
outputData[8] = lockScript.length; // varint
outputData.set(lockScript, 9);
const hashOutputs = Hash.sha256(Hash.sha256(outputData));

// Build BIP-143 preimage
const preimage = new Uint8Array(4 + 32 + 32 + 32 + 4 + 1 + lockScript.length + 8 + 4 + 32 + 4 + 4);
const pdv = new DataView(preimage.buffer);
let pos = 0;

// 1. nVersion
pdv.setUint32(pos, 1, true); pos += 4;
// 2. hashPrevouts
preimage.set(new Uint8Array(hashPrevouts), pos); pos += 32;
// 3. hashSequence
preimage.set(new Uint8Array(hashSequence), pos); pos += 32;
// 4. outpoint (prev_txid + prev_vout)
preimage.set(new Uint8Array(fundingTxid), pos); pos += 32;
pdv.setUint32(pos, 0, true); pos += 4; // vout=0
// 5. scriptCode (varint + lock script)
preimage[pos] = lockScript.length; pos += 1;
preimage.set(lockScript, pos); pos += lockScript.length;
// 6. value
pdv.setBigUint64(pos, prevoutValue, true); pos += 8;
// 7. nSequence
pdv.setUint32(pos, sequence, true); pos += 4;
// 8. hashOutputs
preimage.set(new Uint8Array(hashOutputs), pos); pos += 32;
// 9. nLocktime
pdv.setUint32(pos, 0, true); pos += 4;
// 10. nHashType
pdv.setUint32(pos, SIGHASH_ALL_FORKID, true); pos += 4;

// SHA256D of preimage = sighash
const sighash = Hash.sha256(Hash.sha256(preimage.subarray(0, pos)));

// ── Sign the sighash ──
const sig = privkey.sign(Array.from(new Uint8Array(sighash)));
const sigDER = new Uint8Array(sig.toDER());

// ── Build unlock script: PUSH<sig+hashtype> PUSH<pubkey> ──
const sigWithHashtype = new Uint8Array([...sigDER, SIGHASH_ALL_FORKID]);
const unlockScript = new Uint8Array(1 + sigWithHashtype.length + 1 + pubkeyBytes.length);
unlockScript[0] = sigWithHashtype.length;
unlockScript.set(sigWithHashtype, 1);
unlockScript[1 + sigWithHashtype.length] = pubkeyBytes.length;
unlockScript.set(pubkeyBytes, 2 + sigWithHashtype.length);

// ── Build raw spending tx ──
const spendingTx = new Uint8Array(
  4 + 1 + 32 + 4 + 1 + unlockScript.length + 4 + 1 + 8 + 1 + lockScript.length + 4
);
const sdv = new DataView(spendingTx.buffer);
let sp = 0;
sdv.setUint32(sp, 1, true); sp += 4; // version
spendingTx[sp] = 1; sp += 1; // input count
spendingTx.set(new Uint8Array(fundingTxid), sp); sp += 32; // prev txid
sdv.setUint32(sp, 0, true); sp += 4; // prev vout
spendingTx[sp] = unlockScript.length; sp += 1; // scriptSig len
spendingTx.set(unlockScript, sp); sp += unlockScript.length;
sdv.setUint32(sp, sequence, true); sp += 4; // sequence
spendingTx[sp] = 1; sp += 1; // output count
sdv.setBigUint64(sp, BigInt(49000), true); sp += 8; // value
spendingTx[sp] = lockScript.length; sp += 1; // scriptPubKey len
spendingTx.set(lockScript, sp); sp += lockScript.length;
sdv.setUint32(sp, 0, true); sp += 4; // locktime

const vector = {
  description: 'Manually-constructed BSV P2PKH spend with BIP-143 sighash',
  lockingScript: Buffer.from(lockScript).toString('hex'),
  unlockingScript: Buffer.from(unlockScript).toString('hex'),
  rawSpendingTx: Buffer.from(spendingTx.subarray(0, sp)).toString('hex'),
  prevoutValue: 50000,
  sequence,
  locktime: 0,
  txVersion: 1,
  sighashPreimage: Buffer.from(preimage.subarray(0, pos)).toString('hex'),
  sighash: Buffer.from(new Uint8Array(sighash)).toString('hex'),
  signature: Buffer.from(sigDER).toString('hex'),
  hashtypeByte: SIGHASH_ALL_FORKID,
  publicKey: Buffer.from(pubkeyBytes).toString('hex'),
  expectedResult: true,
};

const outPath = join(import.meta.dir, 'checksig-p2pkh.json');
writeFileSync(outPath, JSON.stringify(vector, null, 2) + '\n');
console.log('Written to', outPath);
console.log('Lock script:', vector.lockingScript);
console.log('Sighash:', vector.sighash);
console.log('Sig DER len:', sigDER.length);
console.log('Tx size:', sp, 'bytes');

```
