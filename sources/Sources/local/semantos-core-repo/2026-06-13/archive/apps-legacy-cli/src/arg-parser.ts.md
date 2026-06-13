---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/src/arg-parser.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.698536+00:00
---

# archive/apps-legacy-cli/src/arg-parser.ts

```ts
/**
 * Minimal argv parser for the Phase 1 CLI.
 *
 * Yields a `LegacyVerbCommand` shape compatible with `routeLegacy`:
 *   { positional: string[], flags: Record<string, unknown> }
 *
 * Grammar:
 *   <verb> [subcommand] [positional...] [--flag value] [--bool-flag]
 *
 * Boolean flags (`--pkce`, `--dry-run`) auto-detect when the next
 * token starts with `--` or is missing. Numeric flag values are
 * parsed eagerly into numbers; everything else stays a string.
 *
 * Top-level CLI flags (`--root`, `--passphrase`) are stripped before
 * the verb is dispatched and returned separately.
 */

export interface ParsedArgs {
  /** Positional args, including the subcommand verb. */
  positional: string[];
  /** Verb-level flags. */
  flags: Record<string, unknown>;
  /** CLI-level flags (consumed before dispatching). */
  cliFlags: {
    root?: string;
    passphrase?: string;
    help?: boolean;
    quiet?: boolean;
  };
}

/** Recognised CLI-level flag names. Verb-level flags are anything else. */
const CLI_FLAG_NAMES = new Set(['root', 'passphrase', 'help', 'quiet']);

export function parseArgs(argv: string[]): ParsedArgs {
  const positional: string[] = [];
  const flags: Record<string, unknown> = {};
  const cliFlags: ParsedArgs['cliFlags'] = {};

  for (let i = 0; i < argv.length; i++) {
    const tok = argv[i];

    if (tok === '--') {
      // Everything after `--` is positional.
      positional.push(...argv.slice(i + 1));
      break;
    }

    if (tok.startsWith('--')) {
      const name = tok.slice(2);
      const next = argv[i + 1];
      const isBool = next === undefined || next.startsWith('--');
      const value: unknown = isBool ? true : coerce(next);
      if (CLI_FLAG_NAMES.has(name)) {
        (cliFlags as Record<string, unknown>)[name] = value;
      } else {
        flags[name] = value;
      }
      if (!isBool) i += 1;
      continue;
    }

    positional.push(tok);
  }

  return { positional, flags, cliFlags };
}

function coerce(raw: string): string | number {
  if (raw === '') return raw;
  const n = Number(raw);
  if (Number.isFinite(n) && /^-?\d*\.?\d+$/.test(raw)) return n;
  return raw;
}

```
