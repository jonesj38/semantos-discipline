---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/udp-multicast-transport.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.051611+00:00
---

# runtime/session-protocol/src/swarm/udp-multicast-transport.ts

```ts
/**
 * udpMulticastTransport — a real SwarmTransport over node:dgram multicast.
 *
 * The production data-plane transport for a standalone node/daemon. udp4
 * (239.x, robust on one switch) or udp6 link-local (ff02::, needs an interface
 * scope — name on Linux, numeric scope on macOS via `scope`). Frames carry a
 * per-process id in the 12-byte wire header so a node drops its own loopback;
 * replies go to the group (payload-level filtering handles delivery), which is
 * the simple multi-node model — production per-recipient unicast is a follow-on.
 */

import { createSocket } from 'node:dgram';
import { networkInterfaces } from 'node:os';
import type { SwarmTransport, FrameHandler } from './swarm-transport';

const NODE_ID_OFFSET = 4; // bytes 4..6 of the wire header = nodeIdShort (u16 BE)

export interface UdpMulticastOptions {
  family?: 'udp4' | 'udp6';
  /** Multicast group (default 239.255.41.99 / ff02::6873). */
  group?: string;
  port?: number;
  /** Interface name (end0 / en8 …); required for udp6 link-local. */
  iface?: string;
  /** Numeric IPv6 scope override (macOS — `ifconfig <iface>` → "scopeid 0x.."). */
  scope?: number;
  /** This node's label (used as localAddress for announce/attribution). */
  label?: string;
  /** Multicast loopback (default true — lets co-located processes see each other). */
  loopback?: boolean;
  debug?: boolean;
}

function ifaceScopeId(name?: string): number | undefined {
  if (!name) return undefined;
  for (const a of networkInterfaces()[name] ?? []) {
    const sid = (a as { family?: string; scopeid?: number }).scopeid;
    if ((a.family === 'IPv6' || (a.family as unknown) === 6) && sid) return sid;
  }
  return undefined;
}

export function udpMulticastTransport(opts: UdpMulticastOptions = {}): SwarmTransport {
  const family: 'udp4' | 'udp6' = opts.family ?? 'udp4';
  const group = opts.group ?? (family === 'udp6' ? 'ff02::6873' : '239.255.41.99');
  const port = opts.port ?? 41999;
  const iface = opts.iface;
  const scope = family === 'udp6' ? (opts.scope ?? ifaceScopeId(iface)) : undefined;
  const sendAddr = family === 'udp6' && iface ? `${group}%${scope ?? iface}` : group;
  const label = opts.label ?? `${family}:${port}`;
  const dbg = (...a: unknown[]) => { if (opts.debug) console.error('[udp]', ...a); };

  const sock = createSocket({ type: family, reuseAddr: true });
  const myId = (process.pid * 2654435761) & 0xffff;
  const handlers: FrameHandler[] = [];
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
    for (const h of handlers) h(new Uint8Array(msg), rinfo.address);
  });

  return {
    localAddress: () => label,
    async start() {
      await new Promise<void>((resolve, reject) => {
        sock.once('error', reject);
        sock.bind(port, () => {
          try {
            if (family === 'udp6' && iface) sock.addMembership(group, iface);
            else sock.addMembership(group);
          } catch (e) { dbg('addMembership failed', String(e)); }
          for (const c of (family === 'udp6' ? [scope && `::%${scope}`, iface && `::%${iface}`] : [iface]).filter(Boolean) as string[]) {
            try { sock.setMulticastInterface(c); break; } catch (e) { dbg('setMulticastInterface failed', c, String(e)); }
          }
          try { sock.setMulticastLoopback(opts.loopback ?? true); } catch { /* ignore */ }
          sock.removeListener('error', reject);
          dbg(`bound ${family} ${group}:${port} iface=${iface} send=${sendAddr}`);
          resolve();
        });
      });
    },
    async stop() { handlers.length = 0; sock.close(); },
    async broadcast(frame) { sock.send(tag(frame), port, sendAddr); },
    async sendTo(_address, frame) { sock.send(tag(frame), port, sendAddr); },
    onFrame(h) { handlers.push(h); },
  };
}

```
