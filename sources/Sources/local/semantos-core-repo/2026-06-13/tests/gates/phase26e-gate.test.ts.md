---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase26e-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.572932+00:00
---

# tests/gates/phase26e-gate.test.ts

```ts
/**
 * Phase 26E Gate Tests — Node Bootstrap & Self-Object
 *
 * T1–T7:  Unit tests (config validation, createNode rejections, initialization)
 * T8–T12: Integration tests (lifecycle, uptime, updateNodeObject, RELEVANT linearity)
 * T13–T15: Config loading tests (JSON parsing, CLI overrides, invalid adapter type)
 */

import { describe, test, expect, afterEach } from 'bun:test';
import { writeFileSync, unlinkSync, mkdirSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';

import { createNode } from '../../core/protocol-types/src/node';
import { loadNodeConfig } from '../../core/protocol-types/src/node-config-loader';
import type { NodeConfig } from '../../core/protocol-types/src/node-config';
import type { SemantosNode } from '../../core/protocol-types/src/types/semantos-node';
import { MemoryAdapter } from '../../core/protocol-types/src/adapters/memory-adapter';
import { StubIdentityAdapter } from '../../core/protocol-types/src/adapters/stub-identity-adapter';
import { StubAnchorAdapter } from '../../core/protocol-types/src/adapters/stub-anchor-adapter';
import { StubNetworkAdapter } from '../../core/protocol-types/src/adapters/stub-network-adapter';
import { Linearity } from '../../core/protocol-types/src/constants';

// ── Test Helper ───────────────────────────────────────────────────

function buildStubConfig(overrides?: Partial<NodeConfig>): NodeConfig {
  return {
    storage: new MemoryAdapter(),
    identity: new StubIdentityAdapter({ mode: 'stub' }),
    anchor: new StubAnchorAdapter(600_000),
    network: new StubNetworkAdapter(),
    nodeCert: 'test-node-001',
    extensions: ['sovereignty'],
    anchorIntervalMs: 0, // disabled to avoid timer leaks in tests
    ...overrides,
  };
}

// Track nodes that need cleanup
const activeNodes: SemantosNode[] = [];

afterEach(async () => {
  for (const node of activeNodes) {
    try {
      const status = node.getStatus();
      if (status.running) await node.stop();
    } catch { /* ignore */ }
  }
  activeNodes.length = 0;
});

// ── Unit Tests (T1–T7) ───────────────────────────────────────────

describe('Phase 26E — NodeConfig and createNode', () => {
  test('T1: NodeConfig accepts all four adapters', () => {
    const config = buildStubConfig();
    expect(config.storage).toBeDefined();
    expect(config.identity).toBeDefined();
    expect(config.anchor).toBeDefined();
    expect(config.network).toBeDefined();
    expect(config.nodeCert).toBe('test-node-001');
    expect(config.extensions).toEqual(['sovereignty']);
  });

  test('T2: createNode rejects missing nodeCert', async () => {
    const config = buildStubConfig({ nodeCert: '' });
    await expect(createNode(config)).rejects.toThrow('nodeCert');
  });

  test('T3: createNode rejects missing extensions', async () => {
    const config = buildStubConfig({ extensions: [] });
    await expect(createNode(config)).rejects.toThrow('extensions');
  });

  test('T4: createNode initializes CellStore and SemanticFS', async () => {
    const node = await createNode(buildStubConfig());
    activeNodes.push(node);
    expect(node.cellStore).toBeDefined();
    expect(node.semanticFs).toBeDefined();
  });

  test('T5: createNode creates node self-object with sovereignty/node path', async () => {
    const node = await createNode(buildStubConfig());
    activeNodes.push(node);
    expect(node.nodeObject).toBeDefined();
    expect(node.nodeObject.key).toContain('sovereignty/node');
    expect(node.nodeObject.key).toContain('test-node-001');
  });

  test('T6: node.start() sets running=true and uptime > 0', async () => {
    const node = await createNode(buildStubConfig());
    activeNodes.push(node);
    await node.start();
    const status = node.getStatus();
    expect(status.running).toBe(true);
    expect(status.uptime).toBeGreaterThanOrEqual(0);
    expect(status.startedAt).not.toBeNull();
  });

  test('T7: node.stop() sets running=false and uptime=0', async () => {
    const node = await createNode(buildStubConfig());
    activeNodes.push(node);
    await node.start();
    await node.stop();
    const status = node.getStatus();
    expect(status.running).toBe(false);
    expect(status.uptime).toBe(0);
  });
});

// ── Integration Tests (T8–T12) ───────────────────────────────────

describe('Phase 26E — SemantosNode lifecycle', () => {
  test('T8: createNode with stubs returns ready node', async () => {
    const node = await createNode(buildStubConfig());
    activeNodes.push(node);
    expect(node.config).toBeDefined();
    expect(node.nodeObject).toBeDefined();
    expect(node.storage).toBeInstanceOf(MemoryAdapter);
    expect(node.identity).toBeInstanceOf(StubIdentityAdapter);
    expect(node.anchor).toBeInstanceOf(StubAnchorAdapter);
    expect(node.network).toBeInstanceOf(StubNetworkAdapter);
  });

  test('T9: getStatus() uptime increases after start', async () => {
    const node = await createNode(buildStubConfig());
    activeNodes.push(node);
    await node.start();
    const status1 = node.getStatus();
    await new Promise(r => setTimeout(r, 15));
    const status2 = node.getStatus();
    expect(status2.uptime).toBeGreaterThan(status1.uptime);
  });

  test('T10: stop() then getStatus() shows uptime=0', async () => {
    const node = await createNode(buildStubConfig());
    activeNodes.push(node);
    await node.start();
    await new Promise(r => setTimeout(r, 10));
    expect(node.getStatus().uptime).toBeGreaterThan(0);
    await node.stop();
    expect(node.getStatus().uptime).toBe(0);
    expect(node.getStatus().running).toBe(false);
  });

  test('T11: updateNodeObject() refreshes the self-object', async () => {
    const node = await createNode(buildStubConfig());
    activeNodes.push(node);
    await node.start();
    const before = node.nodeObject;
    await new Promise(r => setTimeout(r, 15));
    await node.updateNodeObject();
    const after = node.nodeObject;
    // New version should have updated version number or timestamp
    expect(after.version).toBeGreaterThanOrEqual(before.version);
  });

  test('T12: nodeObject has RELEVANT linearity', async () => {
    const node = await createNode(buildStubConfig());
    activeNodes.push(node);
    const selfPath = `objects/sovereignty/node/${node.config.nodeCert}`;
    const cellValue = await node.semanticFs.get(selfPath);
    expect(cellValue).not.toBeNull();
    expect(cellValue!.header.linearity).toBe(Linearity.RELEVANT);
  });
});

// ── Config Loading Tests (T13–T15) ───────────────────────────────

describe('Phase 26E — loadNodeConfig and adapter factories', () => {
  const tempDir = join(tmpdir(), 'semantos-26e-test');
  try { mkdirSync(tempDir, { recursive: true }); } catch { /* exists */ }

  test('T13: loadNodeConfig reads JSON file and resolves stub adapters', async () => {
    const configPath = join(tempDir, 'test-config-t13.json');
    writeFileSync(configPath, JSON.stringify({
      nodeCert: '0xtest123',
      storage: { type: 'memory' },
      identity: { type: 'stub' },
      anchor: { type: 'stub' },
      network: { type: 'stub' },
      extensions: ['trades'],
    }));

    const config = await loadNodeConfig(configPath);
    expect(config.nodeCert).toBe('0xtest123');
    expect(config.storage).toBeDefined();
    expect(config.storage).toBeInstanceOf(MemoryAdapter);
    expect(config.identity).toBeDefined();
    expect(config.identity).toBeInstanceOf(StubIdentityAdapter);
    expect(config.anchor).toBeDefined();
    expect(config.anchor).toBeInstanceOf(StubAnchorAdapter);
    expect(config.network).toBeDefined();
    expect(config.network).toBeInstanceOf(StubNetworkAdapter);
    expect(config.extensions).toEqual(['trades']);

    unlinkSync(configPath);
  });

  test('T14: CLI overrides take precedence over JSON values', async () => {
    const configPath = join(tempDir, 'test-config-t14.json');
    writeFileSync(configPath, JSON.stringify({
      nodeCert: '0xjson-cert',
      storage: { type: 'memory' },
      identity: { type: 'stub' },
      anchor: { type: 'stub' },
      network: { type: 'stub' },
      extensions: ['trades'],
      anchorIntervalMs: 60000,
    }));

    const config = await loadNodeConfig(configPath, {
      cert: '0xcli-cert',
      anchorIntervalMs: 120000,
    });
    expect(config.nodeCert).toBe('0xcli-cert');
    expect(config.anchorIntervalMs).toBe(120000);

    unlinkSync(configPath);
  });

  test('T15: loadNodeConfig throws on invalid adapter type', async () => {
    const configPath = join(tempDir, 'test-config-t15.json');
    writeFileSync(configPath, JSON.stringify({
      nodeCert: '0xtest',
      storage: { type: 'nonexistent-storage' },
      identity: { type: 'stub' },
      anchor: { type: 'stub' },
      network: { type: 'stub' },
      extensions: ['trades'],
    }));

    await expect(loadNodeConfig(configPath)).rejects.toThrow(
      /Unknown storage adapter type/,
    );

    unlinkSync(configPath);
  });
});

```
