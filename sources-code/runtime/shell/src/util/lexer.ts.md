---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/util/lexer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.369415+00:00
---

# runtime/shell/src/util/lexer.ts

```ts
/**
 * Unified shell input tokenizer — single source of truth for splitting
 * command-line input into arguments, respecting quotes and escapes.
 *
 * Used by: command execution, built-in command handling, tab completer.
 */

export interface LexResult {
  /** Parsed argument tokens. */
  args: string[];
  /** Set if the input ends inside an unclosed quote (useful for completer). */
  openQuote?: "'" | '"';
}

/**
 * Tokenize a shell input line into arguments.
 *
 * Supports:
 * - Single-quoted strings ('...')
 * - Double-quoted strings ("...")
 * - Backslash escapes within double quotes (\" \\ \n \t)
 * - Backslash-space outside quotes to include literal spaces
 * - Whitespace as delimiter outside quotes
 */
export function lexShellInput(line: string): LexResult {
  const args: string[] = [];
  let current = '';
  let inSingleQuote = false;
  let inDoubleQuote = false;

  for (let i = 0; i < line.length; i++) {
    const ch = line[i];

    if (inSingleQuote) {
      if (ch === "'") {
        inSingleQuote = false;
      } else {
        current += ch;
      }
      continue;
    }

    if (inDoubleQuote) {
      if (ch === '\\' && i + 1 < line.length) {
        const next = line[i + 1];
        if (next === '"' || next === '\\') {
          current += next;
          i++;
        } else if (next === 'n') {
          current += '\n';
          i++;
        } else if (next === 't') {
          current += '\t';
          i++;
        } else {
          current += ch;
        }
      } else if (ch === '"') {
        inDoubleQuote = false;
      } else {
        current += ch;
      }
      continue;
    }

    // Outside quotes
    if (ch === "'") {
      inSingleQuote = true;
      continue;
    }
    if (ch === '"') {
      inDoubleQuote = true;
      continue;
    }
    if (ch === '\\' && i + 1 < line.length) {
      // Escape next character (e.g., backslash-space for literal space)
      current += line[i + 1];
      i++;
      continue;
    }
    if (ch === ' ' || ch === '\t') {
      if (current.length > 0) {
        args.push(current);
        current = '';
      }
      continue;
    }
    current += ch;
  }

  if (current.length > 0) {
    args.push(current);
  }

  const openQuote = inSingleQuote ? "'" : inDoubleQuote ? '"' : undefined;
  return { args, openQuote };
}

```
