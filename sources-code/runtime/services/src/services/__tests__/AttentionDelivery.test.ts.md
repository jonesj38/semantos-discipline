---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/__tests__/AttentionDelivery.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.109750+00:00
---

# runtime/services/src/services/__tests__/AttentionDelivery.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { AttentionDelivery } from '../AttentionDelivery';
import { AttentionTelemetry } from '../AttentionTelemetry';
import type { AttentionItem } from '../../types/loom';

function item(over: Partial<AttentionItem> = {}): AttentionItem {
  return {
    object: {
      id: over.object?.id ?? 'i1',
      typeDefinition: { name: 'Test', fields: [] } as any,
      header: { version: 1, linearity: 3, fieldHeader: 0, sigSet: 0 } as any,
      payload: { name: 'hello' },
      patches: [],
      visibility: 'draft',
      createdAt: 0,
      updatedAt: 0,
    } as any,
    relevance: 0.9,
    reason: { type: 'pending_action', action: 'reply', awaitingSince: Date.now() - 86400000 } as any,
    primaryMode: 'do',
    context: 'manage',
    urgency: over.urgency ?? 'immediate',
    scoredAt: Date.now(),
  };
}

describe('AttentionDelivery', () => {
  test('immediate items fire push exactly once', async () => {
    const sent: any[] = [];
    const d = new AttentionDelivery({
      push: { send: async (p) => { sent.push(p); return { delivered: true }; } },
      lastHelmInteractionAt: () => Date.now() - 10 * 60 * 1000,
    });
    const it = item();
    await d.onSnapshot([it]);
    await d.onSnapshot([it]);
    expect(sent.length).toBe(1);
  });

  test('quiet hours suppress non-critical pushes', async () => {
    const sent: any[] = [];
    // Construct a window that always covers "now".
    const now = new Date();
    const start = `${(now.getHours()).toString().padStart(2, '0')}:00`;
    const endHour = (now.getHours() + 1) % 24;
    const end = `${endHour.toString().padStart(2, '0')}:00`;
    const d = new AttentionDelivery({
      push: { send: async (p) => { sent.push(p); return { delivered: true }; } },
      quietHours: { start, end },
      lastHelmInteractionAt: () => Date.now() - 10 * 60 * 1000,
    });
    await d.onSnapshot([item()]);
    expect(sent.length).toBe(0);
  });

  test('critical pushes bypass quiet hours', async () => {
    const sent: any[] = [];
    const now = new Date();
    const start = `${(now.getHours()).toString().padStart(2, '0')}:00`;
    const endHour = (now.getHours() + 1) % 24;
    const end = `${endHour.toString().padStart(2, '0')}:00`;
    const d = new AttentionDelivery({
      push: { send: async (p) => { sent.push(p); return { delivered: true }; } },
      quietHours: { start, end },
      lastHelmInteractionAt: () => Date.now() - 10 * 60 * 1000,
      isCritical: () => true,
    });
    await d.onSnapshot([item()]);
    expect(sent.length).toBe(1);
  });

  test('SMS fallback fires when push fails', async () => {
    const smsSent: any[] = [];
    const d = new AttentionDelivery({
      push: { send: async () => ({ delivered: false }) },
      sms: { send: async (p) => { smsSent.push(p); return { delivered: true }; } },
      smsTo: '+15551234',
      lastHelmInteractionAt: () => Date.now() - 10 * 60 * 1000,
    });
    await d.onSnapshot([item()]);
    expect(smsSent.length).toBe(1);
  });

  test('whatsNext returns coherent summary', async () => {
    const d = new AttentionDelivery({});
    const summary = await d.whatsNext([item(), item({ object: { id: 'i2' } as any })], 2);
    expect(summary).toContain('hello');
  });

  test('telemetry receives push-delivered events', async () => {
    const tel = new AttentionTelemetry();
    const d = new AttentionDelivery({
      push: { send: async () => ({ delivered: true }) },
      telemetry: tel,
      lastHelmInteractionAt: () => Date.now() - 10 * 60 * 1000,
    });
    await d.onSnapshot([item()]);
    expect(tel.query({ kinds: ['push-delivered'] }).length).toBe(1);
  });
});

```
