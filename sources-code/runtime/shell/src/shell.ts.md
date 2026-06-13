---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/shell.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.364106+00:00
---

# runtime/shell/src/shell.ts

```ts
/**
 * Shell — coordinates parsing, routing, and formatting for
 * both single-command and REPL modes.
 */

import { parseCommand } from './parser';
import { route } from './router';
import { OutputFormatter, parseOutputFormat } from './formatters';
import { REPLShell } from './repl';
import type { ShellContext } from './types';

export class Shell {
  private formatter = new OutputFormatter();

  constructor(private ctx: ShellContext) {}

  /**
   * Execute a single command from CLI args.
   * Returns the formatted output string (stdout).
   * Throws on parse errors (caller should write to stderr).
   */
  async execute(args: string[]): Promise<string> {
    const cmd = parseCommand(args);
    const format = parseOutputFormat(cmd.flags.format ?? this.ctx.defaultFormat);
    const result = await route(cmd, this.ctx);
    return this.formatter.format(result, format);
  }

  /** Enter interactive REPL mode. */
  async repl(): Promise<void> {
    const replShell = new REPLShell(this.ctx);
    await replShell.repl();
  }
}

```
