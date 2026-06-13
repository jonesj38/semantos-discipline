---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/ixp-routing/carrier-billing-demo.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.413475+00:00
---

# cartridges/ixp-routing/carrier-billing-demo.ts

```ts
#!/usr/bin/env bun
/**
 * carrier-billing-demo.ts — IXP bilateral peering settlement demo
 *
 * THE PITCH
 * ─────────
 * Two ISPs peer at an IXP. Today they run traffic for a month, exchange EDI
 * files, argue about the numbers, and settle via wire transfer net-60.
 *
 * This demo shows what replacing that looks like:
 *   Each BGP route accepted → inference.request / ixp.route.accept cell
 *   Each cell → CashLanes advance at ixp tier (100 sats/cell)
 *   Settlement fires automatically → PushDrop anchor on BSV (txid)
 *   Either carrier can independently verify: txid, route count, MB exchanged
 *
 * "Your EDI file is a spreadsheet that both sides could have edited.
 *  Our settlement is a Bitcoin transaction ID. Go look it up."
 *
 * WHAT IT DEMONSTRATES (and why it matters for the architecture review)
 * ─────────────────────────────────────────────────────────────────────
 * Uses the NEW typed SSE subscription (relay ?typePath=ixp.*) so the IXP
 * handler ONLY receives IXP cells — it never sees inference or sensor cells.
 * This is the semantic multicast proof: two completely different verticals
 * sharing one relay without interference, each paying different rates.
 *
 * Carrier A: publishes ixp.route.accept / ixp.route.reject cells
 * Carrier B: publishes ixp.route.withdraw / ixp.traffic.report cells
 * Settlement handler: subscribes to ixp.* ONLY → advances CashLanes per route
 *
 * USAGE
 * ─────
 *   bun cartridges/ixp-routing/carrier-billing-demo.ts
 *   RELAY_URL=http://192.168.0.50:5199 bun carrier-billing-demo.ts
 *   DURATION_S=60 bun carrier-billing-demo.ts    # run for 60s
 *   bun carrier-billing-demo.ts --fast            # 5× speed
 *   bun carrier-billing-demo.ts --once            # single round then exit
 *
 * START THE STACK FIRST
 * ─────────────────────
 *   bash cartridges/shared/demo/start-demo.sh
 *   # then in another terminal:
 *   bun cartridges/ixp-routing/carrier-billing-demo.ts
 */

import { createHash, randomBytes } from 'node:crypto';

// ── Config ────────────────────────────────────────────────────────────────────

const RELAY_URL    = process.env.RELAY_URL    ?? 'http://localhost:5199';
const BRIDGE_URL   = process.env.BRIDGE_URL   ?? 'http://localhost:5198';
const DURATION_S   = parseInt(process.env.DURATION_S ?? '0', 10);
const FAST         = process.argv.includes('--fast');
const ONCE         = process.argv.includes('--once');
const TICK_MS      = FAST ? 1000 : 5000;   // ms between BGP route events

// Two simulated carriers peering at this IXP
const CARRIER_A = { name: 'Telstra-AS1221',  asn: 1221,  fp: 'a0b1c2d3' };
const CARRIER_B = { name: 'Optus-AS4804',    asn: 4804,  fp: 'e4f5a6b7' };
const IXP_NAME  = 'AusIX-BNE';

// BGP route pool: realistic Australian prefixes
const BGP_PREFIXES = [
  '203.2.218.0/24',   // Telstra
  '203.0.113.0/24',   // Optus
  '1.128.0.0/11',     // Telstra consumer
  '49.183.0.0/16',    // Optus mobile
  '27.122.0.0/18',    // Brisbane DC
  '101.160.0.0/13',   // Vodafone AU
  '103.16.200.0/22',  // Brisbane IXP block
  '58.6.0.0/16',      // iiNet
  '203.16.0.0/14',    // Optus business
  '139.130.0.0/16',   // AAPT
];

// ── Colour helpers ────────────────────────────────────────────────────────────

const C = {
  reset:  '\x1b[0m',
  bold:   '\x1b[1m',
  dim:    '\x1b[2m',
  green:  '\x1b[32m',
  yellow: '\x1b[33m',
  red:    '\x1b[31m',
  cyan:   '\x1b[36m',
  blue:   '\x1b[34m',
};

function log(prefix: string, msg: string) {
  const ts = new Date().toLocaleTimeString();
  console.log(`[${ts}] ${prefix} ${msg}`);
}

// ── Cell publish helpers ──────────────────────────────────────────────────────

let seq = 0;

async function publishCell(
  typePath: string,
  senderFp: string,
  data: Record<string, unknown>
): Promise<string> {
  const payload    = JSON.stringify({ ixp: IXP_NAME, ...data });
  const payloadHex = Buffer.from(payload, 'utf8').toString('hex');
  const cellId     = createHash('sha256').update(payloadHex).digest('hex');
  seq++;

  // scopeHash = SHA-256("AU.QLD.BNE.ixp") — geo-scoped to Brisbane IXP
  const scopeHash = createHash('sha256').update('AU.QLD.BNE.ixp').digest('hex');

  const body = {
    header: {
      cellId,
      typePath,
      scopeHash,
      senderFp,
      seq,
      payloadLen: payload.length,
    },
    payload: payloadHex,
  };

  const r = await fetch(`${RELAY_URL}/publish`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify(body),
    signal:  AbortSignal.timeout(3000),
  });

  if (!r.ok) {
    const err = await r.text().catch(() => '');
    throw new Error(`relay ${r.status}: ${err.slice(0, 80)}`);
  }
  return cellId;
}

// ── IXP settlement handler ────────────────────────────────────────────────────
// Subscribes to ixp.* ONLY (typed subscription — the semantic multicast proof).
// Advances CashLanes per route at the ixp tier rate (100 sats/cell).
// This handler never sees inference.*, sensor.*, or any other type.

interface SettlementStats {
  routesAccepted: number;
  routesRejected: number;
  routesWithdrawn: number;
  trafficReports:  number;
  satsAdvanced:    number;
  settlements:     Array<{ seq: number; amount: number; txid?: string; ts: number }>;
  lastSettlementTs: number;
}

const stats: SettlementStats = {
  routesAccepted:  0,
  routesRejected:  0,
  routesWithdrawn: 0,
  trafficReports:  0,
  satsAdvanced:    0,
  settlements:     [],
  lastSettlementTs: 0,
};

interface RecentCell {
  header:  { cellId: string; typePath: string; senderFp: string; ts: number };
  payload: string | null;
}

async function startIxpHandler(): Promise<void> {
  // Subscribe to ixp.* ONLY — the typed subscription
  const url = `${RELAY_URL}/cells/stream?typePath=ixp.*`;
  log('🔌', `IXP handler subscribing: ${C.cyan}${url}${C.reset}`);

  const tryConnect = async (): Promise<void> => {
    try {
      const r = await fetch(url, { signal: AbortSignal.timeout(30_000) });
      if (!r.ok || !r.body) throw new Error(`SSE connect failed: ${r.status}`);

      log('✓', `${C.green}IXP handler connected — receiving ixp.* cells only${C.reset}`);

      const reader = r.body.getReader();
      const decoder = new TextDecoder();
      let buf = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += decoder.decode(value, { stream: true });

        // Parse SSE events
        const events = buf.split('\n\n');
        buf = events.pop() ?? '';

        for (const event of events) {
          if (!event.startsWith('event: cell')) continue;
          const dataLine = event.split('\n').find(l => l.startsWith('data: '));
          if (!dataLine) continue;

          try {
            const { header, payload } = JSON.parse(dataLine.slice(6)) as RecentCell;
            await handleIxpCell(header.typePath, header.senderFp, payload);
          } catch { /* skip malformed */ }
        }
      }
    } catch (e: any) {
      if (!e.message?.includes('AbortSignal')) {
        log('⚠', `SSE error: ${e.message} — reconnecting in 3s`);
        await Bun.sleep(3000);
        await tryConnect();
      }
    }
  };

  // Run handler in background
  tryConnect().catch(() => {});
}

// Advance CashLanes per IXP cell (100 sats/cell at ixp tier)
async function advanceCashLanes(): Promise<void> {
  try {
    const r = await fetch(`${BRIDGE_URL}/channel/advance`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ mb: 0.1 }),  // 0.1 MB per route event
      signal: AbortSignal.timeout(2000),
    });
    if (r.ok) {
      const state = await r.json() as { totalAdvances?: number; totalSats?: number; settlementTxid?: string };
      stats.satsAdvanced = state.totalSats ?? stats.satsAdvanced;

      if (state.settlementTxid) {
        const settlement = {
          seq: state.totalAdvances ?? 0,
          amount: 0,
          txid: state.settlementTxid,
          ts: Date.now(),
        };
        stats.settlements.push(settlement);
        stats.lastSettlementTs = Date.now();
        log('⛓ ', `${C.green}${C.bold}SETTLEMENT #${stats.settlements.length}${C.reset} txid=${state.settlementTxid.slice(0, 16)}…`);
        log('⛓ ', `${C.dim}https://whatsonchain.com/tx/${state.settlementTxid}${C.reset}`);
      }
    }
  } catch { /* bridge offline — count anyway */ }
}

