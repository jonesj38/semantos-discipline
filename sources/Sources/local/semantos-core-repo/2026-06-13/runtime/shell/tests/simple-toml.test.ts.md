---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/tests/simple-toml.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.360764+00:00
---

# runtime/shell/tests/simple-toml.test.ts

```ts
import { describe, test, expect } from 'bun:test';
import { parseSections, parseStringArray, parseInteger, parseString } from '../src/util/simple-toml';

// ── parseSections ────────────────────────────────────────────

describe('parseSections', () => {
  test('parses flat sections', () => {
    const input = `
[shell]
adapter_mode = "stub"
active_hat = "alice"

[plexus]
mode = "real"
endpoint = "http://localhost:9000"
`;
    const result = parseSections(input);
    expect(result.shell.adapter_mode).toBe('stub');
    expect(result.shell.active_hat).toBe('alice');
    expect(result.plexus.mode).toBe('real');
    expect(result.plexus.endpoint).toBe('http://localhost:9000');
  });

  test('parses dotted section names', () => {
    const input = `
[layout]
width = 200
height = 50

[panes.objects]
width_percent = 20
columns = ["id", "linearity", "phase"]

[colors]
theme = "dark"
`;
    const result = parseSections(input);
    expect(result.layout.width).toBe('200');
    expect(result.layout.height).toBe('50');
    expect(result['panes.objects'].width_percent).toBe('20');
    expect(result['panes.objects'].columns).toBe('["id", "linearity", "phase"]');
    expect(result.colors.theme).toBe('dark');
  });

  test('strips quotes from values', () => {
    const input = `
[test]
single = 'hello'
double = "world"
bare = 42
`;
    const result = parseSections(input);
    expect(result.test.single).toBe('hello');
    expect(result.test.double).toBe('world');
    expect(result.test.bare).toBe('42');
  });

  test('ignores comments and blank lines', () => {
    const input = `
# This is a comment
[section]
# Another comment
key = "value"

`;
    const result = parseSections(input);
    expect(result.section.key).toBe('value');
  });

  test('ignores lines before any section', () => {
    const input = `
orphan = "ignored"
[section]
key = "value"
`;
    const result = parseSections(input);
    expect(result.section.key).toBe('value');
    expect(result['']?.orphan).toBeUndefined();
  });

  test('handles empty input', () => {
    const result = parseSections('');
    expect(Object.keys(result).length).toBe(0);
  });

  test('handles value with equals sign', () => {
    const input = `
[section]
url = "http://example.com?a=1&b=2"
`;
    const result = parseSections(input);
    expect(result.section.url).toBe('http://example.com?a=1&b=2');
  });
});

// ── parseStringArray ─────────────────────────────────────────

describe('parseStringArray', () => {
  test('parses quoted array', () => {
    expect(parseStringArray('["id", "name", "status"]')).toEqual(['id', 'name', 'status']);
  });

  test('parses unquoted array', () => {
    expect(parseStringArray('[a, b, c]')).toEqual(['a', 'b', 'c']);
  });

  test('handles single element', () => {
    expect(parseStringArray('["only"]')).toEqual(['only']);
  });

  test('handles empty array', () => {
    expect(parseStringArray('[]')).toEqual([]);
  });

  test('returns empty for non-array input', () => {
    expect(parseStringArray('not an array')).toEqual([]);
  });

  test('strips mixed quotes', () => {
    expect(parseStringArray(`["a", 'b', c]`)).toEqual(['a', 'b', 'c']);
  });
});

// ── parseInteger ─────────────────────────────────────────────

describe('parseInteger', () => {
  test('parses valid integer', () => {
    expect(parseInteger('42', 0)).toBe(42);
  });

  test('returns fallback for undefined', () => {
    expect(parseInteger(undefined, 99)).toBe(99);
  });

  test('returns fallback for non-numeric', () => {
    expect(parseInteger('abc', 10)).toBe(10);
  });

  test('parses negative integer', () => {
    expect(parseInteger('-5', 0)).toBe(-5);
  });
});

// ── parseString ──────────────────────────────────────────────

describe('parseString', () => {
  test('returns value as-is', () => {
    expect(parseString('hello', 'default')).toBe('hello');
  });

  test('returns fallback for undefined', () => {
    expect(parseString(undefined, 'default')).toBe('default');
  });

  test('strips remaining quotes', () => {
    expect(parseString('"quoted"', 'default')).toBe('quoted');
    expect(parseString("'quoted'", 'default')).toBe('quoted');
  });
});

```
