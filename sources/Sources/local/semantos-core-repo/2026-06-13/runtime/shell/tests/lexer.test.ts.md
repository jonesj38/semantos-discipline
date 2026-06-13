---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/tests/lexer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.361037+00:00
---

# runtime/shell/tests/lexer.test.ts

```ts
import { describe, test, expect } from 'bun:test';
import { lexShellInput } from '../src/util/lexer';

describe('lexShellInput — basic tokenization', () => {
  test('splits on whitespace', () => {
    const { args } = lexShellInput('inspect job-1774');
    expect(args).toEqual(['inspect', 'job-1774']);
  });

  test('collapses multiple spaces', () => {
    const { args } = lexShellInput('list   --type   Job');
    expect(args).toEqual(['list', '--type', 'Job']);
  });

  test('handles tabs as delimiters', () => {
    const { args } = lexShellInput("list\t--type\tJob");
    expect(args).toEqual(['list', '--type', 'Job']);
  });

  test('empty string returns empty array', () => {
    const { args } = lexShellInput('');
    expect(args).toEqual([]);
  });

  test('whitespace-only returns empty array', () => {
    const { args } = lexShellInput('   ');
    expect(args).toEqual([]);
  });
});

describe('lexShellInput — single quotes', () => {
  test('preserves spaces inside single quotes', () => {
    const { args } = lexShellInput("new 'trades.job' --urgency 'very high'");
    expect(args).toEqual(['new', 'trades.job', '--urgency', 'very high']);
  });

  test('single-quoted string with no spaces', () => {
    const { args } = lexShellInput("inspect 'obj-1'");
    expect(args).toEqual(['inspect', 'obj-1']);
  });
});

describe('lexShellInput — double quotes', () => {
  test('preserves spaces inside double quotes', () => {
    const { args } = lexShellInput('taxonomy nearest "I need a plumber"');
    expect(args).toEqual(['taxonomy', 'nearest', 'I need a plumber']);
  });

  test('backslash-escaped double quote inside double quotes', () => {
    const { args } = lexShellInput('eval "(= name \\"hello\\")"');
    expect(args).toEqual(['eval', '(= name "hello")']);
  });

  test('backslash-escaped backslash inside double quotes', () => {
    const { args } = lexShellInput('eval "path\\\\to"');
    expect(args).toEqual(['eval', 'path\\to']);
  });

  test('\\n inside double quotes becomes newline', () => {
    const { args } = lexShellInput('eval "line1\\nline2"');
    expect(args).toEqual(['eval', 'line1\nline2']);
  });

  test('\\t inside double quotes becomes tab', () => {
    const { args } = lexShellInput('eval "col1\\tcol2"');
    expect(args).toEqual(['eval', 'col1\tcol2']);
  });
});

describe('lexShellInput — backslash outside quotes', () => {
  test('backslash-space produces literal space', () => {
    const { args } = lexShellInput('load my\\ extension');
    expect(args).toEqual(['load', 'my extension']);
  });
});

describe('lexShellInput — open quotes', () => {
  test('unclosed single quote reported', () => {
    const result = lexShellInput("eval '(> amount");
    expect(result.openQuote).toBe("'");
    expect(result.args).toEqual(['eval', '(> amount']);
  });

  test('unclosed double quote reported', () => {
    const result = lexShellInput('eval "(> amount');
    expect(result.openQuote).toBe('"');
    expect(result.args).toEqual(['eval', '(> amount']);
  });

  test('closed quotes have no openQuote', () => {
    const result = lexShellInput('eval "(> amount 500)"');
    expect(result.openQuote).toBeUndefined();
  });
});

describe('lexShellInput — mixed quotes', () => {
  test('single quotes inside double quotes are literal', () => {
    const { args } = lexShellInput(`eval "it's fine"`);
    expect(args).toEqual(['eval', "it's fine"]);
  });

  test('double quotes inside single quotes are literal', () => {
    const { args } = lexShellInput(`eval 'say "hello"'`);
    expect(args).toEqual(['eval', 'say "hello"']);
  });
});

```
