---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/AttentionDelivery.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.097631+00:00
---

# runtime/services/src/services/AttentionDelivery.ts

```ts
/**
 * AttentionDelivery — AS5 of the AS workstream.
 *
 * Delivers high-urgency attention items across channels other than the
 * Helm right panel:
 *   - mobile push (web push / FCM / APNs via the operator's wallet origin)
 *   - SMS fallback when push channel is silent (operator-opt-in)
 *   - voice "what's next" surface: returns a top-N spoken summary
 *
 * Quiet hours suppress push + SMS in the configured window unless the
 * urgency is `immediate-critical` (capability revocation, wallet-security
 * event, explicit pinned-must-alert item).
 *
 * Per-channel telemetry feeds the same AS1 loop — push delivered /
 * opened / dismissed flow as additional `AttentionInteraction` variants.
 */
import { TypedEventEmitter } from './TypedEventEmitter';
import type { AttentionItem } from '../types/loom';
import type { AttentionTelemetry } from './AttentionTelemetry';

export type DeliveryChannel = 'push' | 'sms' | 'voice';

export interface PushTransport {
  send(payload: { title: string; body: string; deepLink: string; itemId: string }): Promise<{ delivered: boolean }>;
}

export interface SmsTransport {
  send(payload: { to: string; body: string; itemId: string }): Promise<{ delivered: boolean }>;
}

export interface VoiceTransport {
  /** Speak the summary aloud or return a serialised tts payload. */
  speak(summary: string): Promise<void>;
}

export interface QuietHours {
  /** "22:00" — local time of operator's profile. */
  start: string;
  end: string;
}

export interface AttentionDeliveryOptions {
  push?: PushTransport;
  sms?: SmsTransport;
  voice?: VoiceTransport;
  /** Operator's phone number for the SMS fallback. */
  smsTo?: string;
  /** Operator's quiet-hours window. */
  quietHours?: QuietHours;
  /** Helm-not-foreground threshold; only push if Helm idle for this long. Default 5 min. */
  idleThresholdMs?: number;
  /** Source of the operator's last Helm interaction time. */
  lastHelmInteractionAt?: () => number;
  /** Telemetry sink — receives push-* events. */
  telemetry?: AttentionTelemetry;
  /** Build the deep link for an item. */
  deepLinkFor?: (item: AttentionItem) => string;
  /** Decide whether an item is `immediate-critical` — bypasses quiet hours. */
  isCritical?: (item: AttentionItem) => boolean;
}

type DeliveryEvents = {
  delivered: [{ itemId: string; channel: DeliveryChannel }];
};

const PUSH_LATENCY_BUDGET_MS = 30_000;

export class AttentionDelivery extends TypedEventEmitter<DeliveryEvents> {
  private opts: AttentionDeliveryOptions;
  /** Items already delivered, keyed by id. Avoids re-firing on each recompute. */
  private delivered = new Set<string>();

  constructor(opts: AttentionDeliveryOptions) {
    super();
    this.opts = opts;
  }

  setOptions(patch: Partial<AttentionDeliveryOptions>): void {
    this.opts = { ...this.opts, ...patch };
  }

  /**
   * Process a fresh attention snapshot. For each item with
   * urgency = 'immediate' that hasn't been delivered yet, fan out to
   * push / SMS / voice per the configured transports.
   */
  async onSnapshot(items: AttentionItem[]): Promise<void> {
    for (const item of items) {
      if (item.urgency !== 'immediate') continue;
      if (this.delivered.has(item.object.id)) continue;
      await this.deliver(item);
      this.delivered.add(item.object.id);
    }
    // Drop ids that have rolled out of the surface.
    const present = new Set(items.map(i => i.object.id));
    for (const id of [...this.delivered]) {
      if (!present.has(id)) this.delivered.delete(id);
    }
  }

  /** Voice "what's next" — returns a coherent spoken summary of the top N. */
  async whatsNext(items: AttentionItem[], n: number = 3): Promise<string> {
    const top = items.slice(0, n);
    if (top.length === 0) return 'You have no immediate attention items.';
    const fragments = top.map((it) => itemSummary(it));
    const joined = fragments.length === 1
      ? fragments[0]
      : fragments.slice(0, -1).join(', ') + ', and ' + fragments[fragments.length - 1];
    const summary = `You've got ${joined}.`;
    if (this.opts.voice) await this.opts.voice.speak(summary);
    if (this.opts.telemetry) {
      for (const it of top) {
        await this.opts.telemetry.record({
          kind: 'push-delivered',
          itemId: it.object.id,
          channel: 'voice',
        });
      }
    }
    return summary;
  }

  private async deliver(item: AttentionItem): Promise<void> {
    const critical = this.opts.isCritical?.(item) ?? false;
    if (this.isQuietHours() && !critical) return;
    if (!this.helmIsIdle() && !critical) return;

    const deepLink = this.opts.deepLinkFor?.(item) ?? `helm:item/${item.object.id}`;
    const summary = itemSummary(item);

    let pushOk = false;
    if (this.opts.push) {
      try {
        const start = Date.now();
        const res = await this.opts.push.send({
          title: titleOf(item),
          body: summary,
          deepLink,
          itemId: item.object.id,
        });
        pushOk = res.delivered && (Date.now() - start) <= PUSH_LATENCY_BUDGET_MS;
        if (pushOk) {
          await this.opts.telemetry?.record({
            kind: 'push-delivered',
            itemId: item.object.id,
            channel: 'push',
          });
          this.emit('delivered', { itemId: item.object.id, channel: 'push' });
        }
      } catch {
        pushOk = false;
      }
    }

    if (!pushOk && this.opts.sms && this.opts.smsTo) {
      try {
        const res = await this.opts.sms.send({
          to: this.opts.smsTo,
          body: `${summary} ${deepLink}`,
          itemId: item.object.id,
        });
        if (res.delivered) {
          await this.opts.telemetry?.record({
            kind: 'push-delivered',
            itemId: item.object.id,
            channel: 'sms',
          });
          this.emit('delivered', { itemId: item.object.id, channel: 'sms' });
        }
      } catch {
        // SMS failures are non-fatal
      }
    }
  }

  private isQuietHours(): boolean {
    const q = this.opts.quietHours;
    if (!q) return false;
    const [sh, sm] = q.start.split(':').map(Number);
    const [eh, em] = q.end.split(':').map(Number);
    const now = new Date();
    const minutes = now.getHours() * 60 + now.getMinutes();
    const startM = sh * 60 + sm;
    const endM = eh * 60 + em;
    if (startM < endM) {
      return minutes >= startM && minutes < endM;
    }
    // Wraps over midnight.
    return minutes >= startM || minutes < endM;
  }

  private helmIsIdle(): boolean {
    if (!this.opts.lastHelmInteractionAt) return true;
    const last = this.opts.lastHelmInteractionAt();
    const idleMs = this.opts.idleThresholdMs ?? 5 * 60 * 1000;
    return Date.now() - last > idleMs;
  }
}

function titleOf(item: AttentionItem): string {
  const obj = item.object;
  return (obj.payload.name as string)
    ?? (obj.payload.title as string)
    ?? obj.typeDefinition?.name
    ?? obj.id;
}

function itemSummary(item: AttentionItem): string {
  const t = titleOf(item);
  const reason = item.reason;
  switch (reason.type) {
    case 'deadline_approaching':
      return `${t} \u2014 deadline ${reason.field} approaching`;
    case 'pending_action':
      return `${t} \u2014 ${reason.action}`;
    case 'extension_signal':
      return `${t} \u2014 ${reason.signal}`;
    case 'active_work':
      return `${t} \u2014 active work`;
    default:
      return t;
  }
}

```
