---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/parser.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.365192+00:00
---

# runtime/shell/src/parser.ts

```ts
/**
 * Command grammar parser — parses CLI args into structured ShellCommand.
 *
 * Grammar:  semantos <verb> [<type-path>] [--flags] [<object-id>]
 *
 * Examples:
 *   semantos new trades.job.plumbing --urgency high
 *   semantos inspect job-1774
 *   semantos list --type governance.dispute --status open --format json
 *   semantos publish job-1774 --dry-run
 *   semantos identity register alice@example.com
 *   semantos whoami
 *   semantos capabilities
 *
 * Phase 19.5: Added identity, whoami, capabilities verbs.
 */

/** The known verbs in the semantic shell grammar. */
export const KNOWN_VERBS = [
  'new', 'patch', 'transition', 'inspect', 'trace', 'verify', 'sign',
  'publish', 'revoke', 'stake', 'vote', 'dispute', 'transfer', 'flow',
  'eval', 'compile', 'bind', 'list', 'identity', 'whoami', 'capabilities', 'taxonomy',
  'cdm', 'game', 'grammar', 'infer', 'extract',
  'settle', 'govern', 'extension',
  'share', 'export', 'merge', 'diff',
  'host.exec',  // Phase 38C — publish-before-execute dispatcher
  'host.audit', // Phase 38D — read-only cryptographic audit of HostCommand
] as const;

export type ShellVerb = typeof KNOWN_VERBS[number];

export interface ShellCommand {
  verb: ShellVerb;
  typePath?: string;
  objectId?: string;
  flags: Record<string, string | boolean>;
  rawArgs: string[];
}

/** Verbs that primarily take an object ID, not a type path. */
const OBJECT_ID_VERBS = new Set<ShellVerb>([
  'inspect', 'trace', 'verify', 'sign', 'publish', 'revoke',
  'stake', 'vote', 'dispute', 'transfer', 'patch', 'transition',
  'settle',
  'share', 'export', 'merge', 'diff',
]);

/** Verbs that take a type path as the first positional arg. */
const TYPE_PATH_VERBS = new Set<ShellVerb>(['new']);

/** Verbs that use sub-command pattern (first positional = action, second = target). */
const SUBCOMMAND_VERBS = new Set<ShellVerb>(['flow', 'identity', 'cdm', 'game', 'grammar', 'infer', 'extract']);

/** Verbs that take no positional args. */
const NO_ARGS_VERBS = new Set<ShellVerb>(['list', 'whoami', 'capabilities']);

/** Compute Levenshtein distance between two strings. */
function levenshtein(a: string, b: string): number {
  const m = a.length;
  const n = b.length;
  const dp: number[][] = Array.from({ length: m + 1 }, () => Array(n + 1).fill(0));
  for (let i = 0; i <= m; i++) dp[i][0] = i;
  for (let j = 0; j <= n; j++) dp[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] = a[i - 1] === b[j - 1]
        ? dp[i - 1][j - 1]
        : 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
    }
  }
  return dp[m][n];
}

/** Suggest the closest known verb for a typo. */
function suggestVerb(input: string): string | null {
  let best: string | null = null;
  let bestDist = Infinity;
  for (const verb of KNOWN_VERBS) {
    const d = levenshtein(input, verb);
    if (d < bestDist) {
      bestDist = d;
      best = verb;
    }
  }
  return bestDist <= 3 ? best : null;
}

/**
 * Parse CLI arguments into a structured ShellCommand.
 * Throws an Error with a helpful message on invalid input.
 */
export function parseCommand(args: string[]): ShellCommand {
  if (args.length === 0) {
    throw new Error('No command provided. Usage: semantos <verb> [<type-path>] [--flags] [<object-id>]');
  }

  // Extract verb — first non-flag arg
  let verbIndex = -1;
  for (let i = 0; i < args.length; i++) {
    if (!args[i].startsWith('--')) {
      verbIndex = i;
      break;
    }
  }

  if (verbIndex === -1) {
    throw new Error('No verb found. Usage: semantos <verb> [<type-path>] [--flags] [<object-id>]');
  }

  const verbStr = args[verbIndex];

  // Validate verb
  if (!(KNOWN_VERBS as readonly string[]).includes(verbStr)) {
    const suggestion = suggestVerb(verbStr);
    const hint = suggestion ? ` Did you mean '${suggestion}'?` : '';
    throw new Error(
      `Unknown verb '${verbStr}'.${hint} Available verbs: ${KNOWN_VERBS.join(', ')}`
    );
  }

  const verb = verbStr as ShellVerb;

  // Collect flags and remaining positional args
  const flags: Record<string, string | boolean> = {};
  const positionals: string[] = [];

  for (let i = 0; i < args.length; i++) {
    if (i === verbIndex) continue; // skip verb itself
    const arg = args[i];

    if (arg.startsWith('--')) {
      const key = arg.slice(2);
      if (!key) continue;
      // Check if next arg is a value (not another flag and not past end)
      const next = args[i + 1];
      if (next !== undefined && !next.startsWith('--')) {
        flags[key] = next;
        i++; // consume the value
      } else {
        flags[key] = true; // boolean flag
      }
    } else {
      positionals.push(arg);
    }
  }

  // Interpret positional args based on verb
  let typePath: string | undefined;
  let objectId: string | undefined;

  if (NO_ARGS_VERBS.has(verb)) {
    // list, whoami, capabilities take no positional args — everything via flags
  } else if (verb === 'identity') {
    // identity uses positionals: action + target
    // semantos identity register alice@example.com
    // semantos identity derive my-device
    // semantos identity resolve cert:abc123
    // semantos identity list
    if (positionals.length >= 1) {
      flags['action'] = positionals[0];
    }
    if (positionals.length >= 2) {
      objectId = positionals[1];
    }
  } else if (verb === 'flow') {
    // flow uses positionals as sub-command args (e.g., "flow start new-job-intake")
    if (positionals.length >= 1) {
      flags['subcommand'] = positionals[0];
    }
    if (positionals.length >= 2) {
      flags['flow'] = positionals[1];
    }
  } else if (verb === 'taxonomy') {
    // taxonomy uses positionals as sub-command + args
    // e.g., "taxonomy embed", "taxonomy distance create.job create.quote"
    // e.g., "taxonomy nearest 'I need a plumber'"
    if (positionals.length >= 1) {
      flags['subcommand'] = positionals[0];
    }
    if (positionals.length >= 2) {
      // For 'distance': two dotted paths; for 'nearest': utterance string
      if (positionals[0] === 'distance') {
        flags['pathA'] = positionals[1];
        if (positionals.length >= 3) {
          flags['pathB'] = positionals[2];
        }
      } else if (positionals[0] === 'nearest') {
        flags['utterance'] = positionals.slice(1).join(' ');
      }
    }
  } else if (verb === 'cdm') {
    // cdm uses positionals: subcommand + optional target
    // e.g., "cdm import --file trade.json", "cdm event <id> --type confirmation"
    if (positionals.length >= 1) {
      flags['subcommand'] = positionals[0];
    }
    if (positionals.length >= 2) {
      objectId = positionals[1];
    }
  } else if (verb === 'game') {
    // game uses positionals: gameType + subcommand
    // e.g., "game risk new --players 3", "game risk attack --from 5 --to 12"
    // e.g., "game chess move --move e2e4", "game life step --count 5"
    if (positionals.length >= 1) {
      objectId = positionals[0]; // game type: chess, go, cards, life, risk
    }
    if (positionals.length >= 2) {
      flags['subcommand'] = positionals[1]; // action: new, move, attack, etc.
    }
    // Any remaining positionals become the expression (for move notation, etc.)
    if (positionals.length >= 3) {
      flags['expression'] = positionals.slice(2).join(' ');
    }
  } else if (verb === 'grammar') {
    // grammar uses positionals: subcommand + path(s)
    // e.g., "grammar validate ./grammar.json"
    // e.g., "grammar diff old.json new.json"
    // e.g., "grammar list"
    // e.g., "grammar inspect ./grammar.json"
    // e.g., "grammar test ./grammar.json"
    if (positionals.length >= 1) {
      flags['subcommand'] = positionals[0];
    }
    if (positionals.length >= 2) {
      flags['path'] = positionals[1];
    }
    if (positionals.length >= 3) {
      flags['newPath'] = positionals[2]; // For diff: second file path
    }
  } else if (verb === 'infer') {
    // infer uses positionals: subcommand/path + optional target
    // e.g., "infer review <grammar-id>", "infer approve <grammar-id>"
    // e.g., "infer ./sample.json", "infer https://api.example.com/v2"
    // e.g., "infer list --status draft"
    if (positionals.length >= 1) {
      flags['subcommand'] = positionals[0];
    }
    if (positionals.length >= 2) {
      flags['path'] = positionals[1];
    }
  } else if (verb === 'host.exec') {
    // host.exec uses positionals: handler id
    // e.g., "host.exec process.killByPort --arg port=9000 --dry-run --timeout 5000"
    if (positionals.length >= 1) {
      flags['handler'] = positionals[0];
    }
  } else if (verb === 'host.audit') {
    // host.audit uses positionals: hostCommandId
    // e.g., "host.audit obj-12345"
    if (positionals.length >= 1) {
      objectId = positionals[0];
    }
  } else if (verb === 'eval' || verb === 'compile') {
    // eval/compile take expression as positional
    if (positionals.length >= 1) {
      flags['expression'] = positionals.join(' ');
    }
  } else if (verb === 'bind') {
    // bind takes policy reference as first positional
    if (positionals.length >= 1) {
      flags['expression'] = positionals[0];
    }
    if (positionals.length >= 2) {
      // Second positional could be type path if --type not given
      typePath = positionals[1];
    }
  } else if (TYPE_PATH_VERBS.has(verb)) {
    // new expects typePath first, then optional objectId
    typePath = positionals[0];
    objectId = positionals[1];
  } else if (OBJECT_ID_VERBS.has(verb)) {
    // inspect, trace, etc. expect objectId
    objectId = positionals[0];
    // If a second positional exists, it might be additional context
    if (positionals.length > 1) {
      typePath = positionals[1];
    }
  } else {
    // Default: first positional is typePath or objectId
    if (positionals.length >= 2) {
      typePath = positionals[0];
      objectId = positionals[1];
    } else if (positionals.length === 1) {
      // Heuristic: if it contains dots, it's a type path
      if (positionals[0].includes('.')) {
        typePath = positionals[0];
      } else {
        objectId = positionals[0];
      }
    }
  }

  return { verb, typePath, objectId, flags, rawArgs: args };
}

```
