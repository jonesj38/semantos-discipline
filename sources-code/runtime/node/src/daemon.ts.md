---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/daemon.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.303398+00:00
---

# runtime/node/src/daemon.ts

```ts
#!/usr/bin/env bun
/**
 * Semantos node daemon — long-running process.
 *
 * Loads NodeConfig from JSON, creates and starts the node,
 * starts the admin API, and handles graceful shutdown.
 *
 * Cross-references:
 *   protocol-types/src/node.ts — createNode()
 *   protocol-types/src/node-config-loader.ts — loadNodeConfig()
 *   packages/node/src/api/server.ts — startAdminApi()
 */

import { createNode, loadNodeConfig } from '@semantos/protocol-types';
import { startAdminApi, type AdminApiOptions } from './api/server';
import {
  loadLicenseFromDisk,
  validateLicenseForBoot,
  evaluateNodeCapAuthorizationFromConfig,
} from './license-policy';
import { startFederation, type FederationHandle } from './federation';

export interface DaemonOptions {
  configPath?: string;
  adminPort?: number;
  certsDir?: string;
}

export async function createDaemon(options: DaemonOptions = {}) {
  const configPath = options.configPath
    ?? process.env.SEMANTOS_CONFIG
    ?? '/etc/semantos/node.json';

  const certsDir = options.certsDir
    ?? process.env.SEMANTOS_CERTS_DIR
    ?? '/etc/semantos/certs';

  const adminPort = options.adminPort
    ?? Number(process.env.SEMANTOS_ADMIN_PORT ?? 6443);

  console.log(`[semantos] Loading config from ${configPath}`);
  const config = await loadNodeConfig(configPath);

  // Phase 35B: refuse to start without a valid license when license.path
  // is configured. Pre-35B clusters (no license block) keep booting as
  // before — enforcement only kicks in once a license path is declared.
  if (config.license?.path) {
    console.log(`[semantos] Loading license from ${config.license.path}`);
    const { license } = await loadLicenseFromDisk(config.license.path);
    const verdict = await validateLicenseForBoot(license, {
      devMode: config.license.devMode,
    });
    if (!verdict.ok) {
      console.error(
        `[semantos] FATAL: license rejected (${verdict.reason})` +
          (verdict.detail ? `: ${verdict.detail}` : ''),
      );
      process.exit(1);
    }
    console.log(
      `[semantos] License accepted` +
        (verdict.devIssued ? ' (dev-issuer)' : ''),
    );
  }

  console.log(`[semantos] Creating node (cert: ${config.nodeCert})`);
  const node = await createNode(config);

  console.log('[semantos] Starting node...');
  await node.start();

  console.log(`[semantos] Starting admin API on port ${adminPort}`);
  const api = startAdminApi({
    node,
    port: adminPort,
    certsDir,
  });

  // NL-1 (SELLABLE-NODE-LICENSE.md N3 "Layer") — cap-UTXO
  // authorization / kill-switch layer, orthogonal to the signed-License
  // identity gate above. ADDITIVE: not configured ⇒ Phase-35B
  // behaviour. Unauthorized (spent / SPV-fail / wrong holder) ⇒
  // DISABLE federation but DO NOT exit — local sovereign use + data
  // isolation survive the kill-switch (N3).
  const capAuth = await evaluateNodeCapAuthorizationFromConfig(config);
  if (capAuth.configured) {
    if (capAuth.authorized) {
      console.log(`[semantos] Node-license cap-UTXO authorized — network participation enabled`);
    } else {
      console.log(
        `[semantos] Node-license unauthorized — federation disabled ` +
          `(local use + data isolation unaffected): ${capAuth.reason}`,
      );
    }
  }

  // Phase 35B.1 federation — boot WsNodeAdapter when both license.path and
  // license.privateKeyPath are configured AND (NL-1) the cap-UTXO
  // authorization layer is satisfied. The upstream license-policy gate
  // has already validated the signed-License identity; this starts the
  // actual transport.
  let federation: FederationHandle | undefined;
  if (config.license?.path && config.license?.privateKeyPath && capAuth.authorized) {
    console.log(`[semantos] Starting federation plane...`);
    federation = await startFederation(config, {
      log: (tag, msg) => console.log(`[federation/${tag}] ${msg}`),
    });
    console.log(
      `[semantos] Federation listening on port ${federation.adapter.listeningPort} as ${federation.bca}`,
    );
  }

  console.log(`[semantos] Node running`);
  console.log(`  Admin API:  https://localhost:${adminPort}/api/node/status`);
  console.log(`  Node cert:  ${config.nodeCert}`);
  console.log(`  Extensions:  ${config.extensions.join(', ')}`);
  if (federation) {
    console.log(`  Federation: ws://0.0.0.0:${federation.adapter.listeningPort}/session`);
    console.log(`  Discovery:  /.well-known/semantos-node`);
  }

  // Graceful shutdown
  const shutdown = async () => {
    console.log('\n[semantos] Shutting down...');
    if (federation) await federation.stop();
    api.stop();
    await node.stop();
    console.log('[semantos] Stopped.');
    process.exit(0);
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);

  return { node, api, federation };
}

// Run as main process if invoked directly
if (import.meta.main) {
  createDaemon().catch(err => {
    console.error('[semantos] Fatal:', err.message);
    process.exit(1);
  });
}

```
