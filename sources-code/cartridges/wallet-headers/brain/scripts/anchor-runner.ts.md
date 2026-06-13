---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/scripts/anchor-runner.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.642836+00:00
---

# cartridges/wallet-headers/brain/scripts/anchor-runner.ts

```ts
#!/usr/bin/env bun
// anchor-runner.ts — long-running anchor processor.
//
// Tails the JSON-lines queue file the brain's anchor_queue_writer.zig
// appends to.  For each new cell.created event, invokes the cartridge
// subscriber + broadcasts via Metanet Desktop.  Tracks last-processed
// offset in a sibling .cursor file so restarts resume cleanly.
//
// Architecture (file-based queue, Todd 2026-05-26 "keep going to wrap
// this all up"):
//
//   brain.AnchorEmitter.emitBsv → broker.publish("cell.created")
//     → anchor_queue_writer.zig appends line to anchor-queue.jsonl
//       → [this script] tails the file
//         → handleCellCreated → real BSV mainnet txid
//
// Why file-based vs in-brain bun-child spawning:
//   • Survives brain restarts (queue is durable on disk).
//   • Decoupled lifecycle: this runner can be stopped/restarted
//     independently of the brain.
//   • Operator can `tail -f anchor-queue.jsonl` to see what's queued
//     without running this script.
//
// Usage:
//   bun cartridges/wallet-headers/brain/scripts/anchor-runner.ts \
//     --queue <path-to-anchor-queue.jsonl> [--poll-ms 1000]
//
//   Environment variables (same as flush-anchor-once.ts):
//     METANET_URL                  default http://localhost:3321
//     METANET_ORIGIN               default http://localhost
//     HAT_SEED                     operator hat seed (REQUIRED for
//                                  production; demo fallback warns
//                                  loudly).  identitySk = SHA-256(seed),
//                                  matching Zig bkds.privFromSeed.
//
// Cursor file: <queue>.cursor — single integer (byte offset of next
// unread byte).  Atomic write via tmpfile + rename.  Missing cursor
// = start from byte 0.

import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { promises as fs } from 'fs';
import {
  handleCellCreated,
  type CellCreatedEvent,
  type IdentityProvider,
  type CreateActionAdapter,
} from '../src/anchor-subscriber';

const DEMO_HAT_SEED = 'flush-anchor-once.ts demo hat (NOT FOR PRODUCTION)';

// ─────────────────────────────────────────────────────────────────────
// CLI parsing
// ─────────────────────────────────────────────────────────────────────

interface ParsedArgs {
  queuePath: string;
  pollMs: number;
}

function parseArgs(argv: string[]): ParsedArgs {
  let queuePath: string | null = null;
  let pollMs = 1000;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === '--queue') {
      queuePath = argv[++i] ?? '';
    } else if (a === '--poll-ms') {
      pollMs = Number.parseInt(argv[++i] ?? '1000', 10);
    } else {
      die(`unknown arg: ${a}`);
    }
  }
  if (!queuePath) die('usage: bun anchor-runner.ts --queue <path-to-anchor-queue.jsonl> [--poll-ms 1000]');
  if (!Number.isFinite(pollMs) || pollMs < 100) die(`--poll-ms must be >= 100 (got ${pollMs})`);
  return { queuePath, pollMs };
}

function die(msg: string): never {
  console.error(`error: ${msg}`);
  process.exit(2);
}

// ─────────────────────────────────────────────────────────────────────
// Identity (hat-scoped, matching flush-anchor-once.ts)
// ─────────────────────────────────────────────────────────────────────

function loadAnchorIdentitySk(): Uint8Array {
  const seed = process.env.HAT_SEED;
  if (seed && seed.length > 0) {
    console.error(`[runner] deriving anchor identitySk from HAT_SEED via SHA-256 (${seed.length} char seed)`);
    return new Uint8Array(nobleSha256(new TextEncoder().encode(seed)));
  }
  console.error(`[runner] WARNING: no HAT_SEED set — using built-in demo seed`);
  console.error(`[runner] WARNING: production runs MUST set HAT_SEED`);
  return new Uint8Array(nobleSha256(new TextEncoder().encode(DEMO_HAT_SEED)));
}

// ─────────────────────────────────────────────────────────────────────
// Hex / cursor helpers
// ─────────────────────────────────────────────────────────────────────

function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

async function readCursor(cursorPath: string): Promise<number> {
  try {
    const txt = await fs.readFile(cursorPath, 'utf-8');
    const n = Number.parseInt(txt.trim(), 10);
    return Number.isFinite(n) && n >= 0 ? n : 0;
  } catch (e: any) {
    if (e?.code === 'ENOENT') return 0;
    throw e;
  }
}

async function writeCursor(cursorPath: string, offset: number): Promise<void> {
  // Atomic write: tmpfile + rename.
  const tmp = `${cursorPath}.tmp`;
  await fs.writeFile(tmp, `${offset}\n`, 'utf-8');
  await fs.rename(tmp, cursorPath);
}

// ─────────────────────────────────────────────────────────────────────
// CreateActionAdapter — same Metanet Desktop wiring as flush-anchor-once.ts
// ─────────────────────────────────────────────────────────────────────

function buildCreateActionAdapter(metanetUrl: string, origin: string): CreateActionAdapter {
  return async params => {
    const o = params.outputs[0]!;
    const scriptHex = bytesToHex(o.lockingScript);
    const body = {
      description: params.description,
      outputs: [
        {
          lockingScript: scriptHex,
          satoshis: o.satoshis,
          outputDescription: params.description,
          tags: [] as string[],
        },
      ],
      labels: [] as string[],
    };
    try {
      const resp = await fetch(`${metanetUrl}/createAction`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Origin: origin },
        body: JSON.stringify(body),
      });
      if (!resp.ok) {
        const text = await resp.text();
        return { ok: false, reason: `createAction ${resp.status}: ${text}` };
      }
      const j = (await resp.json()) as { txid?: string };
      if (typeof j.txid === 'string' && /^[0-9a-fA-F]{64}$/.test(j.txid)) {
        return { ok: true, txid: j.txid.toLowerCase() };
      }
      return { ok: false, reason: `createAction: response missing txid (keys: ${Object.keys(j).join(',')})` };
    } catch (e: any) {
      return { ok: false, reason: `fetch failed: ${e?.message ?? String(e)}` };
    }
  };
}

// ─────────────────────────────────────────────────────────────────────
// Queue-line processing
// ─────────────────────────────────────────────────────────────────────

interface QueueLine {
  event_id: string;
  ts: number;
  type: string;
  payload: {
    cell_hash?: string;
    type_hash?: string;
    entity_tag?: number;
    cartridge_id?: string;
    correlation_id?: string;
  };
}

function parseQueueLine(line: string): QueueLine | null {
  try {
    const obj = JSON.parse(line) as QueueLine;
    if (typeof obj.event_id !== 'string') return null;
    if (typeof obj.type !== 'string') return null;
    if (typeof obj.payload !== 'object' || obj.payload === null) return null;
    return obj;
  } catch {
    return null;
  }
}

function queueLineToEvent(line: QueueLine): CellCreatedEvent | null {
  if (line.type !== 'cell.created') return null;
  const p = line.payload;
  if (typeof p.cell_hash !== 'string' || typeof p.type_hash !== 'string') return null;
  return {
    cell_hash: p.cell_hash,
    type_hash: p.type_hash,
    entity_tag: typeof p.entity_tag === 'number' ? p.entity_tag : 0,
    cartridge_id: typeof p.cartridge_id === 'string' ? p.cartridge_id : '',
    correlation_id: typeof p.correlation_id === 'string' ? p.correlation_id : '',
  };
}

// ─────────────────────────────────────────────────────────────────────
// Main loop
// ─────────────────────────────────────────────────────────────────────

interface RunnerState {
  args: ParsedArgs;
  cursorPath: string;
  /** Sibling file for confirmation feedback (PR-3a-bridge-3).
   *  One line per broadcast outcome; brain-side
   *  anchor_confirmation_reader.zig tails this file + writes audit
   *  log entries. */
  confirmationsPath: string;
  identity: IdentityProvider;
  createAction: CreateActionAdapter;
  shouldStop: boolean;
}

/** Shape of one line in <queue>.confirmations.jsonl.  Stable wire
 *  format — brain reader pattern-matches on `status` to decide
 *  audit-log entry kind. */
interface ConfirmationLine {
  /** Broker event id (echoed from the queue line) so the brain can
   *  correlate confirm-back to the source cell write. */
  event_id: string;
  cell_hash: string;
  type_hash: string;
  status: 'broadcast' | 'failed' | 'skipped';
  /** Populated when status === 'broadcast'. */
  txid?: string;
  /** Populated when status === 'failed' or 'skipped'. */
  error_kind?: string;
  /** Populated when status === 'failed'. */
  detail?: string;
  /** Wall-clock timestamp when the runner finished processing the
   *  event, milliseconds since epoch.  Brain-side audit uses this for
   *  the audit log entry's ts field. */
  processed_at_ms: number;
}

async function appendConfirmation(
  path: string,
  line: ConfirmationLine,
): Promise<void> {
  // Single-line JSON + newline.  Best-effort: a write failure to the
  // confirmations file should NOT stop the runner from processing
  // more events — the runner's stdout still has the txid, the brain
  // just won't get the structured feedback.
  try {
    await fs.appendFile(path, `${JSON.stringify(line)}\n`, 'utf-8');
  } catch (e: any) {
    console.error(`[runner] failed to write confirmation: ${e?.message ?? String(e)}`);
  }
}

async function processNewLines(state: RunnerState): Promise<void> {
  const stat = await fs.stat(state.args.queuePath).catch(() => null);
  if (!stat || !stat.isFile()) return; // queue not yet created
  const cursor = await readCursor(state.cursorPath);
  if (cursor >= stat.size) return; // nothing new

  // Read [cursor, EOF).  Buffer cap chosen large enough for any
  // reasonable backlog; if the file is huge we'd want streaming reads,
  // but for the cell.created queue this fits.
  const fh = await fs.open(state.args.queuePath, 'r');
  try {
    const buf = Buffer.alloc(stat.size - cursor);
    await fh.read(buf, 0, buf.length, cursor);
    const text = buf.toString('utf-8');

    // Split into lines; the LAST line may be incomplete if the brain
    // is mid-write.  Track the offset of the last complete '\n' so we
    // only advance the cursor past complete lines.
    let lineStart = 0;
    let newCursor = cursor;
    for (let i = 0; i < text.length; i++) {
      if (text[i] === '\n') {
        const line = text.slice(lineStart, i);
        await processOneLine(state, line);
        newCursor = cursor + i + 1; // past the newline
        lineStart = i + 1;
      }
    }
    if (newCursor > cursor) await writeCursor(state.cursorPath, newCursor);
  } finally {
    await fh.close();
  }
}

async function processOneLine(state: RunnerState, line: string): Promise<void> {
  if (line.length === 0) return; // tolerate blank line
  const parsed = parseQueueLine(line);
  if (!parsed) {
    console.error(`[runner] skip: malformed queue line`);
    return;
  }
  const event = queueLineToEvent(parsed);
  if (!event) {
    console.error(`[runner] skip: not a cell.created event (type=${parsed.type})`);
    return;
  }
  console.error(
    `[runner] processing event_id=${parsed.event_id} cell_hash=${event.cell_hash.slice(0, 16)}…`,
  );
  const outcome = await handleCellCreated(event, state.identity, state.createAction);

  // PR-3a-bridge-3: write structured confirmation to sibling file so
  // brain-side anchor_confirmation_reader.zig can tail it + audit-log.
  await appendConfirmation(state.confirmationsPath, {
    event_id: parsed.event_id,
    cell_hash: event.cell_hash,
    type_hash: event.type_hash,
    status: outcome.status,
    txid: outcome.status === 'broadcast' ? outcome.txid : undefined,
    error_kind: outcome.error_kind,
    detail: outcome.detail,
    processed_at_ms: Date.now(),
  });

  if (outcome.status === 'broadcast' && outcome.txid) {
    console.log(JSON.stringify({
      event_id: parsed.event_id,
      cell_hash: event.cell_hash,
      type_hash: event.type_hash,
      txid: outcome.txid,
      wo_url: `https://whatsonchain.com/tx/${outcome.txid}`,
    }));
  } else {
    console.error(
      `[runner] event_id=${parsed.event_id} status=${outcome.status}` +
        (outcome.error_kind ? ` error_kind=${outcome.error_kind}` : '') +
        (outcome.detail ? ` detail=${outcome.detail}` : ''),
    );
  }
}

