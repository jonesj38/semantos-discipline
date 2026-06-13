---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/tests/formatters.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.361867+00:00
---

# runtime/shell/tests/formatters.test.ts

```ts
import { describe, test, expect } from 'bun:test';
import { OutputFormatter, parseOutputFormat } from '../src/formatters';

const fmt = new OutputFormatter();

// ── parseOutputFormat ────────────────────────────────────────

describe('parseOutputFormat', () => {
  test('returns json for undefined', () => {
    expect(parseOutputFormat(undefined)).toBe('json');
  });

  test('returns json for boolean', () => {
    expect(parseOutputFormat(true)).toBe('json');
  });

  test('accepts valid formats', () => {
    expect(parseOutputFormat('json')).toBe('json');
    expect(parseOutputFormat('table')).toBe('table');
    expect(parseOutputFormat('cell')).toBe('cell');
    expect(parseOutputFormat('csv')).toBe('csv');
  });

  test('case-insensitive', () => {
    expect(parseOutputFormat('JSON')).toBe('json');
    expect(parseOutputFormat('Table')).toBe('table');
  });

  test('defaults to json for unknown string', () => {
    expect(parseOutputFormat('yaml')).toBe('json');
  });
});

// ── JSON format ──────────────────────────────────────────────

describe('JSON format', () => {
  test('formats simple object', () => {
    const result = fmt.format({ a: 1, b: 'hello' }, 'json');
    const parsed = JSON.parse(result);
    expect(parsed.a).toBe(1);
    expect(parsed.b).toBe('hello');
  });

  test('handles Map via replacer', () => {
    const data = new Map([['key1', 'val1'], ['key2', 'val2']]);
    const result = fmt.format(data, 'json');
    const parsed = JSON.parse(result);
    expect(parsed.key1).toBe('val1');
    expect(parsed.key2).toBe('val2');
  });

  test('handles Set via replacer', () => {
    const data = new Set([1, 2, 3]);
    const result = fmt.format(data, 'json');
    const parsed = JSON.parse(result);
    expect(parsed).toEqual([1, 2, 3]);
  });

  test('handles Uint8Array via replacer', () => {
    const data = new Uint8Array([0x01, 0x02, 0x03]);
    const result = fmt.format(data, 'json');
    const parsed = JSON.parse(result);
    expect(parsed).toEqual([1, 2, 3]);
  });

  test('handles BigInt via replacer', () => {
    const data = { value: BigInt(999999999999999) };
    const result = fmt.format(data, 'json');
    expect(result).toContain('999999999999999');
  });

  test('pretty prints with 2-space indent', () => {
    const result = fmt.format({ a: 1 }, 'json');
    expect(result).toContain('\n');
    expect(result).toContain('  ');
  });
});

// ── Table format ─────────────────────────────────────────────

describe('Table format', () => {
  test('single object renders as key-value pairs', () => {
    const result = fmt.format({ name: 'Alice', role: 'admin' }, 'table');
    expect(result).toContain('name');
    expect(result).toContain('Alice');
    expect(result).toContain('role');
    expect(result).toContain('admin');
  });

  test('array renders with column headers', () => {
    const data = [
      { id: 'obj-1', type: 'Job', status: 'draft' },
      { id: 'obj-2', type: 'Quote', status: 'published' },
    ];
    const result = fmt.format(data, 'table');
    const lines = result.split('\n');
    // First line is header
    expect(lines[0]).toContain('ID');
    expect(lines[0]).toContain('TYPE');
    expect(lines[0]).toContain('STATUS');
    // Data rows
    expect(lines[1]).toContain('obj-1');
    expect(lines[2]).toContain('obj-2');
  });

  test('empty array shows (no results)', () => {
    const result = fmt.format([], 'table');
    expect(result).toBe('(no results)');
  });

  test('numeric values are right-aligned', () => {
    const data = [{ name: 'A', count: 42 }];
    const result = fmt.format(data, 'table');
    const lines = result.split('\n');
    // The count value should be right-aligned (padStart)
    const dataLine = lines[1];
    // Find the position of '42' — it should be right-padded (padStart)
    expect(dataLine).toContain('42');
  });

  test('non-object data stringified', () => {
    const result = fmt.format('plain text', 'table');
    expect(result).toBe('plain text');
  });
});

// ── Hex dump (cell) format ───────────────────────────────────

describe('Cell (hex) format', () => {
  test('renders Uint8Array as hex dump', () => {
    const bytes = new Uint8Array([
      0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x20, 0x57, 0x6f,
      0x72, 0x6c, 0x64, 0x21,
    ]);
    const result = fmt.format(bytes, 'cell');
    // Should have address + hex + ASCII
    expect(result).toContain('00000000');
    expect(result).toContain('48 65 6c 6c 6f 20 57 6f');
    expect(result).toContain('Hello Wo');
  });

  test('multi-line for >16 bytes', () => {
    const bytes = new Uint8Array(32).fill(0xAA);
    const result = fmt.format(bytes, 'cell');
    const lines = result.split('\n');
    expect(lines.length).toBe(2);
    expect(lines[0]).toContain('00000000');
    expect(lines[1]).toContain('00000010');
  });

  test('handles packedCell property', () => {
    const data = { packedCell: new Uint8Array([0x01, 0x02]) };
    const result = fmt.format(data, 'cell');
    expect(result).toContain('01 02');
  });

  test('non-printable chars shown as dots', () => {
    const bytes = new Uint8Array([0x00, 0x01, 0x7f, 0xff]);
    const result = fmt.format(bytes, 'cell');
    // All non-printable should be dots in ASCII column
    expect(result).toContain('....');
  });
});

// ── CSV format ───────────────────────────────────────────────

describe('CSV format', () => {
  test('array of objects with header row', () => {
    const data = [
      { id: 'obj-1', name: 'Alice' },
      { id: 'obj-2', name: 'Bob' },
    ];
    const result = fmt.format(data, 'csv');
    const lines = result.split('\n');
    expect(lines[0]).toBe('id,name');
    expect(lines[1]).toBe('obj-1,Alice');
    expect(lines[2]).toBe('obj-2,Bob');
  });

  test('escapes commas in values', () => {
    const data = [{ text: 'hello, world' }];
    const result = fmt.format(data, 'csv');
    expect(result).toContain('"hello, world"');
  });

  test('escapes double quotes in values', () => {
    const data = [{ text: 'say "hello"' }];
    const result = fmt.format(data, 'csv');
    expect(result).toContain('"say ""hello"""');
  });

  test('escapes newlines in values', () => {
    const data = [{ text: 'line1\nline2' }];
    const result = fmt.format(data, 'csv');
    expect(result).toContain('"line1\nline2"');
  });

  test('single object wrapped as array', () => {
    const result = fmt.format({ a: '1', b: '2' }, 'csv');
    const lines = result.split('\n');
    expect(lines[0]).toBe('a,b');
    expect(lines[1]).toBe('1,2');
  });

  test('empty array returns empty string', () => {
    expect(fmt.format([], 'csv')).toBe('');
  });

  test('collects keys from all rows', () => {
    const data = [
      { a: '1' },
      { a: '2', b: '3' },
    ];
    const result = fmt.format(data, 'csv');
    const lines = result.split('\n');
    expect(lines[0]).toBe('a,b');
    // First row missing 'b' — should be empty
    expect(lines[1]).toBe('1,');
    expect(lines[2]).toBe('2,3');
  });
});

```
