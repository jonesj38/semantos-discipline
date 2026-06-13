---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/relay/cashlanes-bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.436917+00:00
---

# cartridges/shared/relay/cashlanes-bridge.ts

```ts
#!/usr/bin/env bun
/**
 * cashlanes-bridge.ts — IXP CashLanes per-packet payment channel bridge
 *
 * Simulates a VPP per-packet metered payment channel using the CashLanes
 * FSM model.  On "fund" events it calls Metanet Desktop (:3321) to build
 * a real 2-of-2 multisig funding output.  On "settle" events it calls
 * createAction twice — once from the consumer BRC-42 key and once from the
 * provider BRC-42 key — producing two real BSV mainnet txids per settlement.
 *
 * Channel FSM states:
 *   UNFUNDED → (fund)  → FUNDED
 *              (start) → FLOW_ACTIVE
 *              (advance × N or settle) → SETTLING → CLOSED
 *
 * HTTP :5198
 *   POST /channel/fund     → fund the channel (real 2-of-2 multisig BSV tx)
 *   POST /channel/start    → start MB tick loop (FLOW_ACTIVE)
 *   POST /channel/advance  → per-packet tick (called by dashboard on ixp.route.accept)
 *   POST /channel/settle   → settle + close (two real BSV anchor txs)
 *   POST /channel/reset    → reset to UNFUNDED (demo restart)
 *   GET  /channel/state    → current state JSON
 *   GET  /channel/events   → SSE stream of state changes
 *
 * bun cartridges/shared/relay/cashlanes-bridge.ts [--port 5198]
 */

import { sha256 } from '@noble/hashes/sha2';
import { ripemd160 } from '@noble/hashes/ripemd160';
import { getPublicKey as secp256k1GetPublicKey } from '@noble/secp256k1';
import { createHash } from 'node:crypto';
import {
  type HeadlessWallet,
  initHeadlessWallet,
  sendPushdrop,
  getBalance,
} from '../anchor/headless-wallet';

// ── Config ────────────────────────────────────────────────────────────────────

const HTTP_PORT      = parseInt(process.env.BRIDGE_PORT    ?? '5198', 10);
// Use 127.0.0.1 explicitly: Bun's fetch prefers ::1 (IPv6) when resolving
// "localhost", but Metanet Desktop only binds to IPv4.
const METANET_URL    = process.env.METANET_URL    ?? 'http://127.0.0.1:3321';
const HAT_NAME       = process.env.HAT_NAME       ?? 'ixp-ams-noc';
// Set HEADLESS_WALLET=true to bypass Metanet Desktop for settlements.
// Cuts settlement latency from ~7s → ~100ms via direct sign + ARC broadcast.
// Requires the headless wallet to have funded UTXOs (see headless-wallet.ts).
const USE_HEADLESS   = process.env.HEADLESS_WALLET === 'true';

// Headless wallet singleton (initialized at startup when USE_HEADLESS=true).
let hw: HeadlessWallet | null = null;

// Auto-settle after this many MB (simulated). Set to 0 to disable MB-based trigger.
// Default raised to 50 MB so the fuzzer at 95 cells/sec doesn't trigger settlements
// every 0.1s — 50 MB = ~105 advance calls ≈ 1 settlement per real-usage burst.
const AUTO_SETTLE_MB   = parseFloat(process.env.AUTO_SETTLE_MB   ?? '50');
// Auto-settle after this many seconds. Set to 0 to disable (default).
// Recommended for MND mode: AUTO_SETTLE_SECS=120 (settle at most every 2 min).
const AUTO_SETTLE_SECS = parseInt(process.env.AUTO_SETTLE_SECS  ?? '0', 10);
// Satoshis per MB (demo rate: 10 sats/MB)
const SATS_PER_MB    = 10;
// Simulated MB per "advance" call (one packet batch = ~0.5 MB)
const MB_PER_ADVANCE = 0.5;
// Funding amount (demo: 1000 sats)
const FUNDING_SATS   = 1000;

// ── Key derivation (hat-scoped, matches infra-demo hat logic) ─────────────────

function hatPrivKey(name: string): Uint8Array {
  return sha256(new TextEncoder().encode(name));
}

function hatPubKey(name: string): Uint8Array {
  return secp256k1GetPublicKey(hatPrivKey(name), true); // compressed 33 bytes
}

function hash160(bytes: Uint8Array): Uint8Array {
  return ripemd160(sha256(bytes));
}

function toHex(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString('hex');
}

function fromHex(hex: string): Uint8Array {
  const h = hex.trim();
  const out = new Uint8Array(h.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(h.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

// ── Bitcoin Script helpers ────────────────────────────────────────────────────

function encodePush(data: Uint8Array): Uint8Array {
  const len = data.length;
  if (len <= 75) {
    return new Uint8Array([len, ...data]);
  } else if (len <= 255) {
    return new Uint8Array([0x4c, len, ...data]); // OP_PUSHDATA1
  } else {
    return new Uint8Array([0x4d, len & 0xff, (len >> 8) & 0xff, ...data]); // OP_PUSHDATA2
  }
}

/**
 * 2-of-2 multisig locking script
 * Sorts both pubkeys lexicographically by hex string.
 * OP_2 <push33 sorted_pk1> <push33 sorted_pk2> OP_2 OP_CHECKMULTISIG
 * = [0x52, 0x21, ...pk1, 0x21, ...pk2, 0x52, 0xae]
 */
function multisigScript(pubkeyHex1: string, pubkeyHex2: string): { script: string; orderedPubKeys: [string, string] } {
  const [pk1, pk2] = [pubkeyHex1, pubkeyHex2].sort();
  const pk1bytes = fromHex(pk1);
  const pk2bytes = fromHex(pk2);
  // 1 + 1 + 33 + 1 + 33 + 1 + 1 = 71 bytes
  const buf = new Uint8Array(71);
  let i = 0;
  buf[i++] = 0x52; // OP_2
  buf[i++] = 0x21; // push 33 bytes
  buf.set(pk1bytes, i); i += 33;
  buf[i++] = 0x21; // push 33 bytes
  buf.set(pk2bytes, i); i += 33;
  buf[i++] = 0x52; // OP_2
  buf[i++] = 0xae; // OP_CHECKMULTISIG
  return { script: toHex(buf), orderedPubKeys: [pk1, pk2] };
}

/**
 * PushDrop locking script — <data> OP_DROP <pubkey> OP_CHECKSIG
 * Embeds settlement data on-chain while remaining (notionally) spendable
 * with the matching private key.
 */
function pushdropScript(data: Uint8Array, pubkey: Uint8Array): string {
  const dataPush   = encodePush(data);
  const pubkeyPush = encodePush(pubkey);
  const out = new Uint8Array(dataPush.length + 1 + pubkeyPush.length + 1);
  let i = 0;
  out.set(dataPush, i); i += dataPush.length;
  out[i++] = 0x75; // OP_DROP
  out.set(pubkeyPush, i); i += pubkeyPush.length;
  out[i] = 0xac; // OP_CHECKSIG
  return toHex(out);
}

// ── Channel state ─────────────────────────────────────────────────────────────

type ChannelState = 'UNFUNDED' | 'FUNDED' | 'FLOW_ACTIVE' | 'SETTLING' | 'CLOSED';

interface Settlement {
  seq:           number;
  unitsMB:       number;
  costSats:      number;
  ts:            number;
  consumerTxid:  string;
  providerTxid:  string;
  consumerWoc:   string;
  providerWoc:   string;
  status:        'pending' | 'confirmed';
  blockHeight?:  number;
}

const channel = {
  id:              `ixp-${createHash('sha256').update(Date.now().toString()).digest('hex').slice(0, 8)}`,
  state:           'UNFUNDED' as ChannelState,
  hat:             HAT_NAME,
  hatFp:           createHash('sha256').update(HAT_NAME).digest('hex').slice(0, 8),
  fundingTxid:     null as string | null,
  fundingVout:     0,
  providerPubKey:  null as string | null,
  consumerPubKey:  null as string | null,
  orderedPubKeys:  null as [string, string] | null,
  multisigScript:  null as string | null,
  unitsMB:         0,      // cumulative MB this flow session
  costSats:        0,      // cumulative cost sats
  sequence:        0,      // settlement counter
  settlements:     [] as Settlement[],
  tickTimer:       null as ReturnType<typeof setInterval> | null,
};

// ── Session stats (real counters, never faked) ─────────────────────────────────

const stats = {
  advancesTotal:   0,   // total POST /channel/advance calls this process lifetime
  sessionStartTs:  Date.now(),
};

// Timestamp of the most recent settlement (for time-based auto-settle).
let lastSettleTs = 0;

// ── SSE broadcast ─────────────────────────────────────────────────────────────

const sseClients = new Set<ReadableStreamController<Uint8Array>>();

function broadcast(event: string, data: unknown) {
  const msg = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  const bytes = new TextEncoder().encode(msg);
  for (const ctrl of sseClients) {
    try { ctrl.enqueue(bytes); } catch { sseClients.delete(ctrl); }
  }
}

function statePayload() {
  return {
    channelId:      channel.id,
    state:          channel.state,
    hat:            channel.hat,
    hatFp:          channel.hatFp,
    fundingTxid:    channel.fundingTxid,
    fundingVout:    channel.fundingVout,
    providerPubKey: channel.providerPubKey,
    consumerPubKey: channel.consumerPubKey,
    orderedPubKeys: channel.orderedPubKeys,
    multisigScript: channel.multisigScript,
    unitsMB:        +channel.unitsMB.toFixed(2),
    costSats:       +channel.costSats.toFixed(0),
    sequence:       channel.sequence,
    settlements:    channel.settlements,
    satPerMB:       SATS_PER_MB,
    fundingSats:    FUNDING_SATS,
    // Settlement configuration (for dashboard display)
    autoSettleMB:   AUTO_SETTLE_MB,
    autoSettleSecs: AUTO_SETTLE_SECS,
    settlementMode: hw ? 'headless' : 'metanet-desktop',
  };
}

// ── Metanet Desktop calls ─────────────────────────────────────────────────────

/**
 * Fetch a BRC-42 derived public key from Metanet Desktop.
 * protocolName must contain only letters/numbers/spaces (no hyphens).
 */
async function getPublicKey(protocolName: string, keyID: string): Promise<string> {
  const resp = await fetch(`${METANET_URL}/getPublicKey`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Origin': 'http://localhost',
    },
    body: JSON.stringify({ protocolID: [1, protocolName], keyID }),
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`getPublicKey(${protocolName}) ${resp.status}: ${text}`);
  }
  const j = await resp.json() as { publicKey?: string };
  if (!j.publicKey) throw new Error(`getPublicKey: no publicKey in response`);
  return j.publicKey;
}

async function createAction(opts: {
  description: string;
  outputs: Array<{ lockingScript: string; satoshis: number; outputDescription?: string }>;
}): Promise<string> {
  const body = {
    description: opts.description,
    labels: [] as string[],
    outputs: opts.outputs.map(o => ({ ...o, tags: [] })),
  };

  const resp = await fetch(`${METANET_URL}/createAction`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Origin': 'http://localhost',
    },
    body: JSON.stringify(body),
  });

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Metanet Desktop createAction ${resp.status}: ${text}`);
  }

  const j = await resp.json() as {
    txid?: string;
    beef?: string;
    tx?: number[];
    rawTx?: string;
    signedTransaction?: string;
  };

  if (j.txid) return j.txid;

  if (Array.isArray(j.tx) && j.tx.length > 0) {
    throw new Error('createAction: got tx[] but no txid field — update bridge to parse BEEF');
  }

  throw new Error(`createAction: no txid in response (keys: ${Object.keys(j).join(', ')})`);
}