async function main(): Promise<number> {
  const args = parseArgs(process.argv.slice(2));
  const metanetUrl = process.env.METANET_URL ?? 'http://localhost:3321';
  const origin = process.env.METANET_ORIGIN ?? 'http://localhost';

  console.error(`[runner] queue:       ${args.queuePath}`);
  console.error(`[runner] poll_ms:     ${args.pollMs}`);
  console.error(`[runner] metanet_url: ${metanetUrl}`);

  const cursorPath = `${args.queuePath}.cursor`;
  const confirmationsPath = `${args.queuePath}.confirmations.jsonl`;
  const initialCursor = await readCursor(cursorPath);
  console.error(`[runner] cursor:        ${initialCursor} (resuming from byte offset)`);
  console.error(`[runner] confirmations: ${confirmationsPath}`);

  const identitySk = loadAnchorIdentitySk();
  const identity: IdentityProvider = {
    getIdentitySk: () => identitySk,
    // Per-typeHash monotonic counter.  In-memory only — restarts
    // reset to 0, which means restarts will reuse anchor indices for
    // any type_hash seen before the restart.  Acceptable for the
    // demo because each anchor still anchors a UNIQUE cell_hash (the
    // commitment data, not the spending key, is what dedupes the
    // anchors on-chain).  A future PR can persist this counter
    // alongside the cursor file.
    nextAnchorIndex: (() => {
      const counters = new Map<string, number>();
      return (typeHashHex: string) => {
        const cur = counters.get(typeHashHex) ?? 0;
        counters.set(typeHashHex, cur + 1);
        return cur;
      };
    })(),
  };
  const createAction = buildCreateActionAdapter(metanetUrl, origin);

  const state: RunnerState = {
    args,
    cursorPath,
    confirmationsPath,
    identity,
    createAction,
    shouldStop: false,
  };

  process.on('SIGINT', () => {
    console.error(`[runner] SIGINT — finishing current batch then exiting`);
    state.shouldStop = true;
  });
  process.on('SIGTERM', () => {
    console.error(`[runner] SIGTERM — finishing current batch then exiting`);
    state.shouldStop = true;
  });

  console.error(`[runner] entering poll loop`);
  while (!state.shouldStop) {
    try {
      await processNewLines(state);
    } catch (e: any) {
      console.error(`[runner] processNewLines failed: ${e?.message ?? String(e)}`);
    }
    await new Promise(r => setTimeout(r, state.args.pollMs));
  }
  console.error(`[runner] clean exit`);
  return 0;
}

const code = await main();
process.exit(code);

```
