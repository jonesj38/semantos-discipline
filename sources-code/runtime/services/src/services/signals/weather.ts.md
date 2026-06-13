---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/signals/weather.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.111220+00:00
---

# runtime/services/src/services/signals/weather.ts

```ts
/**
 * Weather signal source — AS4.
 *
 * For every calendar event in the next 7 days that is geo-tagged and
 * outdoor-flagged, computes a weather-risk score and emits an
 * extension_signal.
 *
 * The actual API call is delegated to a `WeatherProvider` so that BoM,
 * OpenWeatherMap, or a fixture provider can be plugged in. The adapter
 * itself is provider-agnostic.
 */
import type { AttentionSignalSource, AttentionSignal } from '../AttentionSignals';
import type { LoomObject } from '../../types/loom';

export interface WeatherForecast {
  /** Unix ms. */
  readonly at: number;
  readonly precipitationMm: number;
  readonly windKph: number;
  readonly tempC: number;
  readonly summary: string;
}

export interface WeatherProvider {
  /** Forecast for a given location and time window. */
  forecast(opts: { lat: number; lon: number; from: number; to: number }): Promise<WeatherForecast[]>;
}

export interface WeatherSourceOptions {
  provider: WeatherProvider;
  /** Returns the operator's outdoor-flagged calendar events with geo-tags. */
  outdoorEventProvider: () => Array<{ object: LoomObject; lat: number; lon: number; at: number }>;
  /** Risk threshold (mm of rain) that triggers a signal. Default 5mm. */
  riskMm?: number;
}

const FORECAST_HORIZON_MS = 7 * 24 * 60 * 60 * 1000;

export function createWeatherSource(opts: WeatherSourceOptions): AttentionSignalSource {
  const riskMm = opts.riskMm ?? 5;
  return {
    id: 'weather',
    displayName: 'Weather',
    async poll(now: number): Promise<AttentionSignal[]> {
      const events = opts.outdoorEventProvider();
      const out: AttentionSignal[] = [];
      for (const e of events) {
        if (e.at < now || e.at > now + FORECAST_HORIZON_MS) continue;
        try {
          const forecasts = await opts.provider.forecast({
            lat: e.lat,
            lon: e.lon,
            from: e.at - 60 * 60 * 1000,
            to: e.at + 60 * 60 * 1000,
          });
          const worst = forecasts.reduce<WeatherForecast | null>(
            (acc, f) => (!acc || f.precipitationMm > acc.precipitationMm ? f : acc),
            null,
          );
          if (worst && worst.precipitationMm >= riskMm) {
            const score = Math.min(1.0, worst.precipitationMm / 30);
            out.push({
              sourceId: 'weather',
              attachToObjectId: e.object.id,
              factor: {
                type: 'extension_signal',
                extensionId: 'weather',
                signal: `${worst.summary} (${worst.precipitationMm.toFixed(0)}mm) during scheduled visit`,
              },
              score,
              expiresAt: e.at + 60 * 60 * 1000,
            });
          }
        } catch {
          // skip failed forecast
        }
      }
      return out;
    },
  };
}

```