// ── WoC confirmation polling ──────────────────────────────────────────────────

async function pollWoC(txid: string, seq: number) {
  const deadline = Date.now() + 5 * 60 * 1000;
  while (Date.now() < deadline) {
    await new Promise(r => setTimeout(r, 15000));
    try {
      const r = await fetch(`https://api.whatsonchain.com/v1/bsv/main/tx/${txid}`);
      if (r.ok) {
        const d = await r.json() as any;
        const confirmed = !!d.blockhash || !!d.blockheight;
        broadcast('confirmation', { seq, txid, status: confirmed ? 'confirmed' : 'pending', blockHeight: d.blockheight ?? null });
        if (confirmed) return;
      }
    } catch { /* network error — retry */ }
  }
  broadcast('confirmation', { seq, txid, status: 'unconfirmed', blockHeight: null });
}

// ── Settlement logic ──────────────────────────────────────────────────────────

let _settlementInFlight = false;

async function settlementTick() {
  // Guard: prevent concurrent settlements if /channel/advance triggers while one is in progress.
  if (_settlementInFlight) {
    console.log('[bridge] settlementTick: already in flight — skipping duplicate');
    return;
  }
  _settlementInFlight = true;

  try { await _doSettlement(); } finally { _settlementInFlight = false; }
}

