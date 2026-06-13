---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/intent-adapters/shell-to-intent.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.370304+00:00
---

# runtime/shell/src/intent-adapters/shell-to-intent.ts

```ts
/**
 * shellCommandToIntent — map a parsed ShellCommand to a pipeline Intent.
 *
 * The shell is a deterministic input mode: no LLM in the loop, no
 * inferred confidence. Every successful `parseCommand` produces an
 * Intent with confidence=1.0 and source='shell'. The adapter's only
 * judgment calls are:
 *
 *   1. Jural category per verb (table below)
 *   2. What goes in `target`  — objectId / typePath from ShellCommand
 *   3. What goes in `constraints` — flags with a clear constraint shape
 *      (e.g. `--capability 5`). Unknown flags ride along in producerMeta
 *      for debugging and do not affect lowering.
 *
 * Read-only verbs (inspect / trace / verify / list / whoami / ...)
 * return null — they bypass the pipeline per docs/INTENT-PIPELINE.md
 * §"Open questions" #4. Callers should route those through the existing
 * direct handlers.
 *
 * See docs/INTENT-PIPELINE.md §"Shell verb dispatch → Intent".
 */

import type { ShellCommand, ShellVerb } from '../parser';
import type {
  Intent,
  IntentId,
  IntentSource,
} from '@semantos/intent';
import type {
  JuralCategory,
  SIRConstraint,
  SIRTarget,
  TaggedCategory,
  TaxonomyCoordinates,
} from '@semantos/semantos-sir';
import { getVerbRegistration } from '@semantos/runtime-services';

// ── Verb classification ─────────────────────────────────────

/**
 * Jural category per mutating verb. Read-only verbs are marked
 * `null` and return a null Intent.
 *
 * Rationale per category:
 *  - `declaration` — asserts facts or state (create, patch, vote, etc.)
 *  - `power`       — changes relations or phase (transition, publish,
 *                    revoke, share, host.exec)
 *  - `transfer`    — moves value or rights (stake, transfer, settle)
 *  - `obligation` / `permission` / `prohibition` / `condition` —
 *                    currently unmapped from shell verbs; surface grammar
 *                    extensions may introduce verbs in these categories.
 *
 * This is a pragmatic default table — adjust entries as real verbs
 * demand different governance shapes.
 */
const VERB_CATEGORY: Record<ShellVerb, JuralCategory | null> = {
  // Mutations
  new: 'declaration',
  patch: 'declaration',
  transition: 'power',
  sign: 'declaration',
  publish: 'power',
  revoke: 'power',
  stake: 'transfer',
  vote: 'declaration',
  dispute: 'declaration',
  transfer: 'transfer',
  flow: 'power',
  settle: 'transfer',
  govern: 'power',
  extension: 'power',
  share: 'power',
  export: 'declaration',
  merge: 'declaration',
  'host.exec': 'power',
  bind: 'declaration',
  compile: 'declaration',
  // Read-only — bypass the pipeline
  inspect: null,
  trace: null,
  verify: null,
  eval: null,
  list: null,
  identity: null,
  whoami: null,
  capabilities: null,
  taxonomy: null,
  cdm: null,
  game: null,
  grammar: null,
  infer: null,
  extract: null,
  diff: null,
  'host.audit': null,
};

export function isShellVerbMutation(verb: ShellVerb): boolean {
  return VERB_CATEGORY[verb] !== null;
}

// ── Flag → constraint extractors ────────────────────────────

/**
 * Convert well-known flags into SIRConstraints. Flags with no
 * recognised constraint shape fall through to producerMeta.
 *
 * Kept narrow on purpose: only flags that clearly map to a typed
 * constraint become constraints. Everything else is metadata.
 */
function extractConstraints(flags: ShellCommand['flags']): {
  constraints: SIRConstraint[];
  leftovers: Record<string, string | boolean>;
} {
  const constraints: SIRConstraint[] = [];
  const leftovers: Record<string, string | boolean> = {};

  for (const [key, value] of Object.entries(flags)) {
    // --capability N  (e.g. --capability 5 for SIGNING)
    if (key === 'capability' && typeof value === 'string' && /^\d+$/.test(value)) {
      const required = parseInt(value, 10);
      constraints.push({
        kind: 'capability',
        required,
        name: `cap-${required}`,
      });
      continue;
    }
    // --domain N
    if (key === 'domain' && typeof value === 'string' && /^\d+$/.test(value)) {
      constraints.push({ kind: 'domain', flag: parseInt(value, 10) });
      continue;
    }
    leftovers[key] = value;
  }

  return { constraints, leftovers };
}

// ── ID generation hook ──────────────────────────────────────
//
// The adapter is pure — it doesn't generate the intent id itself.
// Callers inject a generator so tests are deterministic. For the
// shell REPL, pass a UUID v7 generator.

export interface AdapterOptions {
  /** Generates the Intent.id. Tests pass a deterministic stub. */
  generateId: () => string;
  /** Optional correlationId passthrough (e.g. from a REPL session). */
  correlationId?: string;
}

// ── Target derivation ───────────────────────────────────────

function buildTarget(cmd: ShellCommand): SIRTarget | undefined {
  if (!cmd.objectId && !cmd.typePath) return undefined;
  const target: SIRTarget = {};
  if (cmd.objectId) target.objectId = cmd.objectId;
  if (cmd.typePath) target.typePath = cmd.typePath;
  return target;
}

// ── Taxonomy derivation ─────────────────────────────────────
//
// The shell doesn't carry rich taxonomy; we synthesise it so
// lowerSIR + downstream consumers have a valid triple. Real extensions
// that want richer routing should inspect Intent.target.typePath and
// rewrite taxonomy at a later stage (or produce Intents directly).

function buildTaxonomy(cmd: ShellCommand): TaxonomyCoordinates {
  const what = cmd.typePath ?? cmd.objectId ?? 'shell.unknown';
  return {
    what,
    how: `shell.${cmd.verb}`,
    why: 'shell-invocation',
  };
}

// ── shellCommandToIntent ────────────────────────────────────

const SHELL_SOURCE: IntentSource = 'shell';

/**
 * Resolve (category, action) for a shell verb, consulting the runtime
 * verb registry first. Extensions registering with a lexicon-aware
 * VerbRegistration get their declared TaggedCategory back; bare
 * registrations (`registerVerb(name, handler)`) look identical to the
 * jural-declaration default.
 *
 * When the verb isn't in the registry — built-in shell verbs the shell
 * owns directly (transition, new, stake, …) — fall back to the
 * hardcoded jural VERB_CATEGORY table below. Read-only verbs return
 * null.
 */
function resolveVerbMetadata(cmd: ShellCommand): {
  category: TaggedCategory;
  action: string;
} | null {
  const reg = getVerbRegistration(cmd.verb);
  if (reg) {
    if (!reg.mutation) return null;
    return { category: reg.category, action: reg.action };
  }
  const juralCat = VERB_CATEGORY[cmd.verb];
  if (juralCat === null) return null;
  return {
    category: { lexicon: 'jural', category: juralCat } as TaggedCategory,
    action: cmd.verb,
  };
}

/**
 * Map a parsed ShellCommand to an Intent. Returns null for read-only
 * verbs (inspect, list, …) — those should route through existing direct
 * handlers, not the mutation pipeline.
 */
export function shellCommandToIntent(
  cmd: ShellCommand,
  opts: AdapterOptions,
): Intent | null {
  const meta = resolveVerbMetadata(cmd);
  if (meta === null) return null;

  const { constraints, leftovers } = extractConstraints(cmd.flags);

  const intent: Intent = {
    id: opts.generateId() as IntentId,
    summary: formatSummary(cmd),
    category: meta.category,
    taxonomy: buildTaxonomy(cmd),
    action: meta.action,
    constraints,
    target: buildTarget(cmd),
    confidence: 1.0,
    source: SHELL_SOURCE,
    producerMeta: {
      rawArgs: cmd.rawArgs,
      ...(Object.keys(leftovers).length > 0 ? { flags: leftovers } : {}),
    },
  };

  if (opts.correlationId) {
    (intent as Intent).correlationId = opts.correlationId as Intent['correlationId'];
  }

  return intent;
}

function formatSummary(cmd: ShellCommand): string {
  const target = cmd.objectId ?? cmd.typePath ?? '';
  return target ? `${cmd.verb} ${target}` : cmd.verb;
}

```
