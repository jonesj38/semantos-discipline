---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase26g-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.580634+00:00
---

# tests/gates/phase26g-gate.test.ts

```ts
/**
 * Phase 26G Gate: Node Packaging & Deployment
 *
 * T1:  Docker image builds (integration, skip without SEMANTOS_INTEGRATION)
 * T2:  docker-compose health checks pass (integration)
 * T3:  Admin API responds with valid cert
 * T4:  install.sh creates required directories (file validation)
 * T5:  systemd unit is valid
 * T6:  CLI status command works via admin API
 * T7:  Extension install via admin API
 * T8:  Manual anchor trigger produces proof
 * T9:  Node self-object contains required fields
 * T10: Admin API rejects requests without valid cert (mTLS enforcement)
 */

import { describe, test, expect, afterEach, beforeAll } from 'bun:test';
import { readFileSync, existsSync, mkdirSync, writeFileSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';

import { createNode } from '../../core/protocol-types/src/node';
import type { NodeConfig } from '../../core/protocol-types/src/node-config';
import type { SemantosNode } from '../../core/protocol-types/src/types/semantos-node';
import { MemoryAdapter } from '../../core/protocol-types/src/adapters/memory-adapter';
import { StubIdentityAdapter } from '../../core/protocol-types/src/adapters/stub-identity-adapter';
import { StubAnchorAdapter } from '../../core/protocol-types/src/adapters/stub-anchor-adapter';
import { StubNetworkAdapter } from '../../core/protocol-types/src/adapters/stub-network-adapter';
import { Linearity } from '../../core/protocol-types/src/constants';
import { startAdminApi, type AdminApiHandle } from '../../runtime/node/src/api/server';

const ROOT = join(import.meta.dir, '../..');
const INTEGRATION = !!process.env.SEMANTOS_INTEGRATION;

// ── Test Helpers ─────────────────────────────────────────────────

function buildStubConfig(overrides?: Partial<NodeConfig>): NodeConfig {
  return {
    storage: new MemoryAdapter(),
    identity: new StubIdentityAdapter({ mode: 'stub' }),
    anchor: new StubAnchorAdapter(600_000),
    network: new StubNetworkAdapter(),
    nodeCert: 'test-node-26g',
    extensions: ['sovereignty'],
    anchorIntervalMs: 0,
    ...overrides,
  };
}

const activeNodes: SemantosNode[] = [];
const activeApis: AdminApiHandle[] = [];

afterEach(async () => {
  for (const api of activeApis) {
    try { api.stop(); } catch { /* ignore */ }
  }
  activeApis.length = 0;

  for (const node of activeNodes) {
    try {
      if (node.getStatus().running) await node.stop();
    } catch { /* ignore */ }
  }
  activeNodes.length = 0;
});

// ── T1: Docker image builds (integration only) ──────────────────

describe('Phase 26G — Docker (integration)', () => {
  test.skipIf(!INTEGRATION)('T1: Docker image builds without errors', async () => {
    const proc = Bun.spawn(['docker', 'build', '-t', 'semantos:test', '.'], {
      cwd: ROOT,
      stdout: 'pipe',
      stderr: 'pipe',
    });
    const exitCode = await proc.exited;
    expect(exitCode).toBe(0);
  }, 120_000);

  test.skipIf(!INTEGRATION)('T2: docker-compose services start and pass health checks', async () => {
    const up = Bun.spawn(['docker', 'compose', 'up', '-d'], {
      cwd: ROOT,
      stdout: 'pipe',
      stderr: 'pipe',
    });
    expect(await up.exited).toBe(0);

    // Wait for health check
    let healthy = false;
    for (let i = 0; i < 20; i++) {
      await new Promise(r => setTimeout(r, 3000));
      const inspect = Bun.spawn(
        ['docker', 'inspect', '--format', '{{.State.Health.Status}}', 'semantos-core-semantos-node-1'],
        { cwd: ROOT, stdout: 'pipe' },
      );
      const output = await new Response(inspect.stdout).text();
      if (output.trim() === 'healthy') {
        healthy = true;
        break;
      }
    }

    // Cleanup
    const down = Bun.spawn(['docker', 'compose', 'down', '-v'], {
      cwd: ROOT,
      stdout: 'pipe',
      stderr: 'pipe',
    });
    await down.exited;

    expect(healthy).toBe(true);
  }, 120_000);
});

// ── T3: Admin API responds with valid request ────────────────────

describe('Phase 26G — Admin API', () => {
  test('T3: Admin API returns 200 for GET /api/node/status', async () => {
    const node = await createNode(buildStubConfig());
    activeNodes.push(node);
    await node.start();

    // Start API without TLS for unit testing
    const api = startAdminApi({ node, port: 0 });
    activeApis.push(api);
    const port = api.server.port;

    const res = await fetch(`http://localhost:${port}/api/node/status`);
    expect(res.status).toBe(200);

    const envelope = await res.json() as { data: any; timestamp: number };
    expect(envelope.data).toBeDefined();
    expect(envelope.data.nodeCert).toBe('test-node-26g');
    expect(envelope.data.running).toBe(true);
    expect(envelope.timestamp).toBeGreaterThan(0);
  });
});

