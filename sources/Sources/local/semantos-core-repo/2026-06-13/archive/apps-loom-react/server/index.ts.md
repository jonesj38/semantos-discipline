---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/server/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.930825+00:00
---

# archive/apps-loom-react/server/index.ts

```ts
import { loadExtensionConfigs, watchConfigs } from './config-loader';
import { loadWorkspace, saveWorkspace } from './state';

const PORT = 3001;
const clients = new Set<any>();
let configs = await loadExtensionConfigs();

// Watch for config changes
watchConfigs(() => {
  loadExtensionConfigs().then(updated => {
    configs = updated;
    for (const ws of clients) {
      ws.send(JSON.stringify({ type: 'config_changed', payload: { ids: Object.keys(configs) } }));
    }
  });
});

Bun.serve({
  port: PORT,
  fetch(req, server) {
    const url = new URL(req.url);

    // Upgrade WebSocket
    if (url.pathname === '/ws') {
      if (server.upgrade(req)) return undefined;
      return new Response('WebSocket upgrade failed', { status: 500 });
    }

    // API routes
    if (url.pathname === '/api/extensions') {
      const list = Object.entries(configs).map(([id, c]) => ({ id, name: (c as any).name }));
      return Response.json(list);
    }

    const extensionMatch = url.pathname.match(/^\/api\/extensions\/(.+)$/);
    if (extensionMatch) {
      const id = extensionMatch[1];
      if (configs[id]) return Response.json(configs[id]);
      return new Response('Not found', { status: 404 });
    }

    const wsMatch = url.pathname.match(/^\/api\/workspace\/(.+)$/);
    if (wsMatch) {
      const extensionId = wsMatch[1];
      if (req.method === 'GET') {
        const data = loadWorkspace(extensionId);
        return Response.json(data ?? {});
      }
      if (req.method === 'PUT') {
        return req.json().then(body => {
          saveWorkspace(extensionId, body);
          return Response.json({ ok: true });
        });
      }
    }

    return new Response('Not found', { status: 404 });
  },
  websocket: {
    open(ws) {
      clients.add(ws);
    },
    message(ws, msg) {
      // Broadcast state updates to other clients
      const data = typeof msg === 'string' ? msg : new TextDecoder().decode(msg as ArrayBuffer);
      for (const client of clients) {
        if (client !== ws) client.send(data);
      }
    },
    close(ws) {
      clients.delete(ws);
    },
  },
});

console.log(`Workbench server running on http://localhost:${PORT}`);

```
