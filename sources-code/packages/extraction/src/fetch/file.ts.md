---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/fetch/file.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.460160+00:00
---

# packages/extraction/src/fetch/file.ts

```ts
/**
 * File fetch adapter — reads JSON/CSV files and yields batched RawResponses.
 *
 * Optionally routes raw file bytes through an injected ContentStore so
 * the parse stage consumes content-addressed bytes (and so the same
 * raw documents are cacheable / verifiable across nodes). When no
 * ContentStore is supplied the adapter falls back to plain fs reads
 * for backward compatibility with existing callers.
 */

import type { SourceEntity, SourceDeclaration, ContentStore } from '@semantos/protocol-types';
import type { RawResponse, Credentials, ExtractionContext } from '../stages';
import type { FetchAdapter } from './adapter';
import { readFileSync } from 'node:fs';

export interface FileFetchAdapterConfig {
  /** Optional ContentStore. When set, raw file bytes are put + re-got before parsing. */
  contentStore?: ContentStore;
}

export class FileFetchAdapter implements FetchAdapter {
  private readonly contentStore?: ContentStore;

  constructor(config?: FileFetchAdapterConfig) {
    if (config?.contentStore) this.contentStore = config.contentStore;
  }

  async *fetch(
    entity: SourceEntity,
    source: SourceDeclaration,
    credentials: Credentials,
    _context: ExtractionContext,
  ): AsyncGenerator<RawResponse, void, void> {
    const filePath = credentials.filePath ?? entity.endpoint.list;
    const format = credentials.format ?? detectFormat(filePath);
    const pageSize = source.pagination?.pageSize ?? 100;

    const rawDisk = readFileSync(filePath);
    const rawBytes = new Uint8Array(rawDisk.buffer, rawDisk.byteOffset, rawDisk.byteLength);

    // Route through ContentStore when present: this gives every
    // downstream stage a content-addressed handle on the raw doc and
    // catches mid-extraction bit-rot via the store's hash check.
    let bytesForParse: Uint8Array;
    if (this.contentStore) {
      const ref = await this.contentStore.put(rawBytes, {
        mimeType: mimeForFormat(format),
      });
      bytesForParse = await this.contentStore.get(ref.hash);
    } else {
      bytesForParse = rawBytes;
    }

    const content = new TextDecoder('utf-8').decode(bytesForParse);
    const hash = await sha256hex(content);

    switch (format) {
      case 'json': {
        // Yield the entire JSON as a single response
        const body = JSON.parse(content);
        yield {
          endpoint: `file://${filePath}`,
          statusCode: 200,
          body,
          headers: { 'content-type': 'application/json' },
          timestamp: Date.now(),
          responseHash: hash,
        };
        break;
      }

      case 'csv': {
        const rows = parseCSV(content);
        // Batch rows into pages
        for (let i = 0; i < rows.length; i += pageSize) {
          const batch = rows.slice(i, i + pageSize);
          yield {
            endpoint: `file://${filePath}`,
            statusCode: 200,
            body: { data: batch },
            headers: { 'content-type': 'text/csv' },
            timestamp: Date.now(),
            responseHash: hash,
          };
        }
        break;
      }

      default:
        throw new Error(`Unsupported file format: ${format}. Supported: json, csv`);
    }
  }
}

// ── Helpers ─────────────────────────────────────────────────────

function detectFormat(filePath: string): string {
  if (filePath.endsWith('.json')) return 'json';
  if (filePath.endsWith('.csv')) return 'csv';
  if (filePath.endsWith('.xml')) return 'xml';
  return 'json'; // default
}

function mimeForFormat(format: string): string {
  switch (format) {
    case 'json': return 'application/json';
    case 'csv': return 'text/csv';
    case 'xml': return 'application/xml';
    default: return 'application/octet-stream';
  }
}

/** Simple CSV parser — handles quoted fields with commas. */
function parseCSV(content: string): Record<string, string>[] {
  const lines = content.split('\n').filter(l => l.trim().length > 0);
  if (lines.length < 2) return [];

  const headers = parseCsvLine(lines[0]);
  const rows: Record<string, string>[] = [];

  for (let i = 1; i < lines.length; i++) {
    const values = parseCsvLine(lines[i]);
    const row: Record<string, string> = {};
    for (let j = 0; j < headers.length; j++) {
      row[headers[j]] = values[j] ?? '';
    }
    rows.push(row);
  }

  return rows;
}

function parseCsvLine(line: string): string[] {
  const result: string[] = [];
  let current = '';
  let inQuotes = false;

  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      inQuotes = !inQuotes;
    } else if (ch === ',' && !inQuotes) {
      result.push(current.trim());
      current = '';
    } else {
      current += ch;
    }
  }
  result.push(current.trim());
  return result;
}

async function sha256hex(input: string): Promise<string> {
  const encoded = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest('SHA-256', encoded);
  return Array.from(new Uint8Array(hashBuffer))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

```
