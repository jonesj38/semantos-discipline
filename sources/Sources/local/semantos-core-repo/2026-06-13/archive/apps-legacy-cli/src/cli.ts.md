---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/src/cli.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.698268+00:00
---

# archive/apps-legacy-cli/src/cli.ts

```ts
#!/usr/bin/env bun
/**
 * Phase 1 legacy-ingest CLI.
 *
 * Reference: docs/design/V1.0-EXECUTION-PLAN.md §5; docs/guides/
 * LEGACY-INGEST-GMAIL-SETUP.md.
 *
 * Single-process Bun dispatcher for the `legacy <verb>` REPL surface.
 * Used by the operator on their VPS via:
 *
 *   ssh rbs bun run --cwd /opt/semantos legacy-cli -- <verb> [args] [flags]
 *
 * Phase 2 collapses this into a Semantos Brain-managed Bun service; the
 * dispatcher logic stays the same, only the transport changes
 * (stdin/stdout → unix socket from the Semantos Brain broker).
 */

import { parseArgs } from './arg-parser';
import { bootstrap } from './bootstrap';
import { serveMeta } from './serve';
import { makeRouteLegacy, type Proposal } from '@semantos/legacy-ingest';
import type { SIRProgram } from '@semantos/semantos-sir';

async function main(): Promise<number> {
  const { positional, flags, cliFlags } = parseArgs(process.argv.slice(2));

  if (cliFlags.help && positional.length === 0) {
    printHelp();
    return 0;
  }

  if (positional.length === 0) {
    printHelp();
    return 1;
  }

  let bootstrapped;
  try {
    bootstrapped = await bootstrap({
      root: cliFlags.root,
      passphrase: cliFlags.passphrase ?? process.env.SEMANTOS_LEGACY_PASSPHRASE,
      // Hat id wired from env for now; Phase 2 sources from brain broker.
      hatIdProvider: () => process.env.SEMANTOS_HAT_ID ?? null,
      openBrowser: async (url) => {
        // VPS context typically has no browser. Print the URL clearly
        // for the operator to copy. Phase 2 prefers the Semantos Brain broker's
        // open-on-paired-device path.
        process.stderr.write(`\nOpen this URL in your browser to grant access:\n  ${url}\n\n`);
      },
      openCorrectionEditor: openInDefaultEditor,
    });
  } catch (err) {
    bail(err);
    return 1;
  }

  // `legacy serve` — long-running Meta webhook server.
  // Must be handled before the one-shot routeLegacy dispatcher because
  // serveMeta() does not return until SIGINT/SIGTERM.
  if (positional[0] === 'serve') {
    try {
      await serveMeta({
        metaFanOutSink: bootstrapped.metaFanOutSink,
        shutdown: bootstrapped.shutdown.bind(bootstrapped),
      });
    } catch (err) {
      bail(err);
      return 1;
    }
    return 0;
  }

  try {
    const route = makeRouteLegacy(bootstrapped.ctx);
    const result = await route({ positional, flags }, null);
    emit(result, !!cliFlags.quiet);
    return isErrorResult(result) ? 1 : 0;
  } catch (err) {
    bail(err);
    return 1;
  } finally {
    await bootstrapped.shutdown();
  }
}

function emit(result: unknown, quiet: boolean): void {
  if (quiet) {
    if (isErrorResult(result)) {
      process.stderr.write(`error: ${(result as { error: string }).error}\n`);
    }
    return;
  }
  process.stdout.write(JSON.stringify(result, null, 2) + '\n');
}

function isErrorResult(result: unknown): boolean {
  return (
    typeof result === 'object' &&
    result !== null &&
    'error' in (result as Record<string, unknown>)
  );
}

function bail(err: unknown): void {
  const message = err instanceof Error ? err.message : String(err);
  process.stderr.write(`legacy-cli: ${message}\n`);
}

function printHelp(): void {
  process.stderr.write(
`legacy — Paskian-migration CLI (Phase 1)

Usage:
  legacy [--root <dir>] [--passphrase <p>] [--quiet] <verb> [args] [flags]

CLI flags:
  --root <dir>        Root for legacy-ingest state (default: ~/.semantos)
  --passphrase <p>    Wallet passphrase (or set SEMANTOS_LEGACY_PASSPHRASE)
  --quiet             Suppress JSON output; only print errors to stderr
  --help              Show this message

Verbs:
  legacy register-client <provider> --client-id <id> [--client-secret <secret>] --redirect-uri <url> [--pkce]
  legacy unregister-client <provider>
  legacy clients
  legacy connect <provider>
  legacy resume <state> <code>
  legacy disconnect <provider>
  legacy status [<provider>]
  legacy providers
  legacy ingest <provider> [--since <iso>] [--max-pages <n>] [--query <q>]
  legacy auto <provider> [--interval <seconds>]
  legacy stop <provider>
  legacy review [--provider <id>] [--confidence <op><n>] [--limit <n>]
  legacy ratify <provider>:<proposal-id>
  legacy reject <provider>:<proposal-id> --reason <text>
  legacy correct <provider>:<proposal-id>
  legacy bulk-ratify [--provider <id>] --confidence <op><n> [--dry-run]
  legacy unratify <provider>:<receipt-id>
  legacy migrate-to-graph [--dry-run]
  legacy serve

  legacy serve
    Starts the Meta webhook HTTP server (port WEBHOOK_PORT, default 3002).
    Wires metaFanOutSink as onConversationTurn so Meta DMs flow to both the
    legacy JSONL store and the canonical Postgres spine (when DATABASE_URL set).
    Env: META_WEBHOOK_VERIFY_TOKEN, META_PAGE_ACCESS_TOKEN, WEBHOOK_PORT,
         DATABASE_URL, and any LLM backend vars (OLLAMA_BASE_URL,
         ANTHROPIC_API_KEY, OPENROUTER_API_KEY).

Setup runbook:
  docs/guides/LEGACY-INGEST-GMAIL-SETUP.md
`,
  );
}

/** $EDITOR-based correction editor for `legacy correct`. */
async function openInDefaultEditor(proposal: Proposal): Promise<SIRProgram | null> {
  const editor = process.env.EDITOR ?? process.env.VISUAL ?? 'vi';
  const { mkdtempSync, writeFileSync, readFileSync, unlinkSync, rmdirSync } = await import('node:fs');
  const { spawnSync } = await import('node:child_process');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const dir = mkdtempSync(join(tmpdir(), 'semantos-correct-'));
  const path = join(dir, `${proposal.proposalId}.json`);
  writeFileSync(path, JSON.stringify(proposal.program, null, 2), { mode: 0o600 });
  const result = spawnSync(editor, [path], { stdio: 'inherit' });
  if (result.status !== 0) {
    unlinkSync(path);
    rmdirSync(dir);
    return null;
  }
  const corrected = JSON.parse(readFileSync(path, 'utf8')) as SIRProgram;
  unlinkSync(path);
  rmdirSync(dir);
  return corrected;
}

main().then((code) => process.exit(code), (err) => {
  bail(err);
  process.exit(1);
});

```
