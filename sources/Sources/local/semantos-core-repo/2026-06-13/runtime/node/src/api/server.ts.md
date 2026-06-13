---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/api/server.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.309931+00:00
---

# runtime/node/src/api/server.ts

```ts
/**
 * Admin API server — Bun.serve with mutual TLS on port 6443.
 *
 * All endpoints require a valid client certificate signed by the node CA.
 * Requests without a valid cert receive 401 Unauthorized.
 *
 * Cross-references:
 *   Phase 26G PRD (D26G.4) — admin API specification
 *   packages/loom/server/index.ts — Bun.serve pattern reference
 *   packages/node/src/api/routes.ts — route handler functions
 *   packages/node/src/api/tls.ts — TLS configuration
 */

import type { SemantosNode } from '@semantos/protocol-types';
import type { Server } from 'bun';
import { loadTlsConfig, type TlsConfig } from './tls';
import { error } from './envelope';
import {
  handleGetStatus,
  handleGetSelf,
  handleGetExtensions,
  handleInstallExtension,
  handleDeleteExtension,
  handleGetIdentities,
  handleGetIdentity,
  handleCreateIdentity,
  handleRevokeIdentity,
  handleAnchorNow,
  handleGetAnchorInterval,
  handleSetAnchorInterval,
  handleGetAnchors,
  handleShellCommand,
} from './routes';

export interface AdminApiOptions {
  node: SemantosNode;
  port?: number;
  certsDir?: string;
  tlsConfig?: TlsConfig;
}

export interface AdminApiHandle {
  server: Server;
  stop(): void;
}

/**
 * Start the admin API server with mutual TLS.
 *
 * If certsDir is provided, loads TLS config from disk.
 * If tlsConfig is provided directly, uses that (for testing).
 * If neither is provided, starts without TLS (development only).
 */
export function startAdminApi(options: AdminApiOptions): AdminApiHandle {
  const { node, port = 6443 } = options;

  let tls: any = undefined;
  if (options.tlsConfig) {
    tls = {
      cert: options.tlsConfig.cert,
      key: options.tlsConfig.key,
      ca: options.tlsConfig.ca,
      requestCert: true,
      rejectUnauthorized: true,
    };
  } else if (options.certsDir) {
    const config = loadTlsConfig(options.certsDir);
    tls = {
      cert: config.cert,
      key: config.key,
      ca: config.ca,
      requestCert: true,
      rejectUnauthorized: true,
    };
  }

  const server = Bun.serve({
    port,
    tls,
    async fetch(req) {
      const url = new URL(req.url);
      const { pathname } = url;
      const method = req.method;

      // ── Node Status ──
      if (pathname === '/api/node/status' && method === 'GET') {
        return handleGetStatus(node);
      }

      // ── Node Self-Object ──
      if (pathname === '/api/node/self' && method === 'GET') {
        return handleGetSelf(node);
      }

      // ── Extensions ──
      if (pathname === '/api/node/extensions' && method === 'GET') {
        return handleGetExtensions(node);
      }
      if (pathname === '/api/node/extensions/install' && method === 'POST') {
        return handleInstallExtension(node, req);
      }
      const extensionDelete = pathname.match(/^\/api\/node\/extensions\/(.+)$/);
      if (extensionDelete && method === 'DELETE') {
        return handleDeleteExtension(node, decodeURIComponent(extensionDelete[1]));
      }

      // ── Identities ──
      if (pathname === '/api/node/identities' && method === 'GET') {
        return handleGetIdentities(node);
      }
      if (pathname === '/api/node/identities' && method === 'POST') {
        return handleCreateIdentity(node, req);
      }
      const identityRevoke = pathname.match(
        /^\/api\/node\/identities\/(.+)\/revoke$/,
      );
      if (identityRevoke && method === 'POST') {
        return handleRevokeIdentity(node, decodeURIComponent(identityRevoke[1]));
      }
      const identityGet = pathname.match(/^\/api\/node\/identities\/(.+)$/);
      if (identityGet && method === 'GET') {
        return handleGetIdentity(node, decodeURIComponent(identityGet[1]));
      }

      // ── Anchors ──
      if (pathname === '/api/node/anchor' && method === 'POST') {
        return handleAnchorNow(node);
      }
      if (pathname === '/api/node/anchor/interval' && method === 'GET') {
        return handleGetAnchorInterval(node);
      }
      if (pathname === '/api/node/anchor/interval' && method === 'PUT') {
        return handleSetAnchorInterval(node, req);
      }
      if (pathname === '/api/node/anchors' && method === 'GET') {
        return handleGetAnchors(node);
      }

      // ── Shell ──
      if (pathname === '/api/node/shell' && method === 'POST') {
        return handleShellCommand(node, req);
      }

      return error('NOT_FOUND', `No route for ${method} ${pathname}`, 404);
    },
  });

  return {
    server,
    stop() {
      server.stop(true);
    },
  };
}

```