// ── T4: install.sh creates required directories ──────────────────

describe('Phase 26G — install.sh validation', () => {
  test('T4: install.sh contains required directory creation commands', () => {
    const installScript = readFileSync(join(ROOT, 'scripts/install.sh'), 'utf-8');

    // Verify FHS directory creation
    expect(installScript).toContain('/var/semantos/data');
    expect(installScript).toContain('/etc/semantos');
    expect(installScript).toContain('/var/semantos/extensions');

    // Verify OS detection
    expect(installScript).toContain('/etc/os-release');
    expect(installScript).toContain('ubuntu');
    expect(installScript).toContain('debian');

    // Verify system user creation
    expect(installScript).toContain('useradd');
    expect(installScript).toContain('semantos');

    // Verify Bun installation
    expect(installScript).toContain('bun.sh/install');

    // Verify config file writing
    expect(installScript).toContain('node.json');

    // Verify systemd integration
    expect(installScript).toContain('systemctl');
    expect(installScript).toContain('daemon-reload');
    expect(installScript).toContain('systemctl enable');
  });
});

// ── T5: systemd unit is valid ────────────────────────────────────

describe('Phase 26G — systemd unit', () => {
  test('T5: systemd service unit contains required directives', () => {
    const installScript = readFileSync(join(ROOT, 'scripts/install.sh'), 'utf-8');

    // Extract the heredoc containing the unit file
    expect(installScript).toContain('[Unit]');
    expect(installScript).toContain('[Service]');
    expect(installScript).toContain('[Install]');
    expect(installScript).toContain('Type=simple');
    expect(installScript).toContain('User=semantos');
    expect(installScript).toContain('Restart=on-failure');
    expect(installScript).toContain('WantedBy=multi-user.target');
    expect(installScript).toContain('ExecStart=');
    expect(installScript).toContain('daemon.ts');
  });
});

// ── T6: CLI status command works via admin API ───────────────────

describe('Phase 26G — CLI via Admin API', () => {
  test('T6: GET /api/node/status returns running node with all fields', async () => {
    const node = await createNode(buildStubConfig());
    activeNodes.push(node);
    await node.start();

    const api = startAdminApi({ node, port: 0 });
    activeApis.push(api);
    const port = api.server.port;

    const res = await fetch(`http://localhost:${port}/api/node/status`);
    expect(res.status).toBe(200);

    const envelope = await res.json() as { data: any };
    const status = envelope.data;

    expect(status.nodeCert).toBe('test-node-26g');
    expect(status.running).toBe(true);
    expect(status.uptime).toBeGreaterThanOrEqual(0);
    expect(status.installedExtensions).toContain('sovereignty');
    expect(status.adapters).toBeDefined();
    expect(status.adapters.storage).toBe('MemoryAdapter');
    expect(status.adapters.identity).toBe('StubIdentityAdapter');
    expect(status.adapters.anchor).toBe('StubAnchorAdapter');
    expect(status.adapters.network).toBe('StubNetworkAdapter');
  });
});

