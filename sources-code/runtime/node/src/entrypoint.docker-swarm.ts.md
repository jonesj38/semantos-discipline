---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/entrypoint.docker-swarm.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.304752+00:00
---

# runtime/node/src/entrypoint.docker-swarm.ts

```ts
#!/usr/bin/env bun
/**
 * Docker swarm bot entrypoint — reads BOT_INDEX and BOT_PERSONA env vars,
 * assembles adapters, creates a Semantos node, and joins the mesh.
 *
 * Cross-references:
 *   daemon.ts — standard node entrypoint (pattern reference)
 *   bot-personas.ts — persona definitions
 *   multicast-adapter.ts — network transport (runtime/session-protocol)
 *   Phase 35A PRD — D35A.3
 */

import { createNode } from '@semantos/protocol-types';
import { MemoryAdapter } from '@semantos/protocol-types';
import { StubIdentityAdapter } from '@semantos/protocol-types';
import { StubAnchorAdapter } from '@semantos/protocol-types';
import { NodeUdpTransport } from '@semantos/protocol-types';
import {
  MulticastAdapter,
  DeterministicBCAProvider,
  type TxidProvider,
} from '@semantos/session-protocol';
import { personaForIndex, personaNameForIndex, getPersonaByName } from './bot-personas';

const BOT_INDEX = Number(process.env.BOT_INDEX ?? '0');
const BOT_PERSONA = process.env.BOT_PERSONA ?? personaNameForIndex(BOT_INDEX);

if (Number.isNaN(BOT_INDEX) || BOT_INDEX < 0) {
  console.error(`[bot] Invalid BOT_INDEX: ${process.env.BOT_INDEX}`);
  process.exit(1);
}

const persona = getPersonaByName(BOT_PERSONA) ?? personaForIndex(BOT_INDEX);
const bcaProvider = new DeterministicBCAProvider(BOT_INDEX);

async function main() {
  const bca = await bcaProvider.deriveBCA();
  console.log(`[bot-${BOT_INDEX}] Starting: persona=${persona.name}, bca=${bca}`);

  // Assemble adapters
  const storage = new MemoryAdapter();
  const identity = new StubIdentityAdapter();
  const anchor = new StubAnchorAdapter();

  const transport = new NodeUdpTransport(bca);

  // Counter-based txid provider — matches the old adapter's internal behaviour.
  // Replace with the settlement-backed provider once wired (Phase 35B).
  let txidCounter = 0;
  const txidProvider: TxidProvider = {
    async mint(_cellBytes: Uint8Array): Promise<string> {
      txidCounter++;
      return (
        'mc' +
        BOT_INDEX.toString(16).padStart(4, '0') +
        txidCounter.toString(16).padStart(58, '0')
      );
    },
  };

  const network = new MulticastAdapter({
    identity: bcaProvider,
    transport,
    txidProvider,
    port: 5683,
    primaryGroup: 'ff02::1',
  });

  // Create and start node
  const node = await createNode({
    nodeCert: `bot-${BOT_INDEX}`,
    extensions: ['poker'],
    storage: { type: 'memory' },
    identity: { mode: 'stub' as const },
    anchor: { mode: 'stub' as const },
    network: { mode: 'direct' as const },
    adapters: { storage, identity, anchor, network },
  });

  await node.start();
  await network.start();

  console.log(`[bot-${BOT_INDEX}] Node running, mesh joined`);
  console.log(`[bot-${BOT_INDEX}] Persona: ${persona.name} — ${persona.description}`);

  // Graceful shutdown
  const shutdown = async () => {
    console.log(`\n[bot-${BOT_INDEX}] Shutting down...`);
    await network.stop();
    await node.stop();
    console.log(`[bot-${BOT_INDEX}] Stopped.`);
    process.exit(0);
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch(err => {
  console.error(`[bot-${BOT_INDEX}] Fatal:`, err.message);
  process.exit(1);
});

```
