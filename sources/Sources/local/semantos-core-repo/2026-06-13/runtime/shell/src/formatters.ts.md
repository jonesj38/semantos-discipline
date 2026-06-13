---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/formatters.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.366523+00:00
---

# runtime/shell/src/formatters.ts

```ts
/**
 * Output formatters — JSON, table, cell hex, CSV for Unix pipe composability.
 *
 * All output goes to stdout via returned strings. Errors go to stderr via
 * the caller (shell.ts / index.ts). Never import React.
 */

export type OutputFormat = 'json' | 'table' | 'cell' | 'csv';

/** Validate and coerce a string to an OutputFormat, defaulting to 'json'. */
export function parseOutputFormat(input: string | boolean | undefined): OutputFormat {
  if (typeof input !== 'string') return 'json';
  const lower = input.toLowerCase();
  if (lower === 'json' || lower === 'table' || lower === 'cell' || lower === 'csv') {
    return lower;
  }
  return 'json';
}

export class OutputFormatter {
  format(data: unknown, format: OutputFormat = 'json'): string {
    switch (format) {
      case 'json':
        return this.formatJSON(data);
      case 'table':
        return this.formatTable(data);
      case 'cell':
        return this.formatHexDump(data);
      case 'csv':
        return this.formatCSV(data);
    }
  }

  private formatJSON(data: unknown): string {
    return JSON.stringify(data, replacer, 2);
  }

  private formatTable(data: unknown): string {
    if (!Array.isArray(data)) {
      // Single object — render as key-value pairs
      if (data && typeof data === 'object') {
        const entries = Object.entries(data as Record<string, unknown>);
        const maxKeyLen = Math.max(...entries.map(([k]) => k.length), 0);
        return entries
          .map(([k, v]) => `${k.padEnd(maxKeyLen)}  ${formatValue(v)}`)
          .join('\n');
      }
      return String(data);
    }

    if (data.length === 0) return '(no results)';

    // Collect all keys from all objects
    const allKeys = new Set<string>();
    for (const row of data) {
      if (row && typeof row === 'object') {
        for (const key of Object.keys(row as Record<string, unknown>)) {
          allKeys.add(key);
        }
      }
    }

    const columns = [...allKeys];
    if (columns.length === 0) return '(no columns)';

    // Compute column widths
    const termWidth = typeof process !== 'undefined' && process.stdout?.columns
      ? process.stdout.columns
      : 120;
    const colWidths: number[] = columns.map(col => col.length);
    for (const row of data) {
      if (!row || typeof row !== 'object') continue;
      const obj = row as Record<string, unknown>;
      for (let i = 0; i < columns.length; i++) {
        const val = formatValue(obj[columns[i]]);
        colWidths[i] = Math.max(colWidths[i], val.length);
      }
    }

    // Cap column widths to fit terminal
    const totalPadding = (columns.length - 1) * 2;
    const totalWidth = colWidths.reduce((a, b) => a + b, 0) + totalPadding;
    if (totalWidth > termWidth) {
      const scale = (termWidth - totalPadding) / (totalWidth - totalPadding);
      for (let i = 0; i < colWidths.length; i++) {
        colWidths[i] = Math.max(4, Math.floor(colWidths[i] * scale));
      }
    }

    // Header
    const header = columns
      .map((col, i) => col.toUpperCase().padEnd(colWidths[i]))
      .join('  ');

    // Rows
    const rows = data.map(row => {
      if (!row || typeof row !== 'object') return String(row);
      const obj = row as Record<string, unknown>;
      return columns
        .map((col, i) => {
          const val = formatValue(obj[col]);
          const isNum = typeof obj[col] === 'number';
          return isNum ? val.padStart(colWidths[i]) : val.padEnd(colWidths[i]);
        })
        .join('  ');
    });

    return [header, ...rows].join('\n');
  }

  private formatHexDump(data: unknown): string {
    let bytes: Uint8Array;

    if (data instanceof Uint8Array) {
      bytes = data;
    } else if (Array.isArray(data)) {
      bytes = new Uint8Array(data);
    } else if (data && typeof data === 'object' && 'packedCell' in data) {
      const cell = (data as { packedCell?: Uint8Array }).packedCell;
      if (cell instanceof Uint8Array) {
        bytes = cell;
      } else {
        return this.formatJSON(data);
      }
    } else {
      // Encode as UTF-8
      const encoder = new TextEncoder();
      bytes = encoder.encode(JSON.stringify(data));
    }

    const lines: string[] = [];
    for (let offset = 0; offset < bytes.length; offset += 16) {
      const chunk = bytes.slice(offset, offset + 16);
      const addr = offset.toString(16).padStart(8, '0');
      const hex = Array.from(chunk)
        .map(b => b.toString(16).padStart(2, '0'))
        .join(' ')
        .padEnd(48);
      const ascii = Array.from(chunk)
        .map(b => (b >= 0x20 && b <= 0x7e) ? String.fromCharCode(b) : '.')
        .join('');
      lines.push(`${addr}  ${hex} ${ascii}`);
    }
    return lines.join('\n');
  }

  private formatCSV(data: unknown): string {
    if (!Array.isArray(data)) {
      if (data && typeof data === 'object') {
        data = [data];
      } else {
        return String(data);
      }
    }

    const arr = data as Record<string, unknown>[];
    if (arr.length === 0) return '';

    // Collect all keys from all rows
    const allKeys = new Set<string>();
    for (const row of arr) {
      if (row && typeof row === 'object') {
        for (const key of Object.keys(row)) {
          allKeys.add(key);
        }
      }
    }

    const columns = [...allKeys];
    const header = columns.map(csvEscape).join(',');
    const rows = arr.map(row => {
      if (!row || typeof row !== 'object') return csvEscape(String(row));
      return columns.map(col => csvEscape(formatValue(row[col]))).join(',');
    });

    return [header, ...rows].join('\n');
  }
}

/** Format a value for table display. */
function formatValue(v: unknown): string {
  if (v === undefined || v === null) return '';
  if (typeof v === 'string') return v;
  if (typeof v === 'number' || typeof v === 'boolean') return String(v);
  if (Array.isArray(v)) return v.map(formatValue).join(', ');
  if (v instanceof Uint8Array) return `<${v.length} bytes>`;
  return JSON.stringify(v);
}

/** Escape a value for CSV output. */
function csvEscape(value: string): string {
  if (value.includes(',') || value.includes('"') || value.includes('\n')) {
    return `"${value.replace(/"/g, '""')}"`;
  }
  return value;
}

/** JSON replacer that handles Map, Set, Uint8Array, BigInt. */
function replacer(_key: string, value: unknown): unknown {
  if (value instanceof Map) return Object.fromEntries(value);
  if (value instanceof Set) return [...value];
  if (value instanceof Uint8Array) return Array.from(value);
  if (typeof value === 'bigint') return value.toString();
  return value;
}

```