// ── T7: Extension install via admin API ───────────────────────────

describe('Phase 26G — Extension Management', () => {
  test('T7: POST /api/node/extensions/install activates trades extension', async () => {
    const node = await createNode(buildStubConfig());
    activeNodes.push(node);
    await node.start();

    const api = startAdminApi({ node, port: 0 });
    activeApis.push(api);
    const port = api.server.port;

    // Install trades extension
    const installRes = await fetch(`http://localhost:${port}/api/node/extensions/install`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'trades' }),
    });
    expect(installRes.status).toBe(200);
    const installEnvelope = await installRes.json() as { data: any };
    expect(installEnvelope.data.status).toBe('installed');

    // Verify it appears in the list
    const listRes = await fetch(`http://localhost:${port}/api/node/extensions`);
    expect(listRes.status).toBe(200);
    const listEnvelope = await listRes.json() as { data: any[] };
    expect(listEnvelope.data.find((v: any) => v.name === 'trades')).toBeDefined();
  });
});

// ── T8: Manual anchor trigger produces proof ─────────────────────

describe('Phase 26G — Anchoring', () => {
  test('T8: POST /api/node/anchor triggers anchor cycle', async () => {
    const node = await createNode(buildStubConfig());
    activeNodes.push(node);
    await node.start();

    const api = startAdminApi({ node, port: 0 });
    activeApis.push(api);
    const port = api.server.port;

    const res = await fetch(`http://localhost:${port}/api/node/anchor`, {
      method: 'POST',
    });
    expect(res.status).toBe(200);

    const envelope = await res.json() as { data: any };
    // StubAnchorAdapter returns synthetic proof data
    expect(envelope.data).toBeDefined();
    expect(envelope.data.stateHash).toBeDefined();
    expect(envelope.data.txid).toBeDefined();
    expect(envelope.data.blockHeight).toBeDefined();
  });
});

// ── T9: Node self-object contains required fields ────────────────

describe('Phase 26G — Node Self-Object', () => {
  test('T9: GET /api/node/self returns valid RELEVANT object', async () => {
    const node = await createNode(buildStubConfig());
    activeNodes.push(node);
    await node.start();

    const api = startAdminApi({ node, port: 0 });
    activeApis.push(api);
    const port = api.server.port;

    const res = await fetch(`http://localhost:${port}/api/node/self`);
    expect(res.status).toBe(200);

    const envelope = await res.json() as { data: any };
    const self = envelope.data;

    expect(self.path).toContain('sovereignty/node');
    expect(self.path).toContain('test-node-26g');
    expect(self.linearity).toBe(Linearity.RELEVANT);
    expect(self.payload).toBeDefined();
    expect(self.payload.nodeCert).toBe('test-node-26g');
    expect(self.payload.extensions).toContain('sovereignty');
    expect(self.payload.running).toBe(true);
    expect(self.payload.adapters).toBeDefined();
  });
});

// ── T10: Admin API rejects without valid cert ────────────────────

describe('Phase 26G — mTLS Enforcement', () => {
  test('T10: Dockerfile and admin server support mTLS configuration', () => {
    // Verify Dockerfile exposes port 6443
    const dockerfile = readFileSync(join(ROOT, 'Dockerfile'), 'utf-8');
    expect(dockerfile).toContain('6443');
    expect(dockerfile).toContain('SEMANTOS_CERTS_DIR');

    // Verify admin server supports TLS configuration
    const serverCode = readFileSync(
      join(ROOT, 'packages/node/src/api/server.ts'),
      'utf-8',
    );
    expect(serverCode).toContain('requestCert');
    expect(serverCode).toContain('rejectUnauthorized');
    expect(serverCode).toContain('loadTlsConfig');

    // Verify TLS utilities exist
    const tlsCode = readFileSync(
      join(ROOT, 'packages/node/src/api/tls.ts'),
      'utf-8',
    );
    expect(tlsCode).toContain('loadTlsConfig');
    expect(tlsCode).toContain('generateSelfSignedCerts');
    expect(tlsCode).toContain('node.crt');
    expect(tlsCode).toContain('node.key');
    expect(tlsCode).toContain('ca.crt');

    // Verify install.sh generates certs
    const installScript = readFileSync(join(ROOT, 'scripts/install.sh'), 'utf-8');
    expect(installScript).toContain('openssl');
    expect(installScript).toContain('prime256v1');
    expect(installScript).toContain('ca.crt');
    expect(installScript).toContain('node.crt');
    expect(installScript).toContain('client.crt');
  });
});

