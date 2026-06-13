---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/util/simple-toml.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.369141+00:00
---

# runtime/shell/src/util/simple-toml.ts

```ts
/**
 * Minimal TOML parser — single source of truth for flat key=value
 * parsing under [section] headers.
 *
 * Used by: config.ts (shell config) and tmux/layout.ts (console config).
 *
 * Supports:
 * - [section] and [section.subsection] headers
 * - key = value pairs (strings, integers, string arrays)
 * - Quoted strings (single or double)
 * - # comments
 * - Blank lines
 *
 * Does NOT support: nested tables, inline tables, multiline strings,
 * dates, booleans, or any TOML features beyond the above.
 */

/** Parsed TOML structure: section name → key → raw string value. */
export type ParsedSections = Record<string, Record<string, string>>;

/**
 * Parse a flat TOML file into sections of string key-value pairs.
 * Section names include dots (e.g., 'panes.objects').
 */
export function parseSections(content: string): ParsedSections {
  const result: ParsedSections = {};
  let currentSection = '';

  for (const rawLine of content.split('\n')) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;

    // Section header: [name] or [name.sub]
    const sectionMatch = line.match(/^\[(.+)\]$/);
    if (sectionMatch) {
      currentSection = sectionMatch[1];
      continue;
    }

    if (!currentSection) continue;

    const eqIndex = line.indexOf('=');
    if (eqIndex === -1) continue;

    const key = line.slice(0, eqIndex).trim();
    let value = line.slice(eqIndex + 1).trim();

    // Strip surrounding quotes
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    if (!result[currentSection]) result[currentSection] = {};
    result[currentSection][key] = value;
  }

  return result;
}

/**
 * Parse a string value as an array of strings.
 * Input format: `["a", "b", "c"]` or `[a, b, c]`
 */
export function parseStringArray(value: string): string[] {
  const trimmed = value.trim();
  if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) return [];
  const inner = trimmed.slice(1, -1);
  if (!inner.trim()) return [];
  return inner.split(',').map(s => s.trim().replace(/^["']|["']$/g, ''));
}

/**
 * Parse a string value as an integer, returning fallback on failure.
 */
export function parseInteger(value: string | undefined, fallback: number): number {
  if (value === undefined) return fallback;
  const n = parseInt(value, 10);
  return Number.isNaN(n) ? fallback : n;
}

/**
 * Parse a string value, stripping any remaining quotes.
 * Returns fallback if value is undefined.
 */
export function parseString(value: string | undefined, fallback: string): string {
  if (value === undefined) return fallback;
  return value.replace(/^["']|["']$/g, '');
}

```
