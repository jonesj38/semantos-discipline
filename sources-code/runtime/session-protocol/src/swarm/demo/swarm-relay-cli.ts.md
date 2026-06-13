---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/demo/swarm-relay-cli.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.083822+00:00
---

# runtime/session-protocol/src/swarm/demo/swarm-relay-cli.ts

```ts
/**
 * swarm-relay-cli — a standalone WSS swarm relay (the cross-internet rendezvous).
 *
 *   bun run .../swarm-relay-cli.ts [--port 8431]
 *
 * Peers (daemons / shells) connect with `--transport wss --relay ws://host:8431`,
 * join a room, and the relay fans swarm frames within the room. It's a dumb
 * frame switch — no swarm logic, no payment visibility (payments are end-to-end
 * inside the frames). Run one of these on a public host and any two peers behind
 * NATs can transfer (they both dial OUT).
 */

import { serveSwarmRelay } from '../swarm-wss-relay';

function arg(name: string, def?: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : def;
}

const port = Number(arg('port', '8431'));
const relay = serveSwarmRelay(port);

console.log(`━━━ swarm WSS relay up ━━━`);
console.log(`listening   : ws://0.0.0.0:${relay.port}`);
console.log(`peers connect: --transport wss --relay ws://<host>:${relay.port} --room <room>`);

setInterval(() => {
  const rooms = relay.rooms();
  const summary = Object.entries(rooms).map(([r, n]) => `${r}=${n}`).join(' ') || '(no peers)';
  if (process.env.SWARM_DEBUG) console.log(`rooms: ${summary}`);
}, 5000);

const shutdown = async () => { await relay.stop(); process.exit(0); };
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

```
