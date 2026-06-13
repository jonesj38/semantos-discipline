---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/__tests__/router-core.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.388415+00:00
---

# runtime/shell/src/router/__tests__/router-core.test.ts

```ts
/**
 * router-core dispatch tests — pin the pre-handler pipeline:
 * mutation gate, dry-run envelope, and unknown-verb fallback.
 */

import { describe, expect, test } from 'bun:test';
import { route } from '../router-core';
import { makeVerbRegistry } from '../verb-registry';
import type { VerbHandler } from '../types';
import type { ShellCommand } from '../../parser';
import type { ShellContext } from '../../types';

function makeCtx(overrides: Partial<ShellContext> = {}): ShellContext {
  return {
    activeHatId: null,
    activeHatCertId: null,
    identity: { getActiveHat: () => null } as unknown as ShellContext['identity'],
    plexus: {
      presentCapability: async () => ({ valid: true }),
    } as unknown as ShellContext['plexus'],
    ...overrides,
  } as ShellContext;
}

function makeCmd(verb: string, flags: Record<string, unknown> = {}): ShellCommand {
  return { verb, flags } as unknown as ShellCommand;
}

describe('router-core route()', () => {
  test('1. dispatches a non-mutation verb directly', async () => {
    const reg = makeVerbRegistry();
    const handler: VerbHandler = async () => ({ ok: true });
    reg.register('whoami', handler);
    const out = await route(makeCmd('whoami'), makeCtx(), reg);
    expect(out).toEqual({ ok: true });
  });

  test('2. unknown verb returns a structured UNKNOWN_VERB error', async () => {
    const reg = makeVerbRegistry();
    const out = (await route(makeCmd('mystery'), makeCtx(), reg)) as Record<string, unknown>;
    expect(out.code).toBe('UNKNOWN_VERB');
  });

  test('3. mutation verb without a hat returns CAPABILITY_CHECK_FAILED', async () => {
    const reg = makeVerbRegistry();
    reg.register('new', async () => ({ ok: true }));
    const out = (await route(makeCmd('new'), makeCtx(), reg)) as Record<string, unknown>;
    expect(out.code).toBe('CAPABILITY_CHECK_FAILED');
  });

  test('4. mutation verb with --dry-run returns a dryRun envelope without invoking the handler', async () => {
    const reg = makeVerbRegistry();
    let called = false;
    reg.register('new', async () => {
      called = true;
      return {};
    });
    const out = (await route(
      makeCmd('new', { 'dry-run': true }),
      makeCtx(),
      reg,
    )) as Record<string, unknown>;
    expect(out.dryRun).toBe(true);
    expect(out.verb).toBe('new');
    expect(called).toBe(false);
  });

  test('5. host.exec dry-run runs the handler (handler owns its dry-run semantics)', async () => {
    const reg = makeVerbRegistry();
    let called = false;
    reg.register('host.exec', async () => {
      called = true;
      return { ok: true };
    });
    const ctx = makeCtx({
      identity: {
        getActiveHat: () => ({
          id: 'hat-1',
          certId: 'cert-1',
          capabilities: [0x0001000b], // host.exec requires HOST_EXEC
        }),
      } as unknown as ShellContext['identity'],
      activeHatCertId: 'cert-1',
    });
    await route(makeCmd('host.exec', { 'dry-run': true }), ctx, reg);
    expect(called).toBe(true);
  });

  test('6. handlers added at runtime via register() are immediately routable', async () => {
    const reg = makeVerbRegistry();
    const out1 = (await route(makeCmd('plugin'), makeCtx(), reg)) as { code?: string };
    expect(out1.code).toBe('UNKNOWN_VERB');
    reg.register('plugin', async () => ({ ok: 'live' }));
    const out2 = await route(makeCmd('plugin'), makeCtx(), reg);
    expect(out2).toEqual({ ok: 'live' });
  });
});

```