async function _doSettlement() {
  const seq       = channel.sequence + 1;
  const unitsMB   = +channel.unitsMB.toFixed(2);
  const costSats  = +channel.costSats.toFixed(0);

  channel.state = 'SETTLING';
  broadcast('state', statePayload());

  // Use BRC-42 derived pubkeys from the funding step if available,
  // otherwise fall back to hat-derived local key.
  const consumerPubkeyBytes = channel.consumerPubKey
    ? fromHex(channel.consumerPubKey)
    : hatPubKey(channel.hat);
  const providerPubkeyBytes = channel.providerPubKey
    ? fromHex(channel.providerPubKey)
    : hatPubKey(channel.hat);

  // Consumer settlement
  const consumerSettlementData = JSON.stringify({
    ch: channel.id, mb: unitsMB, sats: costSats, seq,
    role: 'consumer', fundingTx: channel.fundingTxid, hat: channel.hat,
  });
  const consumerScript = pushdropScript(
    new TextEncoder().encode(consumerSettlementData),
    consumerPubkeyBytes,
  );

  // Provider settlement
  const providerSettlementData = JSON.stringify({
    ch: channel.id, mb: unitsMB, sats: costSats, seq,
    role: 'provider', fundingTx: channel.fundingTxid, hat: channel.hat,
  });
  const providerScript = pushdropScript(
    new TextEncoder().encode(providerSettlementData),
    providerPubkeyBytes,
  );

  let consumerTxid: string;
  let providerTxid: string;

  if (hw) {
    // ── Headless wallet path (~100ms, no Metanet Desktop) ──────────────────
    // Owner pubkey for the PushDrop = headless wallet's own pubkey.
    // The wallet funds both outputs and can spend them later for accounting.
    try {
      const t0 = Date.now();
      consumerTxid = await sendPushdrop(hw, new TextEncoder().encode(consumerSettlementData), hw.pubKey);
      providerTxid = await sendPushdrop(hw, new TextEncoder().encode(providerSettlementData), hw.pubKey);
      console.log(`[bridge] Headless settlement #${seq} in ${Date.now() - t0}ms — consumer=${consumerTxid} provider=${providerTxid}`);
    } catch (err: any) {
      console.error(`[bridge] Headless settlement failed: ${err.message}`);
      channel.state = 'FLOW_ACTIVE';
      broadcast('state', statePayload());
      broadcast('error', { message: `Settlement failed (headless): ${err.message}` });
      return;
    }
  } else {
    // ── Metanet Desktop path (~7s, real BRC-42 keys) ────────────────────────
    try {
      consumerTxid = await createAction({
        description: `CashLanes settlement seq${seq} — consumer — ${unitsMB}MB`,
        outputs: [{ lockingScript: consumerScript, satoshis: 1, outputDescription: 'Consumer settlement anchor' }],
      });
      console.log(`[bridge] Consumer settlement #${seq}: txid=${consumerTxid}`);
    } catch (err: any) {
      console.error(`[bridge] Consumer settlement tx failed: ${err.message}`);
      channel.state = 'FLOW_ACTIVE';
      broadcast('state', statePayload());
      broadcast('error', { message: `Consumer settlement failed: ${err.message}` });
      return;
    }

    try {
      providerTxid = await createAction({
        description: `CashLanes settlement seq${seq} — ixp provider — ${unitsMB}MB`,
        outputs: [{ lockingScript: providerScript, satoshis: 1, outputDescription: 'Provider settlement anchor' }],
      });
      console.log(`[bridge] Provider settlement #${seq}: txid=${providerTxid}`);
    } catch (err: any) {
      console.error(`[bridge] Provider settlement tx failed: ${err.message}`);
      channel.state = 'FLOW_ACTIVE';
      broadcast('state', statePayload());
      broadcast('error', { message: `Provider settlement failed: ${err.message}` });
      return;
    }
  }

  channel.sequence = seq;
  lastSettleTs = Date.now();
  const s: Settlement = {
    seq,
    unitsMB,
    costSats,
    ts:           lastSettleTs,
    consumerTxid,
    providerTxid,
    consumerWoc:  `https://whatsonchain.com/tx/${consumerTxid}`,
    providerWoc:  `https://whatsonchain.com/tx/${providerTxid}`,
    status:       'pending',
  };
  channel.settlements.push(s);

  console.log(`[bridge] Settlement #${seq}: ${unitsMB} MB  ${costSats} sats  consumer=${consumerTxid}  provider=${providerTxid}`);

  broadcast('settlement', s);
  broadcast('state', statePayload());

  // Poll consumer txid for confirmation (fire-and-forget)
  pollWoC(consumerTxid, seq).catch(() => {});

  // Anchor the settlement batch as a PushDrop tx (fire-and-forget)
  // Payload: { channelId, seq, unitsMB, costSats, settlementTxids }
  // Uses the proven recipe: createAction with PushDrop locking script
  //   <data> OP_DROP <pubkey> OP_CHECKSIG
  // This makes each settlement a real on-chain record beyond the channel itself.
  anchorSettlement(s).catch(err => {
    console.warn(`[bridge] Anchor tx failed (non-fatal): ${err.message}`);
  });
}