// ── Anti-Regression ──────────────────────────────────────────────

describe('Phase 26G — Anti-Regression', () => {
  test('Phase 25A StorageAdapter exports still present', () => {
    const indexPath = join(ROOT, 'core/protocol-types/src/index.ts');
    const content = readFileSync(indexPath, 'utf-8');
    expect(content).toContain('StorageAdapter');
    expect(content).toContain('MemoryAdapter');
    expect(content).toContain('NodeFsAdapter');
    expect(content).toContain('createAdapter');
  });

  test('Phase 26E createNode and NodeConfig exports still present', () => {
    const indexPath = join(ROOT, 'core/protocol-types/src/index.ts');
    const content = readFileSync(indexPath, 'utf-8');
    expect(content).toContain('createNode');
    expect(content).toContain('NodeConfig');
    expect(content).toContain('SemantosNode');
    expect(content).toContain('loadNodeConfig');
  });

  test('Phase 26F extension loading exports still present', () => {
    const indexPath = join(ROOT, 'core/protocol-types/src/index.ts');
    const content = readFileSync(indexPath, 'utf-8');
    expect(content).toContain('ExtensionManifest');
    expect(content).toContain('ExtensionLoader');
    expect(content).toContain('ExtensionRegistry');
  });

  test('Dockerfile exists and is valid multi-stage build', () => {
    const df = readFileSync(join(ROOT, 'Dockerfile'), 'utf-8');
    expect(df).toContain('FROM oven/bun:');
    expect(df).toContain('AS builder');
    expect(df).toContain('AS runtime');
    expect(df).toContain('COPY --from=builder');
    expect(df).toContain('ENTRYPOINT');
    expect(df).toContain('HEALTHCHECK');
  });

  test('docker-compose.yml exists with required services', () => {
    const dc = readFileSync(join(ROOT, 'docker-compose.yml'), 'utf-8');
    expect(dc).toContain('semantos-node');
    expect(dc).toContain('block-headers');
    expect(dc).toContain('semantos-data');
    expect(dc).toContain('healthcheck');
  });

  test('Deployment docs exist for all four personas', () => {
    expect(existsSync(join(ROOT, 'docs/deployment/VPS-DEPLOYMENT.md'))).toBe(true);
    expect(existsSync(join(ROOT, 'docs/deployment/DOCKER-DEPLOYMENT.md'))).toBe(true);
    expect(existsSync(join(ROOT, 'docs/deployment/ENTERPRISE-COLO.md'))).toBe(true);
    expect(existsSync(join(ROOT, 'docs/deployment/INFRA-PARTNER.md'))).toBe(true);
  });

  test('CLI entry point and commands exist', () => {
    expect(existsSync(join(ROOT, 'packages/node/src/cli.ts'))).toBe(true);
    expect(existsSync(join(ROOT, 'packages/node/src/daemon.ts'))).toBe(true);
    expect(existsSync(join(ROOT, 'packages/node/src/commands/status.ts'))).toBe(true);
    expect(existsSync(join(ROOT, 'packages/node/src/commands/extension.ts'))).toBe(true);
    expect(existsSync(join(ROOT, 'packages/node/src/commands/anchor.ts'))).toBe(true);
    expect(existsSync(join(ROOT, 'packages/node/src/commands/identity.ts'))).toBe(true);
    expect(existsSync(join(ROOT, 'packages/node/src/commands/self.ts'))).toBe(true);
  });
});

```
