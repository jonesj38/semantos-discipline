---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/demo/swarm-node.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.082651+00:00
---

# runtime/session-protocol/src/swarm/demo/swarm-node.ts

```ts
/**
 * swarm-node — a real, standalone swarm node over actual UDP multicast.
 *
 *   bun run .../swarm-node.ts seed  <file> <tracker-dir>
 *   bun run .../swarm-node.ts fetch <infohash> <tracker-dir> <out-file>
 *
 * Two separate OS processes exchange a file over node:dgram UDP multicast
 * (NodeUdpTransport) — no in-process loopback. The shared tracker is a
 * directory (FileBrainClient). This is the "does it work over real sockets"
 * proof the in-process tests can't give.
 *
 * Transport note: two processes on one host share the multicast port, so
 * per-recipient unicast on that port is unreliable. For this 2-node demo both
 * broadcast AND replies go to the group; the SwarmSession's payload-level
 * filtering (infohash + index + merkle verify) handles delivery. Frames carry a
 * per-process id in the 12-byte header's nodeIdShort field so a node drops its
 * own loopback. Production per-recipient unicast is a follow-up.
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { createSocket } from 'node:dgram';
import { networkInterfaces } from 'node:os';
import { publishFile, fromHex, toHex, sha256 } from '@semantos/protocol-types';
import { PrivateKey } from '@bsv/sdk';
import type { MfpFlowConfig } from '@semantos/protocol-types';
import { SwarmSession, type ServePolicy, type PayPolicy } from '../swarm-session';
import { FileBrainClient } from '../file-brain-client';
import {
  MeteredFlowPayer, MeteredFlowVerifier, MultiChannelServePolicy, meteredFlowPayPolicy, protoWalletPort,
  type ChannelRegistration,
} from '../metered-flow';
import type { SwarmTransport, FrameHandler } from '../swarm-transport';

const FLOW_COMMODITY = 'swarm.cell';
const FLOW_RATE = Number(process.env.SWARM_PRICE_SATS ?? 1);

/** Build the seeder's multi-channel serve policy from a registry file (flow mode). */
function flowServePolicy(): ServePolicy | undefined {
  if (!process.env.SWARM_FLOW_SEEDER_KEY || !process.env.SWARM_FLOW_REGISTRY) return undefined;
  const seederKey = PrivateKey.fromHex(process.env.SWARM_FLOW_SEEDER_KEY);
  const reg = JSON.parse(readFileSync(process.env.SWARM_FLOW_REGISTRY, 'utf8')) as ChannelRegistration[];
  const multi = new MultiChannelServePolicy(new MeteredFlowVerifier(seederKey, FLOW_COMMODITY, FLOW_RATE), FLOW_RATE, reg);
  setInterval(() => {
    const s = multi.channelSummary().map(c => ({ flow: c.flowId, cells: c.cellsServed, owed: Number(c.owedSats) }));
    console.log('CHANNELS ' + JSON.stringify(s));
  }, 1000);
  return multi;
}

/** Build a leecher's metered-flow pay policy (flow mode). */
async function flowPayPolicy(): Promise<PayPolicy | undefined> {
  if (!process.env.SWARM_FLOW_KEY || !process.env.SWARM_FLOW_ID || !process.env.SWARM_SEEDER_PUB) return undefined;
  const cfg: MfpFlowConfig = {
    commodityId: FLOW_COMMODITY, ratePerUnitSats: FLOW_RATE, counterparty: process.env.SWARM_SEEDER_PUB,
    flowId: process.env.SWARM_FLOW_ID, fundMode: 'metered',
    vaultCapSats: 1_000_000n, channelChunkSats: 1_000_000n, refillThresholdSats: 0n,
  };
  const payer = new MeteredFlowPayer(cfg, protoWalletPort(PrivateKey.fromHex(process.env.SWARM_FLOW_KEY)));
  await payer.open(); // fund/open the channel
  return meteredFlowPayPolicy(payer);
}

const PORT = Number(process.env.SWARM_PORT ?? 41999);
// Transport family:
//   udp4 (default) — 239.x multicast, robust for two processes on one host.
//   udp6 + SWARM_IFACE — IPv6 link-local ff02:: on a named interface; the
//     proven Skyminer-mesh path (end0 on the Pis, en8 on the laptop LAN).
//     ff02:: needs an interface scope, hence SWARM_IFACE.
const FAMILY: 'udp4' | 'udp6' = process.env.SWARM_FAMILY === 'udp6' ? 'udp6' : 'udp4';
const GROUP = process.env.SWARM_GROUP ?? (FAMILY === 'udp6' ? 'ff02::6873' : '239.255.41.99');
const IFACE = process.env.SWARM_IFACE; // e.g. en8 (laptop) / end0 (pi); required for udp6
const NODE_ID_OFFSET = 4; // bytes 4..6 of the 12-byte wire header = nodeIdShort (u16 BE)
const DEBUG = !!process.env.SWARM_DEBUG;
const dbg = (...a: unknown[]): void => { if (DEBUG) console.error('[swarm]', ...a); };

/** Numeric IPv6 scope id for an interface (macOS prefers this over the name). */
function ifaceScopeId(name?: string): number | undefined {
  if (!name) return undefined;
  for (const a of networkInterfaces()[name] ?? []) {
    const sid = (a as { family?: string; scopeid?: number }).scopeid;
    if ((a.family === 'IPv6' || (a.family as unknown) === 6) && sid) return sid;
  }
  return undefined;
}

function multicastDemoTransport(label: string): SwarmTransport {
  const sock = createSocket({ type: FAMILY, reuseAddr: true });
  const myId = (process.pid * 2654435761) & 0xffff;
  const handlers: FrameHandler[] = [];
  // bun's os.networkInterfaces() omits scopeid, and macOS won't honour a
  // name-scope for multicast egress — so allow a numeric SWARM_SCOPE override
  // (e.g. `ifconfig en8` → "scopeid 0x16" → SWARM_SCOPE=22).
  const scope = FAMILY === 'udp6'
    ? (process.env.SWARM_SCOPE ? Number(process.env.SWARM_SCOPE) : ifaceScopeId(IFACE))
    : undefined;
  // macOS honours a NUMERIC scope in the destination far more reliably than
  // the interface name; fall back to the name, then bare group.
  const sendAddr = FAMILY === 'udp6' && IFACE ? `${GROUP}%${scope ?? IFACE}` : GROUP;
  const tag = (frame: Uint8Array): Uint8Array => {
    const f = frame.slice();
    if (f.length >= NODE_ID_OFFSET + 2) new DataView(f.buffer).setUint16(NODE_ID_OFFSET, myId, false);
    return f;
  };
  sock.on('message', (msg: Buffer, rinfo) => {
    if (msg.length >= NODE_ID_OFFSET + 2) {
      const id = new DataView(msg.buffer, msg.byteOffset, msg.byteLength).getUint16(NODE_ID_OFFSET, false);
      if (id === myId) return; // our own looped-back multicast
    }
    dbg(`rx msg=0x${(msg[1] ?? 0).toString(16)} from=${rinfo.address} len=${msg.length}`);
    for (const h of handlers) h(new Uint8Array(msg), rinfo.address);
  });
  return {
    localAddress: () => label,
    async start() {
      await new Promise<void>((resolve, reject) => {
        sock.once('error', reject);
        sock.bind(PORT, () => {
          try {
            if (FAMILY === 'udp6' && IFACE) sock.addMembership(GROUP, IFACE);
            else sock.addMembership(GROUP);
          } catch (e) { dbg('addMembership failed', String(e)); }
          // Select the multicast egress interface (try numeric scope, then name).
          let set = false;
          const cands = FAMILY === 'udp6'
            ? [scope && `::%${scope}`, IFACE && `::%${IFACE}`]
            : [IFACE];
          for (const c of cands.filter(Boolean) as string[]) {
            try { sock.setMulticastInterface(c); dbg('setMulticastInterface', c); set = true; break; }
            catch (e) { dbg('setMulticastInterface failed', c, String(e)); }
          }
          if (!set) dbg('no multicast egress interface set');
          try { sock.setMulticastLoopback(true); } catch { /* ignore */ }
          sock.removeListener('error', reject);
          dbg(`bound family=${FAMILY} group=${GROUP} iface=${IFACE} scope=${scope} send=${sendAddr} port=${PORT}`);
          resolve();
        });
      });
    },
    async stop() {
      handlers.length = 0;
      sock.close();
    },
    async broadcast(frame) {
      dbg(`tx msg=0x${(frame[1] ?? 0).toString(16)} -> ${sendAddr} (bcast)`);
      sock.send(tag(frame), PORT, sendAddr);
    },
    async sendTo(_address, frame) {
      dbg(`tx msg=0x${(frame[1] ?? 0).toString(16)} -> ${sendAddr} (uni)`);
      sock.send(tag(frame), PORT, sendAddr); // 2-node demo: multicast + filter
    },
    onFrame(h) {
      handlers.push(h);
    },
  };
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);

  if (cmd === 'seed') {
    const [file, dir] = rest;
    if (!file || !dir) throw new Error('usage: seed <file> <tracker-dir>');
    const bytes = new Uint8Array(readFileSync(file));
    const published = publishFile(bytes, file);
    const session = new SwarmSession({ transport: multicastDemoTransport('seed'), brain: new FileBrainClient(dir), servePolicy: flowServePolicy() });
    await session.seed(published);
    console.log(`SEED infohash=${toHex(published.infohash)} cells=${published.manifest.totalCells} bytes=${bytes.length}`);
    console.log('SEED ready — serving over UDP multicast on ' + GROUP + ':' + PORT);
    await new Promise(() => {}); // serve until killed
  } else if (cmd === 'fetch') {
    const [infohashHex, dir, outfile] = rest;
    if (!infohashHex || !dir || !outfile) throw new Error('usage: fetch <infohash> <tracker-dir> <out-file>');
    const session = new SwarmSession({ transport: multicastDemoTransport('leech'), brain: new FileBrainClient(dir), payPolicy: await flowPayPolicy() });
    const t0 = Date.now();
    const got = await session.download(fromHex(infohashHex));
    writeFileSync(outfile, got);
    console.log(`FETCH ok bytes=${got.length} ms=${Date.now() - t0} sha256=${toHex(sha256(got))}`);
    if (process.env.SWARM_STAY) {
      // Stay alive and serve what we just fetched — a leecher becomes a seeder
      // (peer-assist: the file survives the original seeder leaving).
      console.log('STAY — now seeding the fetched file to the swarm');
      await new Promise(() => {});
    }
    await session.stop();
    process.exit(0);
  } else {
    console.error('usage: swarm-node.ts seed <file> <tracker-dir> | fetch <infohash> <tracker-dir> <out-file>');
    process.exit(2);
  }
}

void main();

```