/**
 * anchorSettlement — write a PushDrop UTXO anchoring the settlement batch
 * on BSV mainnet.  Uses the provider's BRC-42 pubkey as the locking key.
 *
 * The locking script is:
 *   PUSHDATA(<json>) OP_DROP PUSH33(<providerPubkey>) OP_CHECKSIG
 *
 * This anchors the settlement summary immutably on-chain.  The provider can
 * spend this UTXO later to prove the settlement happened — or just leave it
 * as an audit trail.
 */
async function anchorSettlement(s: Settlement): Promise<void> {
  // In headless mode, the wallet's own pubkey is used (no MND pubkey needed).
  if (!hw && !channel.providerPubKey) return;

  const anchorData = JSON.stringify({
    v:           1,
    type:        'cashlanes.settlement.anchor',
    channelId:   channel.id,
    hat:         channel.hat,
    seq:         s.seq,
    unitsMB:     s.unitsMB,
    costSats:    s.costSats,
    ts:          s.ts,
    settlementTxids: {
      consumer: s.consumerTxid,
      provider: s.providerTxid,
    },
  });

  const pubkeyBytes = hw ? hw.pubKey : fromHex(channel.providerPubKey!);
  const dataBytes   = new TextEncoder().encode(anchorData);

  let anchorTxid: string;

  if (hw) {
    // Headless wallet: sendPushdrop handles script build, sign, broadcast.
    anchorTxid = await sendPushdrop(hw, dataBytes, pubkeyBytes);
  } else {
    // Metanet Desktop path.
    if (!channel.providerPubKey) return;
    const anchorScript = pushdropScript(dataBytes, fromHex(channel.providerPubKey));
    try {
      anchorTxid = await createAction({
        description: `CashLanes settlement anchor seq${s.seq} — ${s.unitsMB}MB — ${s.costSats} sats`,
        outputs: [{
          lockingScript:      anchorScript,
          satoshis:           1,
          outputDescription:  `Settlement anchor #${s.seq} — PushDrop`,
        }],
      });
    } catch (err: any) {
      throw err; // caller logs it as non-fatal
    }
  }

  console.log(`[bridge] Anchor #${s.seq}: txid=${anchorTxid}  woc=https://whatsonchain.com/tx/${anchorTxid}`);

  // Broadcast anchor txid to SSE clients so dashboard can display it
  broadcast('anchor', {
    seq:        s.seq,
    anchorTxid,
    anchorWoc:  `https://whatsonchain.com/tx/${anchorTxid}`,
  });

  // Merge anchor txid back into the settlement record
  const record = channel.settlements.find(r => r.seq === s.seq);
  if (record) {
    (record as any).anchorTxid = anchorTxid;
    (record as any).anchorWoc  = `https://whatsonchain.com/tx/${anchorTxid}`;
  }
}