async function handleIxpCell(typePath: string, senderFp: string, payload: string | null): Promise<void> {
  let data: Record<string, unknown> = {};
  if (payload) {
    try { data = JSON.parse(Buffer.from(payload, 'hex').toString('utf8')); } catch {}
  }

  const carrier = senderFp === CARRIER_A.fp ? CARRIER_A.name
                : senderFp === CARRIER_B.fp ? CARRIER_B.name
                : `unknown(${senderFp})`;

  if (typePath === 'ixp.route.accept') {
    stats.routesAccepted++;
    log('↗', `${C.green}ACCEPT${C.reset}  ${carrier}  ${data.prefix ?? '?'}  AS_PATH=${data.asPath ?? '?'}`);
    await advanceCashLanes();
  } else if (typePath === 'ixp.route.reject') {
    stats.routesRejected++;
    log('✗', `${C.red}REJECT${C.reset}  ${carrier}  ${data.prefix ?? '?'}  reason=${data.reason ?? '?'}`);
  } else if (typePath === 'ixp.route.withdraw') {
    stats.routesWithdrawn++;
    log('↙', `${C.yellow}WITHDRAW${C.reset} ${carrier}  ${data.prefix ?? '?'}`);
  } else if (typePath === 'ixp.traffic.report') {
    stats.trafficReports++;
    const mb = ((data.bytes as number ?? 0) / 1_000_000).toFixed(1);
    log('📊', `${C.dim}TRAFFIC ${carrier} → ${data.peer ?? '?'}  ${mb}MB  ${data.packets ?? '?'} pkts${C.reset}`);
  }
}

