---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/repl.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.365990+00:00
---

# runtime/shell/src/repl.ts

```ts
/**
 * Interactive REPL — readline-based shell with tab completion,
 * command history, and built-in commands.
 *
 * Reuses the same parser + router as single-command mode.
 * Prompt reflects active hat and extension.
 */

import { createInterface, type Interface } from 'readline';
import { parseCommand, KNOWN_VERBS } from './parser';
import { route } from './router';
import { OutputFormatter, parseOutputFormat } from './formatters';
import type { ShellContext } from './types';
import { lexShellInput } from './util/lexer';

const HELP_TEXT = `
Semantic Shell — typed CLI for semantic objects

VERBS:
  new <type-path> [--flags]       Create a new semantic object
  patch <object-id> [--flags]     Apply a mutation to an object
  transition <id> --visibility X  Change visibility state
  inspect <object-id>             Show object details
  trace <object-id>               View evidence chain
  verify <object-id>              Verify evidence chain integrity
  sign <object-id>                Attach hat signature
  publish <object-id>             Publish: draft -> published
  revoke <object-id>              Revoke: published -> revoked
  stake <object-id>               Start governance staking flow
  vote <object-id>                Cast governance vote
  dispute <object-id>             File a dispute
  transfer <id> --to <hat-id>   Transfer ownership
  flow start|advance|cancel|list  Manage multi-step flows
  list [--type X] [--status X]    List objects with filters
  eval <expression>               Evaluate a Lisp policy expression
  compile <expression>            Compile a Lisp expression to cell opcodes
  bind <policy-ref> [type-path]   Bind a compiled policy to a type

EXTENSIONS (Phase 36E):
  extension list [--json]          List installed extensions with grammar summary
  extension status                 Show extraction status, version compat, governance alerts
  extension detail <id>            Show grammar summary, capabilities, trust signals
    --grammar                      Show full grammar details
    --entities                     Show entity list
    --history                      Show extraction history

IDENTITY (Phase 19.5):
  identity register <email>       Register a new identity via Plexus
  identity derive <resource-id>   Derive a child hat
  identity resolve <cert-id>      Look up certificate details
  identity list                   List facets under current identity
  whoami                          Show current identity, hat, capabilities
  capabilities                    List active hat's capabilities

FLAGS:
  --format json|table|cell|csv    Output format (default: json)
  --dry-run                       Show capability checks without executing
  --verbose                       Extra detail

BUILT-IN COMMANDS:
  help                            Show this help
  switch <hat-id>               Change active hat
  load <extension>                 Change active extension
  exit                            Quit the REPL

EXAMPLES:
  new trades.job.plumbing --urgency high
  inspect job-1774
  list --type Job --status draft --format table
  publish job-1774 --dry-run
  flow start new-job-intake
  identity register alice@example.com
  whoami
