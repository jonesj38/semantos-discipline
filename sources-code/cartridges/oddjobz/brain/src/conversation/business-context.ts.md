---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/business-context.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.522588+00:00
---

# cartridges/oddjobz/brain/src/conversation/business-context.ts

```ts
/**
 * WP-6 — operator business context for the intake conversation.
 *
 * The intake script reads the operator's profile.json + the active prompt version
 * (prompts.jsonl) from its data_dir (= the site's data dir, where the brain's
 * site_handler persists them). These drive a profile-built system prompt so ANY
 * in-person site-visit service business (plumber, electrician, cleaner, …) gets a
 * correctly-framed funnel from config alone — no handyman hardcoding.
 *
 * All reads degrade gracefully: a missing/!malformed profile yields an empty
 * context (the generic persona) rather than failing the turn.
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';

export interface BusinessContext {
  readonly businessName?: string;
  readonly tradeLabel?: string;
  readonly services?: ReadonlyArray<string>;
  readonly geography?: string;
  readonly tone?: string;
  readonly hourlyRate?: number;
  readonly currency?: string;
  readonly travelDistanceKm?: number;
  readonly quotePolicy?: string;
}

export interface OperatorContext {
  readonly context: BusinessContext;
  /** The active WP-5 prompt version's text, or null to use the generic persona. */
  readonly activePrompt: string | null;
}

function asString(v: unknown): string | undefined {
  return typeof v === 'string' && v.length > 0 ? v : undefined;
}

function asNumber(v: unknown): number | undefined {
  return typeof v === 'number' && Number.isFinite(v) ? v : undefined;
}

/** Read profile.json + the active prompts.jsonl version from `dataDir`. */
export function loadOperatorContext(dataDir: string): OperatorContext {
  let context: BusinessContext = {};
  let activeVersion = 0;

  try {
    const p = JSON.parse(readFileSync(join(dataDir, 'profile.json'), 'utf8')) as Record<string, unknown>;
    const pricing = (p.pricing ?? {}) as Record<string, unknown>;
    const hourly = (pricing.hourly_rate ?? {}) as Record<string, unknown>;
    const services = Array.isArray(p.services)
      ? (p.services as unknown[])
          .map((s) => (typeof s === 'string' ? s : asString((s as Record<string, unknown>)?.name) ?? asString((s as Record<string, unknown>)?.label)))
          .filter((s): s is string => typeof s === 'string')
      : undefined;
    context = {
      businessName: asString(p.business_name),
      tradeLabel: asString(p.trade_label),
      services: services && services.length > 0 ? services : undefined,
      geography: asString(p.geography),
      tone: asString(p.tone),
      hourlyRate: asNumber(hourly.amount),
      currency: asString(hourly.currency),
      travelDistanceKm: asNumber(pricing.travel_distance_km),
      quotePolicy: asString(pricing.quote_policy),
    };
    activeVersion = asNumber(p.widget_prompt_version) ?? 0;
  } catch {
    /* no/!malformed profile → generic persona */
  }

  let activePrompt: string | null = null;
  if (activeVersion > 0) {
    try {
      const raw = readFileSync(join(dataDir, 'prompts.jsonl'), 'utf8');
      for (const line of raw.split('\n')) {
        if (!line.trim()) continue;
        try {
          const rec = JSON.parse(line) as { id?: number; text?: string };
          if (rec.id === activeVersion && typeof rec.text === 'string') {
            activePrompt = rec.text;
            break;
          }
        } catch {
          /* skip malformed line */
        }
      }
    } catch {
      /* no prompts file */
    }
  }

  return { context, activePrompt };
}

```