// ── BGP route event simulator ─────────────────────────────────────────────────
// Simulates realistic BGP activity between two carriers at an IXP.

let tick = 0;

async function simulateTick(): Promise<void> {
  tick++;
  const now = Date.now();

  // Alternate: Carrier A announces a route, then Carrier B reports traffic,
  // then Carrier A withdraws an old route, etc.
  const phase = tick % 8;

  try {
    if (phase === 0 || phase === 1) {
      // A announces a route to B
      const prefix = BGP_PREFIXES[tick % BGP_PREFIXES.length]!;
      await publishCell('ixp.route.accept', CARRIER_A.fp, {
        prefix,
        asPath:    `${CARRIER_A.asn} ${CARRIER_B.asn}`,
        nextHop:   '192.168.1.1',
        localPref: 100,
        med:       0,
        communities: [`${CARRIER_A.asn}:100`],
      });
    } else if (phase === 2) {
      // B announces back
      const prefix = BGP_PREFIXES[(tick + 3) % BGP_PREFIXES.length]!;
      await publishCell('ixp.route.accept', CARRIER_B.fp, {
        prefix,
        asPath:    `${CARRIER_B.asn}`,
        nextHop:   '192.168.2.1',
        localPref: 200,
        med:       10,
        communities: [`${CARRIER_B.asn}:200`],
      });
    } else if (phase === 3) {
      // A rejects a route (policy: no transit via this AS)
      await publishCell('ixp.route.reject', CARRIER_A.fp, {
        prefix:  BGP_PREFIXES[(tick + 5) % BGP_PREFIXES.length],
        reason:  'policy_no_transit',
        asPath:  `${CARRIER_A.asn} 4637 ${CARRIER_B.asn}`,
      });
    } else if (phase === 4 || phase === 5) {
      // Traffic report: A→B
      const mbytes = 50 + Math.floor(Math.random() * 450);
      await publishCell('ixp.traffic.report', CARRIER_A.fp, {
        peer:    CARRIER_B.name,
        bytes:   mbytes * 1_000_000,
        packets: Math.floor(mbytes * 750),
        window:  '5min',
      });
    } else if (phase === 6) {
      // B withdraws old route (BGP flap)
      await publishCell('ixp.route.withdraw', CARRIER_B.fp, {
        prefix: BGP_PREFIXES[(tick + 1) % BGP_PREFIXES.length],
        reason: 'route_flap',
      });
    } else {
      // A announces another route
      const prefix = BGP_PREFIXES[(tick + 7) % BGP_PREFIXES.length]!;
      await publishCell('ixp.route.accept', CARRIER_A.fp, {
        prefix,
        asPath:    `${CARRIER_A.asn}`,
        nextHop:   '192.168.1.1',
        localPref: 150,
      });
    }
  } catch (e: any) {
    log('⚠', `publish error: ${e.message}`);
  }
}