// ── Tick timer (FLOW_ACTIVE continuous simulation) ────────────────────────────

function startTickLoop() {
  if (channel.tickTimer) return;
  channel.tickTimer = setInterval(async () => {
    if (channel.state !== 'FLOW_ACTIVE') {
      stopTickLoop();
      return;
    }
    channel.unitsMB  += 0.3;
    channel.costSats += 0.3 * SATS_PER_MB;
    broadcast('tick', { unitsMB: +channel.unitsMB.toFixed(2), costSats: +channel.costSats.toFixed(0) });

    // Auto-settle: time-based (if AUTO_SETTLE_SECS > 0) or MB-based.
    const settledMB = channel.settlements.at(-1)?.unitsMB ?? 0;
    const mbTrigger  = AUTO_SETTLE_MB  > 0 && (channel.unitsMB - settledMB) >= AUTO_SETTLE_MB;
    const timeTrigger = AUTO_SETTLE_SECS > 0 && channel.unitsMB > 0 &&
      (Date.now() - (lastSettleTs || channel.settlements[0]?.ts || Date.now())) >= AUTO_SETTLE_SECS * 1000;

    if (mbTrigger || timeTrigger) {
      const reason = timeTrigger ? `${AUTO_SETTLE_SECS}s elapsed` : `${AUTO_SETTLE_MB}MB threshold`;
      console.log(`[bridge] Auto-settle triggered: ${reason}`);
      await settlementTick();
      if (channel.state !== 'CLOSED') channel.state = 'FLOW_ACTIVE';
      broadcast('state', statePayload());
    }
  }, 8000);
}

