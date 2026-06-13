---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/__tests__/transfer-content.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.387535+00:00
---

# runtime/shell/src/router/__tests__/transfer-content.test.ts

```ts
/**
 * Metered Content Transfer as shell substrate — the verb surface any cartridge
 * or the PWA invokes via ctx.transfer. Proves a share on one shell context and a
 * fetch on another round-trip the bytes through the TransferService, and that
 * the verbs degrade gracefully when no transfer service is wired.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { SwarmBus, inMemorySwarmTransport, FakeBrainClient } from '@semantos/session-protocol';
import { TransferService } from '../../transfer-service';
import { transferContentHandlers } from '../verb-handlers/transfer-content';
import type { ShellContext } from '../../types';
import type { ShellCommand } from '../../parser';

const cmd = (flags: Record<string, unknown>): ShellCommand => ({ flags } as unknown as ShellCommand);
const cleanups: Array<() => Promise<void> | void> = [];
afterEach(async () => { for (const c of cleanups.splice(0)) await c(); });

describe('transfer.* shell verbs (substrate any cartridge invokes)', () => {
  test('share on one context, fetch on another, byte-exact through ctx.transfer', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'shell-transfer-'));
    cleanups.push(() => rmSync(dir, { recursive: true, force: true }));
    const bus = new SwarmBus();
    const discovery = new FakeBrainClient(); // shared manifest discovery

    const seederSvc = new TransferService({ makeTransport: () => inMemorySwarmTransport(bus, 'A'), brain: discovery });
    const leecherSvc = new TransferService({ makeTransport: () => inMemorySwarmTransport(bus, 'B'), brain: discovery });
    cleanups.push(() => seederSvc.stop(), () => leecherSvc.stop());
    const ctxA = { transfer: seederSvc } as unknown as ShellContext;
    const ctxB = { transfer: leecherSvc } as unknown as ShellContext;

    const src = join(dir, 'asset.bin');
    const data = Uint8Array.from({ length: 6 * 1016 + 9 }, (_, i) => (i * 5 + 3) & 0xff);
    writeFileSync(src, data);

    const shared = await transferContentHandlers['transfer.share'](cmd({ path: src, name: 'asset.bin' }), ctxA) as any;
    expect(shared.magnet).toMatch(/^[0-9a-f]{64}$/);
    expect(shared.bytes).toBe(data.length);

    const out = join(dir, 'asset.out');
    const fetched = await transferContentHandlers['transfer.fetch'](cmd({ magnet: shared.magnet, out, timeout: 8000 }), ctxB) as any;
    expect(fetched.bytes).toBe(data.length);
    expect(fetched.out).toBe(out);
    expect(new Uint8Array(readFileSync(out))).toEqual(data);

    // list reflects the seeder's active transfer.
    const listed = await transferContentHandlers['transfer.list'](cmd({}), ctxA) as any;
    expect(listed.transfers[0].magnet).toBe(shared.magnet);
  });

  test('verbs degrade gracefully when no transfer service is wired', async () => {
    const ctx = {} as unknown as ShellContext;
    const r = await transferContentHandlers['transfer.share'](cmd({ path: '/nope' }), ctx) as any;
    expect(r.code).toBe('TRANSFER_UNAVAILABLE');
  });

  test('share without a path is a clear error', async () => {
    const ctx = { transfer: new TransferService({ makeTransport: () => inMemorySwarmTransport(new SwarmBus(), 'X') }) } as unknown as ShellContext;
    cleanups.push(() => (ctx.transfer as TransferService).stop());
    const r = await transferContentHandlers['transfer.share'](cmd({}), ctx) as any;
    expect(r.code).toBe('MISSING_PATH');
  });
});

```
