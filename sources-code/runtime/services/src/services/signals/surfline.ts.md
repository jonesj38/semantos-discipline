---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/signals/surfline.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.111501+00:00
---

# runtime/services/src/services/signals/surfline.ts

```ts
/**
 * Surfline signal source — AS4.
 *
 * Off by default. Opt-in via `attention enable surfline`. For the
 * tradie-on-the-Sunshine-Coast case: when the operator's calendar shows
 * a `flexible` or `personal` window and a configured spot is rated 4+
 * stars during that window, surface it.
 */
import type { AttentionSignalSource, AttentionSignal } from '../AttentionSignals';
import type { LoomObject } from '../../types/loom';

export interface SurfForecast {
  readonly spot: string;
  readonly at: number;
  /** Rating, 1..5. */
  readonly rating: number;
  readonly summary: string;
}

export interface SurflineProvider {
  forecast(opts: { spots: string[]; from: number; to: number }): Promise<SurfForecast[]>;
}

export interface SurflineSourceOptions {
  provider: SurflineProvider;
  spots: string[];
  /** Returns flexible / personal calendar windows. */
  flexibleWindowProvider: () => Array<{ object: LoomObject; from: number; to: number }>;
  minRating?: number;
}

export function createSurflineSource(opts: SurflineSourceOptions): AttentionSignalSource {
  const minRating = opts.minRating ?? 4;
  return {
    id: 'surfline',
    displayName: 'Surfline',
    async poll(now: number): Promise<AttentionSignal[]> {
      const windows = opts.flexibleWindowProvider();
      if (windows.length === 0) return [];
      const horizonStart = now;
      const horizonEnd = Math.max(...windows.map(w => w.to));
      const forecasts = await opts.provider.forecast({
        spots: opts.spots,
        from: horizonStart,
        to: horizonEnd,
      });
      const out: AttentionSignal[] = [];
      for (const w of windows) {
        for (const f of forecasts) {
          if (f.at < w.from || f.at > w.to) continue;
          if (f.rating < minRating) continue;
          out.push({
            sourceId: 'surfline',
            attachToObjectId: w.object.id,
            factor: {
              type: 'extension_signal',
              extensionId: 'surfline',
              signal: `${f.spot} ${f.rating}\u2605 ${f.summary} during your free window`,
            },
            score: Math.min(1.0, (f.rating - minRating + 1) / 2),
            expiresAt: w.to,
          });
        }
      }
      return out;
    },
  };
}

```