function stopTickLoop() {
  if (channel.tickTimer) {
    clearInterval(channel.tickTimer);
    channel.tickTimer = null;
  }
}

// ── CORS ──────────────────────────────────────────────────────────────────────

const CORS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

function json(data: unknown, status = 200) {
  return Response.json(data, { status, headers: CORS });
}

// ── Init headless wallet (async, before serving) ──────────────────────────────

if (USE_HEADLESS) {
  try {
    hw = await initHeadlessWallet();
    console.log(`[bridge] Headless wallet: ${hw.address}  balance: ${getBalance(hw)} sats`);
  } catch (err: any) {
    console.error(`[bridge] ⚠ Headless wallet init failed: ${err.message}`);
    console.error(`[bridge] ⚠ Falling back to Metanet Desktop (HEADLESS_WALLET ignored)`);
  }
}

const settlementMode = hw
  ? `headless wallet (${hw.address}) — ~100ms/settlement`
  : `Metanet Desktop ${METANET_URL} — ~7s/settlement`;

console.log(`[bridge] CashLanes bridge HTTP :${HTTP_PORT}`);
console.log(`[bridge] Settlement mode: ${settlementMode}`);
console.log(`[bridge] Hat: ${HAT_NAME} (fp=${channel.hatFp})`);
console.log(`[bridge] Channel: ${channel.id}`);
const autoSettleDesc = AUTO_SETTLE_SECS > 0
  ? `every ${AUTO_SETTLE_SECS}s (time-based)`
  : `every ${AUTO_SETTLE_MB} MB`;
console.log(`[bridge] Rate: ${SATS_PER_MB} sats/MB  Auto-settle: ${autoSettleDesc}`);
console.log(`[bridge] Funding: ${FUNDING_SATS} sats into 2-of-2 multisig (provider + consumer BRC-42 keys)`);
console.log(`[bridge] Settle: 2 × PushDrop per settlement (consumer + provider anchor txs) + 1 batch anchor`);
console.log(`[bridge] Endpoints:`);
console.log(`  POST /channel/fund    — fund 2-of-2 multisig (real BSV tx)`);
console.log(`  POST /channel/start   — start flow`);
console.log(`  POST /channel/advance — per-packet tick (ixp.route.accept)`);
console.log(`  POST /channel/settle  — dual settle (2 real BSV anchor txs)`);
console.log(`  POST /channel/reset   — reset for demo restart`);
console.log(`  GET  /channel/state   — current state JSON`);
console.log(`  GET  /channel/events  — SSE stream`);

// ── HTTP server ───────────────────────────────────────────────────────────────

