---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/historian.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.469069+00:00
---

# packages/scada/scada/src/historian.ts

```ts
/**
 * Semantic Historian — Phase 29 (D29.4)
 *
 * Tamper-evident data historian built on per-sensor cell DAG chains.
 * Each telemetry reading is an AFFINE cell linked to its predecessor
 * via previousReadingCell. Integrity verification walks the chain
 * and re-computes SHA-256 hashes.
 *
 * Anomaly detection is a proof-of-concept using vector embeddings.
 */

import type {
  TelemetryCell,
  IntegrityReport,
  AnomalyReport,
  AlarmSeverity,
} from './types';

// ── Hash Utilities ─────────────────────────────────────────────

/** Compute SHA-256 hash of cell contents for chain integrity. */
async function computeCellHash(cell: TelemetryCell): Promise<string> {
  const content = JSON.stringify({
    sensorId: cell.sensorId,
    value: cell.value,
    unit: cell.unit,
    quality: cell.quality,
    timestamp: cell.timestamp,
    previousReadingCell: cell.previousReadingCell ?? null,
  });

  const encoder = new TextEncoder();
  const data = encoder.encode(content);

  // Use Web Crypto API (available in Node 18+ and browsers)
  if (typeof globalThis.crypto !== 'undefined' && globalThis.crypto.subtle) {
    const hashBuffer = await globalThis.crypto.subtle.digest('SHA-256', data);
    const hashArray = new Uint8Array(hashBuffer);
    return Array.from(hashArray).map(b => b.toString(16).padStart(2, '0')).join('');
  }

  // Fallback: simple hash for environments without Web Crypto
  let hash = 0;
  const str = content;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  return Math.abs(hash).toString(16).padStart(16, '0');
}

/** Synchronous hash computation for cell ID generation. */
function quickHash(input: string): string {
  let hash = 0;
  for (let i = 0; i < input.length; i++) {
    const char = input.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  return Math.abs(hash).toString(16).padStart(8, '0');
}

// ── ID Generation ──────────────────────────────────────────────

let cellCounter = 0;

function generateCellId(sensorId: string): string {
  cellCounter++;
  return `hist-${sensorId}-${cellCounter.toString(16).padStart(6, '0')}`;
}

// ── Timestamp ──────────────────────────────────────────────────

function microsecondTimestamp(): string {
  const now = new Date();
  return now.toISOString().replace('Z', '000Z');
}

// ── Semantic Historian ─────────────────────────────────────────

export class SemanticHistorian {
  /** Per-sensor cell chains. */
  private chains = new Map<string, TelemetryCell[]>();

  /** Cell lookup by ID. */
  private cellIndex = new Map<string, TelemetryCell>();

  /** Latest cell ID per sensor (head of DAG chain). */
  private latestCell = new Map<string, string>();

  /**
   * Record a telemetry reading — creates AFFINE cell linked to
   * previous reading via DAG.
   */
  async record(reading: Omit<TelemetryCell, 'cellId' | 'previousReadingCell' | 'linearity' | 'hash'>): Promise<string> {
    const sensorId = reading.sensorId;
    const previousReadingCell = this.latestCell.get(sensorId);

    const cell: TelemetryCell = {
      ...reading,
      cellId: generateCellId(sensorId),
      previousReadingCell,
      linearity: 'AFFINE',
    };

    // Compute and store hash for integrity verification
    cell.hash = await computeCellHash(cell);

    // Add to chain
    const chain = this.chains.get(sensorId) ?? [];
    chain.push(cell);
    this.chains.set(sensorId, chain);
    this.cellIndex.set(cell.cellId, cell);
    this.latestCell.set(sensorId, cell.cellId);

    return cell.cellId;
  }

  /**
   * Get a cell by its ID.
   */
  getCell(cellId: string): TelemetryCell | undefined {
    return this.cellIndex.get(cellId);
  }

  /**
   * Get the latest reading for a sensor.
   */
  getLatest(sensorId: string): TelemetryCell | undefined {
    const chain = this.chains.get(sensorId);
    if (!chain || chain.length === 0) return undefined;
    return chain[chain.length - 1];
  }

  /**
   * Query readings for a sensor within a time range.
   * Returns readings in chronological order.
   */
  query(
    sensorId: string,
    from: string,
    to: string,
    options?: { maxPoints?: number; aggregation?: 'none' | 'avg' | 'min' | 'max' },
  ): TelemetryCell[] {
    const chain = this.chains.get(sensorId) ?? [];
    const fromTime = new Date(from).getTime();
    const toTime = new Date(to).getTime();

    let filtered = chain.filter(cell => {
      const cellTime = new Date(cell.timestamp).getTime();
      return cellTime >= fromTime && cellTime <= toTime;
    });

    // Sort chronologically
    filtered.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());

    const maxPoints = options?.maxPoints;
    if (maxPoints && filtered.length > maxPoints) {
      // Downsample by taking evenly spaced points
      const step = Math.ceil(filtered.length / maxPoints);
      filtered = filtered.filter((_, i) => i % step === 0);
    }

    return filtered;
  }

  /**
   * Verify integrity of a reading chain — check DAG hash consistency.
   *
   * Walks the chain from latest to earliest, re-computing each hash.
   * Detects: modified values, inserted fakes, deleted readings, gaps.
   */
  async verifyIntegrity(
    sensorId: string,
    from: string,
    to: string,
  ): Promise<IntegrityReport> {
    const readings = this.query(sensorId, from, to);

    if (readings.length === 0) {
      return {
        sensorId,
        cellCount: 0,
        chainValid: true,
        hashesValid: true,
        gaps: [],
        tamperDetected: false,
      };
    }

    let chainValid = true;
    let hashesValid = true;
    const gaps: Array<{ from: string; to: string }> = [];

    for (let i = 0; i < readings.length; i++) {
      const cell = readings[i];

      // Verify hash
      const expectedHash = await computeCellHash(cell);
      if (cell.hash && cell.hash !== expectedHash) {
        hashesValid = false;
      }

      // Verify chain link (previousReadingCell should point to prior cell)
      if (i > 0) {
        const prevCell = readings[i - 1];
        if (cell.previousReadingCell && cell.previousReadingCell !== prevCell.cellId) {
          chainValid = false;
        }

        // Check for timestamp gaps (> 10x expected interval)
        const prevTime = new Date(prevCell.timestamp).getTime();
        const currTime = new Date(cell.timestamp).getTime();
        if (i >= 2) {
          const prevPrevTime = new Date(readings[i - 2].timestamp).getTime();
          const expectedInterval = currTime - prevTime;
          const prevInterval = prevTime - prevPrevTime;
          if (prevInterval > 0 && expectedInterval > prevInterval * 10) {
            gaps.push({ from: prevCell.timestamp, to: cell.timestamp });
          }
        }
      }
    }

    return {
      sensorId,
      cellCount: readings.length,
      chainValid,
      hashesValid,
      gaps,
      tamperDetected: !chainValid || !hashesValid,
    };
  }

  /**
   * Detect anomalies using embedding-based outlier detection.
   *
   * Embeds readings as 5D vectors:
   *   [normalized-value, rate-of-change, hour-of-day, day-of-week, quality-flag]
   *
   * Computes distance from "normal operating" centroid.
   * Readings beyond threshold are flagged.
   *
   * This is a proof-of-concept — not production ML.
   */
  detectAnomalies(
    sensorId: string,
    window: string,
    threshold: number,
  ): AnomalyReport {
    const chain = this.chains.get(sensorId) ?? [];
    if (chain.length === 0) {
      return { sensorId, window, anomalies: [] };
    }

    // Parse window duration
    const windowMs = parseWindow(window);
    const now = Date.now();
    const fromTime = now - windowMs;

    const readings = chain.filter(c => new Date(c.timestamp).getTime() >= fromTime);
    if (readings.length < 3) {
      return { sensorId, window, anomalies: [] };
    }

    // Compute statistics for the window
    const values = readings.map(r => r.value);
    const mean = values.reduce((a, b) => a + b, 0) / values.length;
    const variance = values.reduce((a, b) => a + (b - mean) ** 2, 0) / values.length;
    const stdDev = Math.sqrt(variance);

    // Compute "embedding" vectors and distances from centroid
    const anomalies: AnomalyReport['anomalies'] = [];

    for (let i = 1; i < readings.length; i++) {
      const curr = readings[i];
      const prev = readings[i - 1];

      // 5D "embedding" vector
      const normalizedValue = stdDev > 0 ? (curr.value - mean) / stdDev : 0;
      const rateOfChange = curr.value - prev.value;
      const date = new Date(curr.timestamp);
      const hourOfDay = date.getHours() / 24;
      const dayOfWeek = date.getDay() / 7;
      const qualityFlag = curr.quality === 'GOOD' ? 1 : curr.quality === 'UNCERTAIN' ? 0.5 : 0;

      // Euclidean distance from "normal" centroid (0, 0, ?, ?, 1)
      const distance = Math.sqrt(
        normalizedValue ** 2 +
        (rateOfChange / (stdDev || 1)) ** 2 +
        (1 - qualityFlag) ** 2,
      );

      if (distance > threshold) {
        const severity: AlarmSeverity =
          distance > threshold * 3 ? 'HIGH' :
          distance > threshold * 2 ? 'MEDIUM' : 'LOW';

        anomalies.push({
          cellId: curr.cellId,
          timestamp: curr.timestamp,
          value: curr.value,
          expectedRange: {
            min: mean - 2 * stdDev,
            max: mean + 2 * stdDev,
          },
          semanticDistance: distance,
          severity,
        });
      }
    }

    return { sensorId, window, anomalies };
  }

  /**
   * Export readings in standard formats.
   */
  export(
    sensorIds: string[],
    from: string,
    to: string,
    format: 'csv' | 'json' | 'opc-ua-json',
  ): string {
    const allReadings: TelemetryCell[] = [];
    for (const sensorId of sensorIds) {
      allReadings.push(...this.query(sensorId, from, to));
    }

    allReadings.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());

    switch (format) {
      case 'csv': {
        const header = 'cellId,sensorId,value,unit,quality,timestamp';
        const rows = allReadings.map(r =>
          `${r.cellId},${r.sensorId},${r.value},${r.unit},${r.quality},${r.timestamp}`,
        );
        return [header, ...rows].join('\n');
      }
      case 'json': {
        return JSON.stringify(allReadings, null, 2);
      }
      case 'opc-ua-json': {
        const opcUaReadings = allReadings.map(r => ({
          NodeId: r.sensorId,
          Value: { Value: r.value, StatusCode: qualityToStatusCode(r.quality) },
          SourceTimestamp: r.timestamp,
        }));
        return JSON.stringify(opcUaReadings, null, 2);
      }
    }
  }

  /**
   * Tamper with a cell (for testing only) — modifies value without updating hash.
   * @internal
   */
  _tamperCell(cellId: string, newValue: number): void {
    const cell = this.cellIndex.get(cellId);
    if (cell) {
      cell.value = newValue;
      // Hash NOT updated — this is the tampering
    }
  }

  /**
   * Delete a cell from the chain (for testing only) — creates a gap.
   * @internal
   */
  _deleteCell(cellId: string): void {
    const cell = this.cellIndex.get(cellId);
    if (!cell) return;

    const chain = this.chains.get(cell.sensorId);
    if (chain) {
      const idx = chain.findIndex(c => c.cellId === cellId);
      if (idx >= 0) {
        chain.splice(idx, 1);
      }
    }
    this.cellIndex.delete(cellId);
  }

  /**
   * Insert a fake cell into the chain (for testing only).
   * @internal
   */
  _insertFakeCell(sensorId: string, position: number, cell: TelemetryCell): void {
    const chain = this.chains.get(sensorId);
    if (chain && position >= 0 && position <= chain.length) {
      chain.splice(position, 0, cell);
      this.cellIndex.set(cell.cellId, cell);
    }
  }
}

// ── Helpers ────────────────────────────────────────────────────

function parseWindow(window: string): number {
  const match = window.match(/^(\d+)(s|m|h|d)$/);
  if (!match) return 24 * 60 * 60 * 1000; // default 24h

  const value = parseInt(match[1], 10);
  const unit = match[2];

  switch (unit) {
    case 's': return value * 1000;
    case 'm': return value * 60 * 1000;
    case 'h': return value * 60 * 60 * 1000;
    case 'd': return value * 24 * 60 * 60 * 1000;
    default: return 24 * 60 * 60 * 1000;
  }
}

function qualityToStatusCode(quality: string): number {
  switch (quality) {
    case 'GOOD': return 0;
    case 'UNCERTAIN': return 0x40000000;
    case 'BAD': return 0x80000000;
    default: return 0x80000000;
  }
}

```
