---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/cold-chain/demo.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.415094+00:00
---

# cartridges/cold-chain/demo.ts

```ts
#!/usr/bin/env bun
/**
 * cold-chain/demo.ts — Temperature sensor simulation with BSV audit anchoring
 *
 * WHY THIS EXISTS
 * ───────────────
 * Cold chain compliance is a billion-dollar pain point: food logistics, pharma
 * distribution, and vaccine storage all require tamper-proof evidence that
 * product stayed within temperature bounds throughout transit.  Current
 * solutions are loggers with proprietary software — auditors get a CSV file
 * that can be edited.
 *
 * This demo shows the alternative:
 *   Every temperature reading → a cell on the mesh
 *   Every threshold breach    → a PushDrop tx on BSV (immutable, txid)
 *   Any auditor gets a txid   → re-derive the breach record, compare to sensor log
 *
 * "You can't edit a Bitcoin txid." — Todd
 *
 * WHAT IT SIMULATES
 * ─────────────────
 * A refrigerated truck carrying fresh produce (target: 2°C, max allowed: 8°C).
 * Temperature follows a 24-hour sine wave with realistic door-open events
 * (temporary +4 to +10°C spikes).  Breach = >8°C sustained for >BREACH_SECS.
 *
 * CELL TYPES PUBLISHED
 * ────────────────────
 *   cold-chain.sensor.reading    — every INTERVAL_MS (default 3s)
 *   cold-chain.event.door-open   — when a door-open spike begins
 *   cold-chain.alert.breach      — when threshold exceeded for BREACH_SECS
 *   cold-chain.alert.restored    — when temperature drops back below threshold
 *
 * The breach alert is also anchored on BSV mainnet (if METANET_URL is set).
 *
 * USAGE
 * ─────
 *   bun cartridges/cold-chain/demo.ts                        # mock mode, no relay needed
 *   RELAY_URL=http://localhost:5199 bun demo.ts              # publish to live relay
 *   SENSOR_ID=truck-007 THRESHOLD_C=4.0 bun demo.ts          # pharma-grade threshold
 *   METANET_URL=http://localhost:3321 bun demo.ts             # anchor breaches on BSV
 *   DURATION_S=120 bun demo.ts                               # run for 2 minutes then exit
 *   bun demo.ts --fast                                       # 10× speed (0.3s ticks)
 *
 * ENVIRONMENT
 * ───────────
 *   RELAY_URL      http://localhost:5199   Multicast relay endpoint
 *   SENSOR_ID      sensor-001              Unique device identifier
 *   LOCATION       cold-chain-zone-A       Human-readable location tag
 *   THRESHOLD_C    8.0                     Breach temperature in °C
 *   BREACH_SECS    30                      Seconds above threshold to trigger alert
 *   INTERVAL_MS    3000                    Milliseconds between readings
 *   DURATION_S     0                       0 = run forever; >0 = exit after N seconds
 *   METANET_URL    (empty)                 Metanet Desktop URL; empty = dry-run anchor
 *   HAT_SEED       cold-chain-demo         Anchor key derivation seed
 */

import { createHash, randomBytes } from 'node:crypto';

// ── Config ────────────────────────────────────────────────────────────────────

const RELAY_URL   = process.env.RELAY_URL    ?? '';
const SENSOR_ID   = process.env.SENSOR_ID    ?? 'sensor-001';
const LOCATION    = process.env.LOCATION     ?? 'truck-zone-A';
const THRESHOLD_C = parseFloat(process.env.THRESHOLD_C ?? '8.0');
const BREACH_SECS = parseInt(process.env.BREACH_SECS   ?? '30', 10);
const DURATION_S  = parseInt(process.env.DURATION_S    ?? '0',  10);
const METANET_URL = process.env.METANET_URL  ?? '';
const HAT_SEED    = process.env.HAT_SEED     ?? 'cold-chain-demo';
const FAST        = process.argv.includes('--fast');
const INTERVAL_MS = FAST
  ? Math.round(parseInt(process.env.INTERVAL_MS ?? '3000', 10) / 10)
  : parseInt(process.env.INTERVAL_MS ?? '3000', 10);

const SENSOR_FP = createHash('sha256').update(SENSOR_ID).digest('hex').slice(0, 8);

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
  white:  '\x1b[97m',
  bg_red: '\x1b[41m',
};

function log(prefix: string, msg: string) {
  const ts = new Date().toLocaleTimeString();
  console.log(`[${ts}] ${prefix} ${msg}`);
}

// ── Temperature model ─────────────────────────────────────────────────────────
// Baseline: 2°C fridge target with gentle daily sine wave (-1 to +1°C amplitude)
// Door-open events: +4 to +10°C spikes, ~60-120s duration, random probability

interface SensorState {
  baseC:         number;   // current baseline temperature
  doorOpenUntil: number;   // timestamp when current door event ends (0 = closed)
  doorPeakC:     number;   // peak spike temp for current door event
  nextDoorCheck: number;   // next timestamp to randomly check for door event
}

const sensorState: SensorState = {
  baseC:         2.0,
  doorOpenUntil: 0,
  doorPeakC:     0,
  nextDoorCheck: Date.now() + 20_000,
};

function readTemperature(now: number): number {
  // Daily sine wave: ±0.5°C over 24hr, slowed to ±0.5 over DEMO_PERIOD
  const DEMO_PERIOD_MS = FAST ? 120_000 : 3_600_000;  // 2 min (fast) or 1 hr (normal)
  const dailySine = 0.5 * Math.sin((2 * Math.PI * now) / DEMO_PERIOD_MS);

  // Small sensor noise
  const noise = (Math.random() - 0.5) * 0.3;

  // Door-open spike
  if (now < sensorState.doorOpenUntil) {
    const progress = (sensorState.doorOpenUntil - now) / 90_000;  // decay over 90s
    const spike = sensorState.doorPeakC * (1 - Math.pow(progress, 2));
    return sensorState.baseC + dailySine + noise + spike;
  }

  // Randomly open door every ~2-5 min (in real time; 12-30s in fast mode)
  if (now > sensorState.nextDoorCheck) {
    if (Math.random() < 0.4) {
      // Door open event — temperature spikes 4-10°C above baseline
      const spike = 4 + Math.random() * 6;
      const duration = FAST
        ? (15_000 + Math.random() * 30_000)
        : (60_000 + Math.random() * 90_000);

      sensorState.doorOpenUntil = now + duration;
      sensorState.doorPeakC     = spike;
      log('🚪', `${C.yellow}Door open event — expected peak +${spike.toFixed(1)}°C, ~${(duration / 1000).toFixed(0)}s${C.reset}`);
    }
    const nextGap = FAST
      ? (12_000 + Math.random() * 18_000)
      : (120_000 + Math.random() * 180_000);
    sensorState.nextDoorCheck = now + nextGap;
  }

  return sensorState.baseC + dailySine + noise;
}

// ── Cell publishing ───────────────────────────────────────────────────────────

let seq = 0;

async function publishCell(typePath: string, data: Record<string, unknown>): Promise<string | null> {
  const payload    = JSON.stringify({ sensorId: SENSOR_ID, sensorFp: SENSOR_FP, location: LOCATION, ...data });
  const payloadHex = Buffer.from(payload, 'utf8').toString('hex');
  const cellId     = createHash('sha256').update(payloadHex).digest('hex');
  seq++;

  const body = {
    header: {
      cellId,
      typePath,
      senderFp: SENSOR_FP,
      seq,
      payloadLen: payload.length,
    },
    payload: payloadHex,
  };

  if (!RELAY_URL) {
    // Dry-run: log without publishing
    return cellId;
  }

  try {
    const r = await fetch(`${RELAY_URL}/publish`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify(body),
      signal:  AbortSignal.timeout(3000),
    });
    return r.ok ? cellId : null;
  } catch {
    return null;
  }
}

// ── BSV anchor ────────────────────────────────────────────────────────────────
// When a breach is confirmed, anchor the event on BSV mainnet using PushDrop.
// The anchor payload is the breach summary; the txid is the immutable receipt.

interface BreachRecord {
  sensorId:      string;
  location:      string;
  breachStartTs: number;
  peakTempC:     number;
  durationSecs:  number;
  readingCount:  number;
  thresholdC:    number;
  breachCellId:  string;
}

async function anchorBreach(record: BreachRecord): Promise<string | null> {
  const breachJson = JSON.stringify(record);
  const dataHex    = Buffer.from(breachJson, 'utf8').toString('hex');

  // Stable type hash for cold-chain breach anchors
  const TYPE_HASH = createHash('sha256').update('cold-chain.alert.breach.v1').digest('hex');
  // Data hash: SHA-256 of the breach record
  const dataHash  = createHash('sha256').update(breachJson).digest('hex');
  // Cell hash: type_hash || data_hash
  const cellHash  = createHash('sha256').update(TYPE_HASH + dataHash).digest('hex');

  log('⛓ ', `${C.cyan}Anchoring breach on BSV — cellHash ${cellHash.slice(0, 12)}…${C.reset}`);
  log('⛓ ', `${C.dim}${breachJson.slice(0, 120)}…${C.reset}`);

  if (!METANET_URL) {
    // Dry-run — show what would be anchored
    const fakeTxid = createHash('sha256').update(cellHash + Date.now()).digest('hex');
    log('⛓ ', `${C.dim}[DRY RUN] Metanet Desktop not configured (METANET_URL not set)${C.reset}`);
    log('⛓ ', `${C.dim}[DRY RUN] Would anchor: ${dataHex.slice(0, 40)}… OP_DROP <pubkey> OP_CHECKSIG${C.reset}`);
    log('⛓ ', `${C.dim}[DRY RUN] Simulated txid: ${fakeTxid}${C.reset}`);
    return `dry-run:${fakeTxid}`;
  }

  // Real path — same recipe proven in MNCA anchor / CashLanes settlements:
  // POST /v1/createAction with a PushDrop locking script
  try {
    const r = await fetch(`${METANET_URL}/v1/createAction`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        description: `Cold-chain breach: ${record.sensorId} ${record.location} ${record.peakTempC.toFixed(1)}°C`,
        outputs: [{
          satoshis: 1,
          lockingScript: [
            dataHex,             // breach record data
            'OP_DROP',
            '210279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',  // secp256k1 G (demo key)
            'OP_CHECKSIG',
          ].join(' '),
          outputDescription: `Cold-chain breach anchor: ${record.sensorId}`,
        }],
      }),
      signal: AbortSignal.timeout(30_000),
    });

    if (!r.ok) {
      const err = await r.text().catch(() => '');
      log('⛓ ', `${C.red}Anchor failed HTTP ${r.status}: ${err.slice(0, 80)}${C.reset}`);
      return null;
    }

    const { txid } = await r.json() as { txid?: string };
    return txid ?? null;
  } catch (e: any) {
    log('⛓ ', `${C.red}Anchor error: ${e.message}${C.reset}`);
    return null;
  }
}

// ── Breach tracker ────────────────────────────────────────────────────────────

interface BreachState {
  active:       boolean;
  startTs:      number;
  peakTempC:    number;
  readingCount: number;
  alerted:      boolean;  // breach cell published + anchor attempted
}

const breach: BreachState = {
  active:       false,
  startTs:      0,
  peakTempC:    0,
  readingCount: 0,
  alerted:      false,
};

// ── Run stats ─────────────────────────────────────────────────────────────────

const runStats = {
  startTs:       Date.now(),
  readings:      0,
  cellsPublished: 0,
  cellsFailed:   0,
  breachCount:   0,
  anchorTxids:   [] as string[],
  maxTempC:      -Infinity,
  minTempC:       Infinity,
};

// ── Temperature bar ───────────────────────────────────────────────────────────

function tempBar(tempC: number): string {
  const MIN = -2, MAX = 14;
  const clamped = Math.max(MIN, Math.min(MAX, tempC));
  const width   = 20;
  const pos     = Math.round(((clamped - MIN) / (MAX - MIN)) * width);
  const thPos   = Math.round(((THRESHOLD_C - MIN) / (MAX - MIN)) * width);

  const bar = Array.from({ length: width }, (_, i) => {
    if (i === pos) return '●';
    if (i === thPos) return '|';
    return i < pos ? '▓' : '░';
  }).join('');

  const color = tempC > THRESHOLD_C ? C.red : tempC > THRESHOLD_C - 2 ? C.yellow : C.cyan;
  return `${color}${bar}${C.reset}`;
}

// ── Main loop ─────────────────────────────────────────────────────────────────

async function tick(): Promise<void> {
  const now   = Date.now();
  const tempC = readTemperature(now);
  runStats.readings++;
  runStats.maxTempC = Math.max(runStats.maxTempC, tempC);
  runStats.minTempC = Math.min(runStats.minTempC, tempC);

  const aboveThreshold = tempC > THRESHOLD_C;

  // Update breach state
  if (aboveThreshold && !breach.active) {
    breach.active       = true;
    breach.startTs      = now;
    breach.peakTempC    = tempC;
    breach.readingCount = 1;
    breach.alerted      = false;
  } else if (aboveThreshold && breach.active) {
    breach.peakTempC    = Math.max(breach.peakTempC, tempC);
    breach.readingCount++;
  } else if (!aboveThreshold && breach.active) {
    // Temperature restored
    const durationSecs = (now - breach.startTs) / 1000;

    if (breach.alerted) {
      // Publish restored cell
      const restoredId = await publishCell('cold-chain.alert.restored', {
        ts:           now,
        tempC:        parseFloat(tempC.toFixed(2)),
        breachSecs:   durationSecs.toFixed(1),
        peakTempC:    breach.peakTempC.toFixed(2),
        readingCount: breach.readingCount,
      });
      if (restoredId) runStats.cellsPublished++;
      log('✅', `${C.green}${C.bold}Restored — breach lasted ${durationSecs.toFixed(0)}s, peak ${breach.peakTempC.toFixed(1)}°C${C.reset}`);
    }

    breach.active       = false;
    breach.alerted      = false;
    breach.startTs      = 0;
    breach.peakTempC    = 0;
    breach.readingCount = 0;
  }

  // Breach alert — only fire once per breach event, after BREACH_SECS elapsed
  if (breach.active && !breach.alerted) {
    const durationSecs = (now - breach.startTs) / 1000;
    if (durationSecs >= BREACH_SECS) {
      breach.alerted = true;
      runStats.breachCount++;

      const breachRecord: BreachRecord = {
        sensorId:      SENSOR_ID,
        location:      LOCATION,
        breachStartTs: breach.startTs,
        peakTempC:     parseFloat(breach.peakTempC.toFixed(2)),
        durationSecs:  parseFloat(durationSecs.toFixed(1)),
        readingCount:  breach.readingCount,
        thresholdC:    THRESHOLD_C,
        breachCellId:  '',  // filled after publish
      };

      console.log('');
      log('🚨', `${C.bg_red}${C.white}${C.bold} BREACH CONFIRMED ${C.reset} ${tempC.toFixed(1)}°C > ${THRESHOLD_C}°C for ${durationSecs.toFixed(0)}s`);

      // Publish breach cell
      const breachId = await publishCell('cold-chain.alert.breach', {
        ts:           now,
        tempC:        parseFloat(tempC.toFixed(2)),
        thresholdC:   THRESHOLD_C,
        breachSecs:   durationSecs.toFixed(1),
        peakTempC:    breach.peakTempC.toFixed(2),
        readingCount: breach.readingCount,
        breachStartTs: breach.startTs,
        breachNumber:  runStats.breachCount,
      });

      if (breachId) {
        runStats.cellsPublished++;
        breachRecord.breachCellId = breachId;
        log('📡', `${C.cyan}Breach cell: ${breachId.slice(0, 16)}…${C.reset}`);
      }

      // Anchor on BSV
      const txid = await anchorBreach(breachRecord);
      if (txid) {
        runStats.anchorTxids.push(txid);
        const isDryRun = txid.startsWith('dry-run:');
        if (isDryRun) {
          log('⛓ ', `${C.dim}Simulated txid: ${txid.replace('dry-run:', '').slice(0, 20)}…${C.reset}`);
        } else {
          log('⛓ ', `${C.green}${C.bold}BSV txid: ${txid}${C.reset}`);
          log('⛓ ', `${C.dim}https://whatsonchain.com/tx/${txid}${C.reset}`);
        }
      }
      console.log('');
    }
  }

  // Publish reading cell
  const breachDurationSecs = breach.active ? (now - breach.startTs) / 1000 : 0;
  const cellId = await publishCell('cold-chain.sensor.reading', {
    ts:          now,
    tempC:       parseFloat(tempC.toFixed(2)),
    thresholdC:  THRESHOLD_C,
    aboveThresh: aboveThreshold,
    breachSecs:  aboveThreshold ? parseFloat(breachDurationSecs.toFixed(1)) : 0,
    doorOpen:    Date.now() < sensorState.doorOpenUntil,
  });

  if (cellId) runStats.cellsPublished++;
  else if (RELAY_URL) runStats.cellsFailed++;

  // Console output
  const tempStr   = `${tempC.toFixed(2).padStart(6)}°C`;
  const bar       = tempBar(tempC);
  const relay     = RELAY_URL ? (cellId ? `${C.green}✓${C.reset}` : `${C.red}✗${C.reset}`) : `${C.dim}dry${C.reset}`;
  const breachSfx = breach.active
    ? (breach.alerted
        ? ` ${C.red}${C.bold}⚠ BREACH ${breachDurationSecs.toFixed(0)}s${C.reset}`
        : ` ${C.yellow}⚠ ${breachDurationSecs.toFixed(0)}s/${BREACH_SECS}s${C.reset}`)
    : '';

  log('🌡 ', `${C.bold}${tempStr}${C.reset}  ${bar}  ${relay}${breachSfx}`);
}

