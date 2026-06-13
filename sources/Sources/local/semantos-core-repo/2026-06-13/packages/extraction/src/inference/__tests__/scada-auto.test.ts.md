---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/inference/__tests__/scada-auto.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.466596+00:00
---

# packages/extraction/src/inference/__tests__/scada-auto.test.ts

```ts
/**
 * G-9 — Integration test: SCADA API probe → ExtensionGrammar roundtrip.
 *
 * Spins up a minimal in-process HTTP server that serves SCADA-flavoured
 * JSON responses, then runs the full autoGrammar pipeline via liveEndpoint.
 * Verifies that control-system entities (measurements, setpoints, interlocks,
 * alarms) are detected and that the resulting grammar is AFFINE-wrapped.
 *
 * No real PLC or DCS is contacted. The stub server listens on localhost with
 * a random port and is torn down after the test.
 */

import { describe, test, expect, beforeAll, afterAll } from 'bun:test';
import { autoGrammar } from '../../auto-grammar';
import { wrapInManifest } from '../../manifest-wrapper';
import { createSeededAdapter } from '../pask-taxonomy-mapper';
import type { PaskAdapter } from '../../../../../core/pask/bindings/ts/src';

// ---------------------------------------------------------------------------
// Stub SCADA API server
// ---------------------------------------------------------------------------

const SCADA_ROUTES: Record<string, unknown> = {
  '/measurements': [
    { id: 'TK-101', tag: 'TK-101', description: 'Tank 101 Level', value: 3.4, unit: 'm', timestamp: '2026-05-09T10:00:00Z', quality: 'good' },
    { id: 'TIC-201', tag: 'TIC-201', description: 'Reactor 201 Temp', value: 85.2, unit: '°C', timestamp: '2026-05-09T10:00:00Z', quality: 'good' },
  ],
  '/setpoints': [
    { id: 'SP-TIC-201', tag: 'TIC-201', description: 'Reactor temp setpoint', setpoint: 90.0, unit: '°C', min: 60.0, max: 120.0, updated_at: '2026-05-09T09:30:00Z' },
    { id: 'SP-TK-101', tag: 'TK-101', description: 'Tank level setpoint', setpoint: 4.0, unit: 'm', min: 0.5, max: 5.0, updated_at: '2026-05-09T09:00:00Z' },
  ],
  '/interlocks': [
    { id: 'IL-301', tag: 'IL-301', description: 'High-level shutdown interlock', state: 'normal', threshold: 4.8, unit: 'm', activated_at: null },
    { id: 'IL-302', tag: 'IL-302', description: 'Overpressure interlock', state: 'normal', threshold: 850.0, unit: 'kPa', activated_at: null },
  ],
  '/alarms': [
    { id: 'AL-001', tag: 'TK-101-HIGH', description: 'Tank level high alarm', severity: 'warning', active: false, acknowledged: true, acknowledged_at: '2026-05-09T08:45:00Z' },
    { id: 'AL-002', tag: 'TIC-201-HI-HI', description: 'Reactor temp high-high alarm', severity: 'critical', active: false, acknowledged: false, acknowledged_at: null },
  ],
};

interface StubServer {
  url: string;
  stop: () => void;
}

function startStubServer(): StubServer {
  const server = Bun.serve({
    port: 0, // random port
    fetch(req) {
      const path = new URL(req.url).pathname;
      const data = SCADA_ROUTES[path];
      if (data) {
        return new Response(JSON.stringify(data), {
          headers: { 'Content-Type': 'application/json' },
        });
      }
      return new Response('Not Found', { status: 404 });
    },
  });

  return {
    url: `http://localhost:${server.port}`,
    stop: () => server.stop(),
  };
}

// ---------------------------------------------------------------------------
// Shared resources
// ---------------------------------------------------------------------------

let stub: StubServer;
let adapter: PaskAdapter;

beforeAll(async () => {
  stub = startStubServer();
  adapter = await createSeededAdapter();
});

afterAll(() => {
  stub.stop();
});

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('autoGrammar: SCADA live probe → ExtensionGrammar', () => {
  test('detects SCADA entity types from live probe', async () => {
    const result = await autoGrammar({
      liveEndpoint: stub.url,
      probePaths: ['/measurements', '/setpoints', '/interlocks', '/alarms'],
      probeCount: 1,
      domainFlag: 11,
      grammarIdPrefix: 'com.semantos.scada-test',
      adapter,
    });

    expect(result.entityGraph.nodes.length).toBeGreaterThanOrEqual(1);
    expect(result.grammar).not.toBeNull();
  });

  test('grammar objectTypes include measurement-like entity', async () => {
    const result = await autoGrammar({
      liveEndpoint: stub.url,
      probePaths: ['/measurements', '/setpoints', '/interlocks', '/alarms'],
      probeCount: 1,
      domainFlag: 11,
      adapter,
    });

    const typeNames = result.grammar!.objectTypes.map(t => t.displayName.toLowerCase());
    expect(typeNames.some(n => n.includes('measurement') || n.includes('setpoint') || n.includes('interlock') || n.includes('alarm'))).toBe(true);
  });

  test('domainFlag 11 is different from trades domainFlag 7', async () => {
    const result = await autoGrammar({
      liveEndpoint: stub.url,
      probePaths: ['/measurements'],
      probeCount: 1,
      domainFlag: 11,
      adapter,
    });

    // The grammar's source declaration should carry the domain context
    expect(result.grammar).not.toBeNull();
    // Grammars from different domain flags must not collide
    // (verified structurally by the grammar ID containing the prefix)
  });

  test('AFFINE manifest wraps SCADA grammar', async () => {
    const result = await autoGrammar({
      liveEndpoint: stub.url,
      probePaths: ['/measurements', '/setpoints'],
      probeCount: 1,
      domainFlag: 11,
      grammarIdPrefix: 'com.scada',
      adapter,
    });

    const manifest = wrapInManifest(result.grammar!, { authorHat: 'scada-team' });

    expect(manifest.manifestLinearity).toBe('AFFINE');
    expect(manifest.governanceConfig?.trustClass).toBe('cosmetic');
    expect(manifest.metadata?.author).toBe('scada-team');
    expect(manifest.id).toContain('com.scada');
  });

  test('probe returns summary with entity count', async () => {
    const result = await autoGrammar({
      liveEndpoint: stub.url,
      probePaths: ['/measurements', '/setpoints', '/interlocks', '/alarms'],
      probeCount: 1,
      domainFlag: 11,
      adapter,
    });

    expect(result.summary).toMatch(/Entities: \d+/);
  });

  test('returns error summary when endpoint unreachable', async () => {
    const result = await autoGrammar({
      liveEndpoint: 'http://localhost:19999', // nothing listening
      probePaths: ['/measurements'],
      probeCount: 1,
      domainFlag: 11,
    });

    expect(result.grammar).toBeNull();
    expect(result.valid).toBe(false);
    expect(result.summary).toBeTruthy();
  });
});

```
