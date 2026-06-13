---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/pi1-subnet-proxy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.411220+00:00
---

# cartridges/inference-gate/pi1-subnet-proxy.ts

```ts
#!/usr/bin/env bun
/**
 * pi1-proxy.ts
 * Transparent TCP proxy running on Pi #1 (192.168.0.2 / 192.168.20.8)
 * Bridges 192.168.0.x Pis → laptop services at 192.168.20.5
 * Ports: 5199 (relay), 5201 (registry), 5202 (coordinator)
 */

import net from 'net';

const LAPTOP_IP = process.env.LAPTOP_IP || '192.168.20.5';
const PORTS     = [5199, 5201, 5202];

for (const port of PORTS) {
  const server = net.createServer(socket => {
    const proxy = net.createConnection(port, LAPTOP_IP);
    socket.pipe(proxy);
    proxy.pipe(socket);
    const cleanup = () => { try { socket.destroy(); } catch {} try { proxy.destroy(); } catch {} };
    socket.on('error', cleanup);
    proxy.on('error', cleanup);
    socket.on('close', cleanup);
    proxy.on('close', cleanup);
  });

  server.listen(port, '0.0.0.0', () => {
    console.log(`[proxy] 0.0.0.0:${port} → ${LAPTOP_IP}:${port}`);
  });
}

console.log(`[proxy] Pi #1 bridge running (laptop=${LAPTOP_IP}). Ctrl+C to stop.`);

```