async function printSummary(): Promise<void> {
  const durationS = (Date.now() - runStats.startTs) / 1000;
  console.log('\n' + '═'.repeat(60));
  console.log(`${C.bold}  Cold Chain Demo Summary${C.reset}`);
  console.log('═'.repeat(60));
  console.log(`  Sensor:          ${SENSOR_ID} (${LOCATION})`);
  console.log(`  Duration:        ${durationS.toFixed(0)}s`);
  console.log(`  Readings:        ${runStats.readings}`);
  console.log(`  Temp range:      ${runStats.minTempC.toFixed(2)}°C — ${runStats.maxTempC.toFixed(2)}°C`);
  console.log(`  Threshold:       ${THRESHOLD_C}°C (alert after ${BREACH_SECS}s)`);
  console.log(`  Breach alerts:   ${runStats.breachCount}`);
  console.log(`  Cells published: ${runStats.cellsPublished}${runStats.cellsFailed ? ` (${runStats.cellsFailed} failed)` : ''}`);

  if (runStats.anchorTxids.length > 0) {
    console.log(`\n  ${C.bold}${C.cyan}BSV Anchor Receipts${C.reset}`);
    for (const txid of runStats.anchorTxids) {
      if (txid.startsWith('dry-run:')) {
        console.log(`  ${C.dim}[dry-run] ${txid.replace('dry-run:', '').slice(0, 40)}…${C.reset}`);
      } else {
        console.log(`  ${C.green}✓ ${txid}${C.reset}`);
        console.log(`    https://whatsonchain.com/tx/${txid}`);
      }
    }
  } else {
    console.log(`\n  ${C.dim}No anchors (set METANET_URL=http://localhost:3321 for real txids)${C.reset}`);
  }

  console.log('\n  Pitch: "Every temperature breach has a Bitcoin txid.');
  console.log('  You cannot edit a confirmed transaction.');
  console.log('  Your cold chain compliance record IS the blockchain."');
  console.log('═'.repeat(60) + '\n');
}