// ── Summary ───────────────────────────────────────────────────────────────────

function printSummary(): void {
  const elapsed = ((Date.now() - runStartTs) / 1000).toFixed(0);
  console.log('\n' + '═'.repeat(62));
  console.log(`${C.bold}  IXP Carrier Billing Demo — Summary${C.reset}`);
  console.log('═'.repeat(62));
  console.log(`  IXP:              ${IXP_NAME}`);
  console.log(`  Carriers:         ${CARRIER_A.name}  ↔  ${CARRIER_B.name}`);
  console.log(`  Duration:         ${elapsed}s`);
  console.log(`  Routes accepted:  ${stats.routesAccepted}`);
  console.log(`  Routes rejected:  ${stats.routesRejected}`);
  console.log(`  Routes withdrawn: ${stats.routesWithdrawn}`);
  console.log(`  Traffic reports:  ${stats.trafficReports}`);
  console.log(`  Sats advanced:    ${stats.satsAdvanced}`);
  console.log(`  Settlements:      ${stats.settlements.length}`);

  if (stats.settlements.length > 0) {
    console.log(`\n  ${C.bold}${C.cyan}BSV Settlement Receipts${C.reset}`);
    for (const s of stats.settlements) {
      console.log(`  ✓ ${s.txid}`);
      console.log(`    https://whatsonchain.com/tx/${s.txid}`);
    }
  } else {
    console.log(`\n  ${C.dim}No settlements yet — run longer or lower AUTO_SETTLE_SECS on bridge${C.reset}`);
  }

  console.log('\n  Pitch:');
  console.log('  "Your EDI file is a spreadsheet both sides could edit.');
  console.log('   Our settlement record is a Bitcoin transaction ID.');
  console.log('   Go look it up. It was written the moment it settled.');
  console.log('   You cannot change it. Your lawyers cannot change it.');
  console.log('   The IXP cannot change it."');
  console.log('═'.repeat(62) + '\n');
}

// ── Main ──────────────────────────────────────────────────────────────────────

let runStartTs = Date.now();

async function main(): Promise<void> {
  console.log(`\n${C.bold}${C.cyan}  IXP Carrier Bilateral Settlement Demo${C.reset}`);
  console.log(`  ${C.dim}${IXP_NAME} — ${CARRIER_A.name} ↔ ${CARRIER_B.name}${C.reset}`);
  console.log(`  Relay:   ${RELAY_URL}`);
  console.log(`  Bridge:  ${BRIDGE_URL}`);
  console.log(`  Speed:   ${FAST ? '5×' : '1×'}  tick=${TICK_MS}ms`);
  console.log(`\n  ${C.dim}IXP handler subscribes to ixp.* ONLY — typed SSE subscription.${C.reset}`);
  console.log(`  ${C.dim}Proves semantic multicast: inference/sensor cells are invisible to it.${C.reset}\n`);

  runStartTs = Date.now();
  const endTs = DURATION_S > 0 ? Date.now() + DURATION_S * 1000 : Infinity;

  // Start typed subscription handler
  await startIxpHandler();
  await Bun.sleep(500);  // let SSE connect

  process.on('SIGINT', () => {
    printSummary();
    process.exit(0);
  });

  if (ONCE) {
    await simulateTick();
    await Bun.sleep(2000);
    printSummary();
    return;
  }

  while (Date.now() < endTs) {
    await simulateTick();
    await Bun.sleep(TICK_MS);
  }

  printSummary();
}

main().catch(e => { console.error(e); process.exit(1); });

```