Bun.serve({
  port: HTTP_PORT,

  async fetch(req) {
    const url = new URL(req.url);
    const { method, pathname } = { method: req.method, pathname: url.pathname };

    if (method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

    // ── GET /channel/state ────────────────────────────────────────────────
    if (method === 'GET' && pathname === '/channel/state') {
      return json(statePayload());
    }

    // ── GET /channel/events (SSE) ─────────────────────────────────────────
    if (method === 'GET' && pathname === '/channel/events') {
      let ctrl!: ReadableStreamController<Uint8Array>;
      const stream = new ReadableStream<Uint8Array>({
        start(c) {
          ctrl = c;
          sseClients.add(ctrl);
          const msg = `event: state\ndata: ${JSON.stringify(statePayload())}\n\n`;
          ctrl.enqueue(new TextEncoder().encode(msg));
        },
        cancel() { sseClients.delete(ctrl); },
      });
      return new Response(stream, {
        headers: {
          ...CORS,
          'Content-Type':  'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection':    'keep-alive',
        },
      });
    }

    // ── POST /channel/fund ────────────────────────────────────────────────
    if (method === 'POST' && pathname === '/channel/fund') {
      if (channel.state !== 'UNFUNDED') {
        return json({ error: `Cannot fund from state ${channel.state}` }, 400);
      }

      let providerPubKey: string;
      let consumerPubKey: string;
      let txid: string;

      if (hw) {
        // ── Headless mode: no Metanet Desktop needed ──────────────────────
        // Use the headless wallet's own pubkey for both roles.
        // The 2-of-2 multisig is simulated (both keys are the same wallet key).
        // Settlements (the important on-chain part) still use real BSV txs.
        providerPubKey = toHex(hw.pubKey);
        consumerPubKey = toHex(hw.pubKey);
        // Create a real on-chain P2PKH funding output via the headless wallet.
        // This proves the channel is genuinely funded, not just simulated.
        const fundingData = new TextEncoder().encode(JSON.stringify({
          v: 1, type: 'cashlanes.channel.fund',
          channelId: channel.id, hat: channel.hat,
          fundingSats: FUNDING_SATS,
          mode: 'headless',
        }));
        try {
          txid = await sendPushdrop(hw, fundingData, hw.pubKey, BigInt(FUNDING_SATS));
          console.log(`[bridge] Headless channel funded — txid=${txid}`);
        } catch (err: any) {
          console.error(`[bridge] Headless fund failed: ${err.message}`);
          return json({ error: err.message }, 500);
        }
      } else {
        // ── Metanet Desktop mode: real BRC-42 2-of-2 multisig ─────────────
        console.log(`[bridge] Fetching BRC-42 pubkeys from Metanet Desktop...`);
        try {
          providerPubKey = await getPublicKey('cashlanes ixp provider', `channel-${channel.id}`);
          console.log(`[bridge] Provider pubkey: ${providerPubKey}`);
        } catch (err: any) {
          console.error(`[bridge] getPublicKey(provider) failed: ${err.message}`);
          return json({ error: err.message }, 500);
        }
        try {
          consumerPubKey = await getPublicKey('cashlanes consumer', `channel-${channel.id}`);
          console.log(`[bridge] Consumer pubkey: ${consumerPubKey}`);
        } catch (err: any) {
          console.error(`[bridge] getPublicKey(consumer) failed: ${err.message}`);
          return json({ error: err.message }, 500);
        }
        const { script, orderedPubKeys: _op } = multisigScript(providerPubKey, consumerPubKey);
        console.log(`[bridge] 2-of-2 multisig script: ${script.slice(0, 30)}... (${script.length / 2} bytes)`);
        console.log(`[bridge] Funding channel ${channel.id} via Metanet Desktop...`);
        try {
          txid = await createAction({
            description: `CashLanes IXP channel funding — ${channel.id} — 2-of-2 multisig — hat=${channel.hat}`,
            outputs: [{ lockingScript: script, satoshis: FUNDING_SATS, outputDescription: '2-of-2 multisig channel funding lock' }],
          });
        } catch (err: any) {
          console.error(`[bridge] Fund failed: ${err.message}`);
          return json({ error: err.message }, 500);
        }
        console.log(`[bridge] Channel FUNDED via MND — txid=${txid}`);
      }

      // Note: we add one output; wallet may place it at vout 0 or 1 depending on change.
      // For this demo, assume vout 0. Production should scan outputs by script match.
      // In headless mode, orderedPubKeys and multisigScript are omitted (no 2-of-2 multisig).
      let orderedPubKeys: [string, string] | null = null;
      let fundingScript: string | null = null;
      if (!hw) {
        const ms = multisigScript(providerPubKey, consumerPubKey);
        orderedPubKeys = ms.orderedPubKeys;
        fundingScript  = ms.script;
      }

      channel.providerPubKey  = providerPubKey;
      channel.consumerPubKey  = consumerPubKey;
      channel.orderedPubKeys  = orderedPubKeys;
      channel.multisigScript  = fundingScript;
      channel.fundingTxid     = txid;
      channel.fundingVout     = 0;
      channel.state           = 'FUNDED';

      const modeLabel = hw ? 'headless wallet' : 'Metanet Desktop';
      console.log(`[bridge] Channel FUNDED (${modeLabel}) — txid=${txid}`);
      broadcast('state', statePayload());
      return json({
        ok: true, txid, state: channel.state,
        mode: hw ? 'headless' : 'metanet-desktop',
        providerPubKey, consumerPubKey,
        orderedPubKeys,
        multisigScript: fundingScript,
      });
    }

    // ── POST /channel/start ───────────────────────────────────────────────
    if (method === 'POST' && pathname === '/channel/start') {
      if (channel.state !== 'FUNDED') {
        return json({ error: `Cannot start from state ${channel.state}` }, 400);
      }
      channel.state = 'FLOW_ACTIVE';
      startTickLoop();
      console.log(`[bridge] Channel FLOW_ACTIVE — mock VPP ticks running`);
      broadcast('state', statePayload());
      return json({ ok: true, state: channel.state });
    }

    // ── POST /channel/advance ─────────────────────────────────────────────
    if (method === 'POST' && pathname === '/channel/advance') {
      if (channel.state !== 'FLOW_ACTIVE') {
        return json({ ok: false, reason: `channel not active (${channel.state})` });
      }

      stats.advancesTotal++;

      channel.unitsMB  += MB_PER_ADVANCE;
      channel.costSats += MB_PER_ADVANCE * SATS_PER_MB;

      broadcast('tick', {
        unitsMB:  +channel.unitsMB.toFixed(2),
        costSats: +channel.costSats.toFixed(0),
      });

      // Auto-settle check: MB threshold and/or time-based.
      const settledMB   = channel.settlements.at(-1)?.unitsMB ?? 0;
      const mbTrigger   = AUTO_SETTLE_MB  > 0 && (channel.unitsMB - settledMB) >= AUTO_SETTLE_MB;
      const timeTrigger = AUTO_SETTLE_SECS > 0 && channel.unitsMB > 0 &&
        (Date.now() - (lastSettleTs || channel.settlements[0]?.ts || Date.now())) >= AUTO_SETTLE_SECS * 1000;

      if (mbTrigger || timeTrigger) {
        settlementTick().then(() => {
          if (channel.state !== 'CLOSED') {
            channel.state = 'FLOW_ACTIVE';
            broadcast('state', statePayload());
          }
        });
      }

      return json({ ok: true, unitsMB: +channel.unitsMB.toFixed(2), costSats: +channel.costSats.toFixed(0) });
    }

    // ── POST /channel/settle ──────────────────────────────────────────────
    if (method === 'POST' && pathname === '/channel/settle') {
      if (channel.state !== 'FLOW_ACTIVE' && channel.state !== 'FUNDED') {
        return json({ error: `Cannot settle from state ${channel.state}` }, 400);
      }
      stopTickLoop();
      await settlementTick();
      channel.state = 'CLOSED';
      stopTickLoop();
      broadcast('state', statePayload());
      const last = channel.settlements.at(-1);
      return json({
        ok: true,
        state: channel.state,
        consumerTxid: last?.consumerTxid,
        providerTxid: last?.providerTxid,
      });
    }

    // ── POST /channel/reset ───────────────────────────────────────────────
    if (method === 'POST' && pathname === '/channel/reset') {
      stopTickLoop();
      channel.id             = `ixp-${createHash('sha256').update(Date.now().toString()).digest('hex').slice(0, 8)}`;
      channel.state          = 'UNFUNDED';
      channel.fundingTxid    = null;
      channel.fundingVout    = 0;
      channel.providerPubKey = null;
      channel.consumerPubKey = null;
      channel.orderedPubKeys = null;
      channel.multisigScript = null;
      channel.unitsMB        = 0;
      channel.costSats       = 0;
      channel.sequence       = 0;
      channel.settlements    = [];
      // Reset session stats
      stats.advancesTotal   = 0;
      stats.sessionStartTs  = Date.now();
      broadcast('state', statePayload());
      return json({ ok: true, state: channel.state });
    }

    // ── GET /channel/stats ────────────────────────────────────────────────
    if (method === 'GET' && pathname === '/channel/stats') {
      const elapsedMin = (Date.now() - stats.sessionStartTs) / 60000;
      const advancesPerMin = elapsedMin > 0.1 ? +(stats.advancesTotal / elapsedMin).toFixed(2) : 0;
      return json({
        advancesTotal:  stats.advancesTotal,
        advancesPerMin,
        sessionStartTs: stats.sessionStartTs,
        state:          channel.state,
      });
    }

    // ── GET /health ───────────────────────────────────────────────────────
    if (method === 'GET' && pathname === '/health') {
      return json({
        ok:           true,
        state:        channel.state,
        mode:         hw ? 'headless' : 'metanet-desktop',
        metanetUrl:   hw ? null : METANET_URL,
        walletAddress: hw?.address ?? null,
        walletBalance: hw ? `${getBalance(hw)} sats` : null,
      });
    }

    return new Response('not found', { status: 404, headers: CORS });
  },
});

```