async function main() {
  console.log(`\n${C.bold}${C.cyan}  Cold Chain Monitor${C.reset}  ${new Date().toLocaleString()}`);
  console.log(`  Sensor: ${SENSOR_ID}  Location: ${LOCATION}`);
  console.log(`  Threshold: ${THRESHOLD_C}°C  Breach alert: >${BREACH_SECS}s above threshold`);
  console.log(`  Interval: ${INTERVAL_MS}ms  ${FAST ? '(10× FAST mode)' : ''}`);
  console.log(`  Relay: ${RELAY_URL || 'not configured (dry-run mode)'}`);
  console.log(`  Anchor: ${METANET_URL || 'dry-run (set METANET_URL for real txids)'}`);
  console.log(`\n  ← ${(THRESHOLD_C - 2).toFixed(0)}°C     |thresh=${THRESHOLD_C}°C          14°C →\n`);

  const endTs = DURATION_S > 0 ? Date.now() + DURATION_S * 1000 : Infinity;

  process.on('SIGINT', async () => {
    console.log('\n  Interrupted');
    await printSummary();
    process.exit(0);
  });

  while (Date.now() < endTs) {
    await tick();
    await Bun.sleep(INTERVAL_MS);
  }

  await printSummary();
}

main().catch(e => { console.error(e); process.exit(1); });

```