`.trim();

export class REPLShell {
  private rl: Interface | null = null;
  private formatter = new OutputFormatter();

  constructor(private ctx: ShellContext) {}

  async repl(): Promise<void> {
    this.rl = createInterface({
      input: process.stdin,
      output: process.stderr, // prompts to stderr so stdout stays clean for pipes
      prompt: this.buildPrompt(),
      completer: (line: string) => this.completer(line),
      terminal: true,
    });

    this.rl.prompt();

    for await (const line of this.rl) {
      const trimmed = line.trim();
      if (!trimmed) {
        this.rl.prompt();
        continue;
      }

      const handled = await this.handleBuiltIn(trimmed);
      if (handled === 'exit') break;
      if (handled) {
        this.rl.prompt();
        continue;
      }

      // Parse and execute shell command
      try {
        const { args } = lexShellInput(trimmed);
        const cmd = parseCommand(args);
        const format = parseOutputFormat(cmd.flags.format ?? this.ctx.defaultFormat);
        const result = await route(cmd, this.ctx);
        const output = this.formatter.format(result, format);
        // Output goes to stdout for pipe composability
        process.stdout.write(output + '\n');
      } catch (err) {
        process.stderr.write(`Error: ${err instanceof Error ? err.message : String(err)}\n`);
      }

      this.rl.prompt();
    }

    this.rl.close();
  }

  private buildPrompt(): string {
    const hatId = this.ctx.activeHatId ?? 'no-hat';
    const extension = this.ctx.activeExtension;
    // Shorten extension name for display
    const shortExtension = extension.replace('-services', '').replace('services-', '');
    return `[${hatId}@${shortExtension}] > `;
  }

  private async handleBuiltIn(input: string): Promise<boolean | 'exit'> {
    const { args: parts } = lexShellInput(input);
    if (parts.length === 0) return false;
    const cmd = parts[0].toLowerCase();

    if (cmd === 'exit' || cmd === 'quit') {
      return 'exit';
    }

    if (cmd === 'help') {
      process.stderr.write(HELP_TEXT + '\n');
      return true;
    }

    if (cmd === 'switch' && parts.length >= 2) {
      const hatId = parts[1];
      this.ctx.activeHatId = hatId;
      this.ctx.identity.switchHat(hatId);
      if (this.rl) {
        this.rl.setPrompt(this.buildPrompt());
      }
      process.stderr.write(`Switched to hat: ${hatId}\n`);
      return true;
    }

    if (cmd === 'load' && parts.length >= 2) {
      const extension = parts[1];
      try {
        await this.ctx.config.switchExtension(extension);
        this.ctx.activeExtension = extension;
        if (this.rl) {
          this.rl.setPrompt(this.buildPrompt());
        }
        process.stderr.write(`Loaded extension: ${extension}\n`);
      } catch (err) {
        process.stderr.write(`Error loading extension: ${err instanceof Error ? err.message : String(err)}\n`);
      }
      return true;
    }

    return false;
  }

  private completer(line: string): [string[], string] {
    const { args: parts } = lexShellInput(line);

    // Complete verb (first word)
    if (parts.length <= 1) {
      const prefix = parts[0] || '';
      const matches = [...KNOWN_VERBS, 'help', 'switch', 'load', 'exit']
        .filter(v => v.startsWith(prefix));
      return [matches, prefix];
    }

    // Complete type paths (after verb)
    const lastPart = parts[parts.length - 1];

    // If typing a flag value after --type, complete type names
    if (parts.length >= 3 && parts[parts.length - 2] === '--type') {
      return [this.getTypeNames().filter(t => t.startsWith(lastPart)), lastPart];
    }

    // If last part starts with --, complete flag names
    if (lastPart.startsWith('--')) {
      const prefix = lastPart.slice(2);
      const commonFlags = ['format', 'dry-run', 'verbose', 'type', 'status', 'to', 'visibility'];
      const matches = commonFlags.filter(f => f.startsWith(prefix)).map(f => '--' + f);
      return [matches, lastPart];
    }

    // After 'identity', complete sub-actions
    if (parts[0] === 'identity' && parts.length === 2) {
      const actions = ['register', 'derive', 'resolve', 'list'];
      const matches = actions.filter(a => a.startsWith(lastPart));
      return [matches, lastPart];
    }

    // After 'new', complete type paths
    if (parts[0] === 'new') {
      const typePaths = this.getTypeNames();
      const matches = typePaths.filter(t => t.toLowerCase().startsWith(lastPart.toLowerCase()));
      return [matches, lastPart];
    }

    // After object-id verbs, complete object IDs
    if (['inspect', 'trace', 'verify', 'sign', 'publish', 'revoke', 'patch', 'transition', 'transfer'].includes(parts[0])) {
      const objectIds = this.getObjectIds();
      const matches = objectIds.filter(id => id.startsWith(lastPart));
      return [matches, lastPart];
    }

    return [[], lastPart];
  }

  private getTypeNames(): string[] {
    const config = this.ctx.config.getConfig();
    if (!config) return [];
    return config.objectTypes.map(t => t.name);
  }

  private getObjectIds(): string[] {
    const state = this.ctx.store.getState();
    return [...state.objects.keys()];
  }
}


```
