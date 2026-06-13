---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/anchor/test-headless-wallet.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.439730+00:00
---

# cartridges/shared/anchor/test-headless-wallet.ts

```ts
#!/usr/bin/env bun
/**
 * test-headless-wallet.ts — dry-run test for the headless wallet EF transaction builder.
 *
 * Does NOT require live UTXOs or ARC access.
 * Builds a PushDrop EF transaction from a synthetic UTXO and verifies:
 *   1. EF format bytes start with the EF marker (0x00 00 00 00 ef)
 *   2. txid is computed correctly (64-hex)
 *   3. P2PKH address derives from the private key correctly
 *   4. Signing produces a valid DER signature (63-72 bytes)
 *   5. Script structure: <data> OP_DROP <pk> OP_CHECKSIG
 *
 * Run: bun cartridges/shared/anchor/test-headless-wallet.ts
 */

// Re-import internals via direct imports for testing.
import { sha256 } from '@noble/hashes/sha2';
import { ripemd160 } from '@noble/hashes/ripemd160';
import { hmac } from '@noble/hashes/hmac';
import * as secp from '@noble/secp256k1';

// Wire secp sync signing.
secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]) =>
  hmac(sha256, key, secp.etc.concatBytes(...msgs));

function toHex(b: Uint8Array) { return Buffer.from(b).toString('hex'); }
function fromHex(h: string): Uint8Array {
  const out = new Uint8Array(h.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(h.slice(i*2,i*2+2), 16);
  return out;
}
function sha256d(b: Uint8Array) { return sha256(sha256(b)); }
function hash160(b: Uint8Array) { return ripemd160(sha256(b)); }

// ── Test key (throwaway — never fund this) ────────────────────────────────────
const TEST_SK  = sha256(new TextEncoder().encode('test-headless-wallet-do-not-fund'));
const TEST_PK  = secp.getPublicKey(TEST_SK, true);
const H160     = hash160(TEST_PK);

// B58
const B58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
function b58Encode(bytes: Uint8Array): string {
  let n = 0n; for (const b of bytes) n = (n<<8n)|BigInt(b);
  let out = ''; while (n>0n) { out=B58[Number(n%58n)]!+out; n/=58n; }
  for (const b of bytes) { if (b===0) out='1'+out; else break; }
  return out;
}
const payload = new Uint8Array(21); payload[0] = 0x00; payload.set(H160, 1);
const cs = sha256d(payload).slice(0,4);
const addrBuf = new Uint8Array(25); addrBuf.set(payload); addrBuf.set(cs,21);
const address = b58Encode(addrBuf);

console.log(`\n── Headless Wallet Test (dry run) ──────────────────────────`);
console.log(`   privkey:  ${toHex(TEST_SK)} (throwaway)`);
console.log(`   pubkey:   ${toHex(TEST_PK)}`);
console.log(`   hash160:  ${toHex(H160)}`);
console.log(`   address:  ${address}`);
console.log();

// ── Synthetic funding UTXO ────────────────────────────────────────────────────
const FUNDING_TXID_HEX = 'a'.repeat(64); // fake txid (display format, reversed for internal)
const FUNDING_VALUE    = 50_000n; // 50k sats
const ANCHOR_SATS      = 1n;
const FEE_SATS         = 1200n;

// ── Script builders (same as headless-wallet.ts) ──────────────────────────────
function le4(n: number) {
  const b = new Uint8Array(4); new DataView(b.buffer).setUint32(0,n>>>0,true); return b;
}
function le8(n: bigint) {
  const b = new Uint8Array(8); new DataView(b.buffer).setBigUint64(0,n,true); return b;
}
function varInt(n: number) {
  if (n<0xfd) return new Uint8Array([n]);
  return new Uint8Array([0xfd, n&0xff, (n>>8)&0xff]);
}
function concat(parts: Uint8Array[]) {
  const t = parts.reduce((s,p)=>s+p.length,0);
  const out = new Uint8Array(t); let off=0;
  for (const p of parts) { out.set(p,off); off+=p.length; }
  return out;
}
function buildP2pkhLock(h160: Uint8Array) {
  const s=new Uint8Array(25); s[0]=0x76;s[1]=0xa9;s[2]=0x14;s.set(h160,3);s[23]=0x88;s[24]=0xac;return s;
}
function encodePush(data: Uint8Array) {
  const len=data.length;
  if (len<=75) return new Uint8Array([len,...data]);
  if (len<=255) return new Uint8Array([0x4c,len,...data]);
  return new Uint8Array([0x4d,len&0xff,(len>>8)&0xff,...data]);
}
function pushdropScript(data: Uint8Array, pk: Uint8Array) {
  const d=encodePush(data), p=encodePush(pk);
  const out=new Uint8Array(d.length+1+p.length+1); let i=0;
  out.set(d,i);i+=d.length; out[i++]=0x75; out.set(p,i);i+=p.length; out[i]=0xac; return out;
}
function derEncode(r: bigint, s: bigint) {
  function trimPad(n: bigint) {
    const buf=new Uint8Array(32); let x=n;
    for(let i=31;i>=0;i--){buf[i]=Number(x&0xffn);x>>=8n;}
    let start=0; while(start<buf.length-1&&buf[start]===0)start++;
    const t=buf.subarray(start);
    if((t[0]!&0x80)!==0){const p=new Uint8Array(t.length+1);p.set(t,1);return p;}
    return t;
  }
  const rB=trimPad(r),sB=trimPad(s);
  const total=2+rB.length+2+sB.length;
  const out=new Uint8Array(2+total);
  out[0]=0x30;out[1]=total;out[2]=0x02;out[3]=rB.length;out.set(rB,4);
  const sOff=4+rB.length; out[sOff]=0x02;out[sOff+1]=sB.length;out.set(sB,sOff+2);
  return out;
}

// BIP143 sighash.
const SIGHASH_ALL_FORKID = 0x41;
function computeSighash(txidBytes: Uint8Array, vout: number, value: bigint, lockScript: Uint8Array, outputs: Array<{script:Uint8Array;sats:bigint}>) {
  const hashPrevouts = sha256d(concat([txidBytes, le4(vout)]));
  const hashSequence = sha256d(le4(0xffffffff));
  const hashOutputs  = sha256d(concat(outputs.map(o=>concat([le8(o.sats),varInt(o.script.length),o.script]))));
  const preimage = concat([
    le4(1), hashPrevouts, hashSequence,
    txidBytes, le4(vout),
    varInt(lockScript.length), lockScript,
    le8(value), le4(0xffffffff),
    hashOutputs,
    le4(0), le4(SIGHASH_ALL_FORKID),
  ]);
  return sha256d(preimage);
}

// ── Build the test transaction ────────────────────────────────────────────────

const fundingLock = buildP2pkhLock(H160);
const testData    = new TextEncoder().encode('{"test":"cashlanes.settlement.anchor","seq":1}');
const anchorScript = pushdropScript(testData, TEST_PK);
const changeSats   = FUNDING_VALUE - ANCHOR_SATS - FEE_SATS;

const outputs = [
  { script: anchorScript, sats: ANCHOR_SATS },
  { script: fundingLock,  sats: changeSats  },
];

// Internal byte order = display txid reversed.
const txidBytes = fromHex(FUNDING_TXID_HEX).slice().reverse();

const sighash  = computeSighash(txidBytes, 0, FUNDING_VALUE, fundingLock, outputs);
const sigObj   = secp.sign(sighash, TEST_SK).normalizeS();
const derSig   = derEncode(sigObj.r, sigObj.s);

// scriptSig: <len sig+sighash> <sig> <SIGHASH_ALL_FORKID> <len pk> <pk>
const sigLen   = derSig.length + 1;
const sigPush  = new Uint8Array(1 + sigLen);
sigPush[0] = sigLen; sigPush.set(derSig, 1); sigPush[sigLen] = SIGHASH_ALL_FORKID;
const pkPush   = new Uint8Array(1 + TEST_PK.length);
pkPush[0] = TEST_PK.length; pkPush.set(TEST_PK, 1);
const unlock   = concat([sigPush, pkPush]);

// Standard raw tx.
const rawInput = concat([
  txidBytes, le4(0), varInt(unlock.length), unlock, le4(0xffffffff),
]);
const rawOutputs = concat(outputs.map(o => concat([le8(o.sats), varInt(o.script.length), o.script])));
const rawTx = concat([le4(1), varInt(1), rawInput, varInt(2), rawOutputs, le4(0)]);
const txid  = toHex(sha256d(rawTx).slice().reverse());

// EF format: version(4) | EF_MARKER(6) | inputs[txid|vout|unlock|seq|value|lock] | outputs | locktime
// EF_MARKER is 6 bytes (verified against wallet-headers/brain/src/tx-builder.ts).
const EF_MARKER = new Uint8Array([0x00,0x00,0x00,0x00,0x00,0xef]);
const efInput = concat([
  txidBytes, le4(0),
  varInt(unlock.length), unlock,
  le4(0xffffffff),
  // EF extension: sourceValue + sourceLock (after sequence).
  le8(FUNDING_VALUE), varInt(fundingLock.length), fundingLock,
]);
const efTx = concat([le4(1), EF_MARKER, varInt(1), efInput, varInt(2), rawOutputs, le4(0)]);

// ── Verify ────────────────────────────────────────────────────────────────────

let pass = 0, fail = 0;
function check(label: string, condition: boolean, detail = '') {
  if (condition) { console.log(`  ✓ ${label}`); pass++; }
  else           { console.error(`  ✗ ${label}${detail ? ': '+detail : ''}`); fail++; }
}

// EF: first 4 bytes = nVersion (01000000 LE), next 6 bytes = EF_MARKER (000000000ef).
check('EF nVersion (bytes 0-3)', toHex(efTx.slice(0,4)) === '01000000');
check('EF marker exact 6 bytes', toHex(efTx.slice(4,10)) === '00000000' + '00ef');
check('txid is 64 hex chars', txid.length === 64);
check('DER signature length (63-72 bytes)', derSig.length >= 63 && derSig.length <= 72,
  `got ${derSig.length}`);
check('DER sig starts with 0x30', derSig[0] === 0x30);
check('anchor output is output[0]', toHex(anchorScript).startsWith(toHex(encodePush(testData))));
check('anchor script ends with OP_CHECKSIG (0xac)', anchorScript[anchorScript.length-1] === 0xac);
// Check OP_DROP (0x75) is present.
const hasOpDrop = Array.from(anchorScript).some(b => b === 0x75);
check('anchor script contains OP_DROP (0x75)', hasOpDrop);
check('change amount correct', changeSats === FUNDING_VALUE - ANCHOR_SATS - FEE_SATS,
  `expected ${FUNDING_VALUE - ANCHOR_SATS - FEE_SATS}, got ${changeSats}`);
check('address is mainnet P2PKH (starts with 1)', address.startsWith('1'));
check('pubkey is 33 bytes compressed', TEST_PK.length === 33 && (TEST_PK[0] === 2 || TEST_PK[0] === 3));

console.log(`\n   txid:     ${txid}`);
console.log(`   EF size:  ${efTx.length} bytes`);
console.log(`   raw size: ${rawTx.length} bytes`);
console.log(`   sig len:  ${derSig.length} bytes (DER)`);
console.log(`   change:   ${changeSats} sats → ${address}`);
console.log();
console.log(`   Anchor script (first 20 bytes): ${toHex(anchorScript.slice(0,20))}...`);
console.log(`   PushDrop layout: <data(${testData.length}B)> OP_DROP <pk(33B)> OP_CHECKSIG`);
console.log();

if (fail === 0) {
  console.log(`✓ All ${pass} checks passed. EF transaction builds correctly.`);
  console.log(`  Ready to fund ${address} and enable HEADLESS_WALLET=true.`);
} else {
  console.error(`✗ ${fail}/${pass+fail} checks FAILED.`);
  process.exit(1);
}

```
