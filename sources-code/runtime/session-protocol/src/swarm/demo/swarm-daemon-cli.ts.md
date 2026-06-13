---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/demo/swarm-daemon-cli.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.083520+00:00
---

# runtime/session-protocol/src/swarm/demo/swarm-daemon-cli.ts

```ts
/**
 * swarm-daemon-cli — a standalone paid-swarm client daemon.
 *
 *   bun run .../swarm-daemon-cli.ts [--rpc 8420] [--family udp4|udp6]
 *      [--group 239.255.41.99] [--port 41999] [--iface en0] [--scope 22]
 *      [--tracker /tmp/swarm-tracker]
 *
 * Runs the multi-torrent engine over real UDP multicast and exposes the
 * JSON-RPC control API over HTTP — the headless client a UI (or `curl`) drives:
 *
 *   curl -s localhost:8420/rpc -d '{"method":"seed","params":{"path":"./x.bin"}}'
 *   curl -s localhost:8420/rpc -d '{"method":"add","params":{"infohash":"…","out":"./x.out"}}'
 *   curl -s localhost:8420/rpc -d '{"method":"list"}'
 *
 * Payments are off by default (free swarm). The wallet seam (headless bundle or
 * BRC-100 / Metanet Desktop) is wired in swarm-wallet.ts and selected here once
 * configured — see that file.
 */

import type { MfpFlowConfig } from '@semantos/protocol-types';
import { SwarmClient } from '../swarm-client';
import { SwarmDaemon, serveSwarmDaemon } from '../swarm-daemon';
import { udpMulticastTransport } from '../udp-multicast-transport';
import { wssSwarmTransport } from '../swarm-wss-relay';
import type { SwarmTransport } from '../swarm-transport';
import { FileBrainClient } from '../file-brain-client';
import { LayeredBrainClient, InMemorySeederRegistry } from '../layered-brain-client';
import { MeteredFlowPayer, meteredFlowPayPolicy } from '../metered-flow';
import { resolveWalletPort, type WalletSpec } from '../swarm-wallet';
import type { PayPolicy } from '../swarm-session';

function arg(name: string, def?: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : def;
}

async function main() {
  const rpcPort = Number(arg('rpc', '8420'));
  const family = (arg('family', 'udp4') as 'udp4' | 'udp6');
  const group = arg('group');
  const port = Number(arg('port', '41999'));
  const iface = arg('iface');
  const scope = arg('scope') ? Number(arg('scope')) : undefined;
  const tracker = arg('tracker', '/tmp/swarm-tracker')!;
  const label = arg('label', `${family}-${rpcPort}`);

  // Wallet seam — bundled headless key, or any BRC-100 wallet (Metanet Desktop
  // / browser). Paid downloads need the seeder's payee pubkey (--payee).
  const walletMode = (arg('wallet', 'none') as 'none' | 'headless' | 'brc100');
  const payee = arg('payee');
  let payPolicy: PayPolicy | undefined;
  if (walletMode !== 'none' && payee) {
    const spec: WalletSpec = walletMode === 'headless'
      ? { mode: 'headless', keyHex: process.env.BRIDGE_WALLET_KEY ?? '' }
      : { mode: 'brc100' };
    const walletPort = resolveWalletPort(spec)!;
    const cfg: MfpFlowConfig = {
      commodityId: 'swarm.cell', ratePerUnitSats: Number(arg('price', '1')), counterparty: payee,
      flowId: Buffer.from(crypto.getRandomValues(new Uint8Array(8))).toString('hex'),
      fundMode: 'metered', vaultCapSats: 1_000_000n, channelChunkSats: 1_000_000n, refillThresholdSats: 0n,
    };
    const flowPayer = new MeteredFlowPayer(cfg, walletPort);
    await flowPayer.open();
    payPolicy = meteredFlowPayPolicy(flowPayer);
  }

  // Data plane: UDP multicast (LAN) or a WSS relay (cross-internet — peers dial
  // out to the relay, so no inbound/NAT rules). `--transport wss --relay <url>`.
  const transportMode = arg('transport', 'udp') as 'udp' | 'wss';
  const relay = arg('relay');
  const room = arg('room', 'swarm');
  const transport: SwarmTransport = transportMode === 'wss'
    ? wssSwarmTransport({ url: relay ?? 'ws://localhost:8431', room, id: label })
    : udpMulticastTransport({ family, group, port, iface, scope, label, debug: !!process.env.SWARM_DEBUG });

  // The torrent client is one consumer of the transfer primitive: discovery goes
  // through LayeredBrainClient (brain → overlay SLAP → UHRP). The local file
  // tracker is the brain leg; an InMemorySeederRegistry stands in for the overlay
  // registry until live SHIP/SLAP adapters (TopicManagerClient/LookupServiceClient)
  // are injected here (a deploy step — needs overlay hosts + a wallet).
  const brain = new LayeredBrainClient({
    inner: new FileBrainClient(tracker),
    registry: new InMemorySeederRegistry(),
  });
  const client = new SwarmClient({ transport, brain, payPolicy });
  const daemon = new SwarmDaemon(client);
  const h = serveSwarmDaemon(daemon, rpcPort);

  console.log(`━━━ swarm daemon up ━━━`);
  console.log(`control API : http://localhost:${h.port}/rpc  (methods: seed, add, list, remove, wallet)`);
  console.log(transportMode === 'wss'
    ? `data plane  : WSS relay ${relay ?? 'ws://localhost:8431'} room=${room} (cross-internet)`
    : `data plane  : ${family} multicast ${group ?? (family === 'udp6' ? 'ff02::6873' : '239.255.41.99')}:${port}${iface ? ' iface=' + iface : ''}`);
  console.log(`discovery   : layered (file tracker ${tracker} → overlay SLAP → UHRP)`);
  console.log(`wallet      : ${walletMode}${payee ? ` (paying downloads → ${payee.slice(0, 16)}…)` : ' (free swarm)'}`);

  const shutdown = async () => { await h.stop(); process.exit(0); };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
  await new Promise(() => {}); // run until killed
}

void main();

```
