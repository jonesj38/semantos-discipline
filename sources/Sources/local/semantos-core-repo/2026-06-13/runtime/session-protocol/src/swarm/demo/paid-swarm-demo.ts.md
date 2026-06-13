---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/demo/paid-swarm-demo.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.082271+00:00
---

# runtime/session-protocol/src/swarm/demo/paid-swarm-demo.ts

```ts
/**
 * Runnable paid-swarm demo — the full M0–M4 data plane in one process.
 *
 *   bun run runtime/session-protocol/src/swarm/demo/paid-swarm-demo.ts
 *
 * Spins up a seeder and a leecher over the in-process loopback UDP transport,
 * publishes a file, runs the paid download (prepay model), verifies every cell
 * against the manifest root, reassembles, and settles receipts to the (fake)
 * brain ledger — printing a human-readable trace at each step. No real socket,
 * no real wallet, no Zig brain: this is the TS data plane proving itself.
 */

import { LoopbackUdpTransport } from '@semantos/protocol-types/adapters/udp-transport';
import { publishFile, bytesEqual, sha256, toHex } from '@semantos/protocol-types';
import type { EconomicPort } from '@semantos/identity-ports';
import { udpSwarmTransport } from '../swarm-transport';
import { FakeBrainClient } from '../brain-client';
import { SwarmSession } from '../swarm-session';
import { PaidSeeder, makePayPolicy } from '../paid-seeder';

const PORT = 49000;
const GROUP = 'ff02::demo-swarm';
const PRICE_SATS = 7;

/** Shared-ledger stub economy (a leecher's signSpend validates on the seeder). */
function stubEconomy() {
  const ledger = new Map<string, { amount: number; currency: string }>();
  let seq = 0;
  const port = (): EconomicPort => ({
    signSpend: async input => {
      const anchor = toHex(sha256(new TextEncoder().encode(`${input.payerCertId}|${input.targetId}|${input.amount}|${input.memo}|${seq++}`)));
      ledger.set(anchor, { amount: input.amount, currency: input.currency });
      return { txAnchor: anchor, amount: input.amount, currency: input.currency, verifier: 'stub' };
    },
    verifyPayment: async ({ txAnchor, amount, currency }) => {
      const e = ledger.get(txAnchor);
      if (!e || e.currency !== currency || amount > e.amount) return { valid: false, reason: 'bad', verifier: 'stub' };
      return { valid: true, verifier: 'stub' };
    },
  });
  return { port };
}

function makeTransport(addr: string) {
  return udpSwarmTransport({ udp: new LoopbackUdpTransport(addr), address: addr, port: PORT, group: GROUP });
}

function sampleFile(bytes: number): Uint8Array {
  const b = new Uint8Array(bytes);
  for (let i = 0; i < bytes; i++) b[i] = (i * 131 + 7) & 0xff; // deterministic, not all-same
  return b;
}

async function main() {
  const FILE_BYTES = 64 * 1024; // 64 KiB
  const file = sampleFile(FILE_BYTES);

  console.log('━━━ paid-swarm demo (TS data plane, loopback) ━━━\n');
  const published = publishFile(file, 'demo/payload.bin');
  console.log(`file            : ${FILE_BYTES} bytes ("demo/payload.bin")`);
  console.log(`chunked into    : ${published.manifest.totalCells} cells × ${published.manifest.chunkSize}B payload`);
  console.log(`infohash        : ${toHex(published.infohash)}`);
  console.log(`merkle root     : ${toHex(published.manifest.merkleRoot)}`);
  console.log(`manifest cell   : ${published.manifestCell.length} bytes (one cell, any file size)\n`);

  const brain = new FakeBrainClient();
  const economy = stubEconomy();

  const paidSeeder = new PaidSeeder({ economic: economy.port(), pricePerCellSats: PRICE_SATS });
  const seeder = new SwarmSession({ transport: makeTransport('fe80::seed'), brain, servePolicy: paidSeeder });
  const leecher = new SwarmSession({
    transport: makeTransport('fe80::leech'),
    brain,
    payPolicy: makePayPolicy({ economic: economy.port(), payerCertId: 'demo-leecher', pricePerCellSats: PRICE_SATS }),
  });

  console.log('seeder          : publishing manifest + serving (price ' + PRICE_SATS + ' sat/cell)…');
  await seeder.seed(published);

  console.log('leecher         : locating + downloading (prepay per cell)…\n');
  const t0 = performance.now();
  const got = await leecher.download(published.infohash);
  const ms = (performance.now() - t0).toFixed(1);

  const bytesOk = bytesEqual(got, file);
  const hashOk = bytesEqual(sha256(got), published.manifest.contentHash);
  console.log(`download        : ${got.length} bytes in ${ms} ms`);
  console.log(`bytes match     : ${bytesOk ? '✓' : '✗ MISMATCH'}`);
  console.log(`content hash    : ${hashOk ? '✓ verified against manifest' : '✗ MISMATCH'}`);

  const recorded = await seeder.flushReceipts();
  const receipts = brain.receiptsFor(published.infohash);
  const sats = receipts.reduce((a, r) => a + r.amount, 0);
  console.log(`settlement      : ${recorded} receipts journaled, ${sats} sats collected (${PRICE_SATS} × ${published.manifest.totalCells})\n`);

  await seeder.stop();
  await leecher.stop();
  LoopbackUdpTransport.resetAll();

  const ok = bytesOk && hashOk && recorded === published.manifest.totalCells && sats === PRICE_SATS * published.manifest.totalCells;
  console.log(ok ? '━━━ RESULT: OK ✓ ━━━' : '━━━ RESULT: FAILED ✗ ━━━');
  process.exit(ok ? 0 : 1);
}

void main();

```
