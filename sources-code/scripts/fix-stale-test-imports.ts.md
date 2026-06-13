---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/fix-stale-test-imports.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.315498+00:00
---

# scripts/fix-stale-test-imports.ts

```ts
#!/usr/bin/env bun
/**
 * Codemod: rewrite stale import specifiers in tests/gates/ left over from the
 * packages/ → core|runtime|extensions|apps restructure.
 *
 * Walks every .ts file under tests/gates/, scans import / require / dynamic-
 * import / string-literal path references, and applies an ordered list of
 * prefix rewrites. Each rewrite is verified: the target file must exist on
 * disk before the substitution is committed. If the target is missing, the
 * original specifier is left alone and the mismatch is reported.
 *
 * Run with `--dry` to preview without writing. Omit to apply.
 *
 *   bun scripts/fix-stale-test-imports.ts --dry
 *   bun scripts/fix-stale-test-imports.ts
 */

import { readdirSync, readFileSync, writeFileSync, existsSync, statSync } from 'node:fs';
import { join, resolve, dirname, extname } from 'node:path';

const REPO_ROOT = resolve(__dirname, '..');
const TESTS_DIR = join(REPO_ROOT, 'tests/gates');
const DRY = process.argv.includes('--dry');

/**
 * Ordered list of prefix rewrites. Longest / most-specific prefixes MUST come
 * first so that `../../packages/protocol-types/` isn't partially matched by a
 * later `packages/protocol-types/` rule.
 *
 * The `from` prefix is matched verbatim against the import specifier / path
 * literal; if it matches and the rewritten target exists on disk, the
 * substitution is applied.
 */
interface Rule {
  from: string;
  to: string;
}

// Ordered, most-specific first.
const RULES: Rule[] = [
  // `packages/loom/` split: headless services → runtime/services, UI → apps/loom-react.
  // UI rules must come before the general loom→runtime/services rule.
  { from: '../../packages/loom/src/panels/', to: '../../apps/loom-react/src/panels/' },
  { from: '../../packages/loom/src/helm/', to: '../../apps/loom-react/src/helm/' },
  { from: '../../packages/loom/src/LoomApp', to: '../../apps/loom-react/src/LoomApp' },
  { from: '../../packages/workbench/src/panels/', to: '../../apps/loom-react/src/panels/' },
  { from: '../../packages/workbench/src/helm/', to: '../../apps/loom-react/src/helm/' },
  { from: 'packages/loom/src/panels/', to: 'apps/loom-react/src/panels/' },
  { from: 'packages/loom/src/helm/', to: 'apps/loom-react/src/helm/' },
  { from: 'packages/loom/src/LoomApp', to: 'apps/loom-react/src/LoomApp' },
  { from: 'packages/workbench/src/panels/', to: 'apps/loom-react/src/panels/' },
  { from: 'packages/workbench/src/helm/', to: 'apps/loom-react/src/helm/' },

  // `../../packages/*` — absolute-from-repo-root style from old packages/__tests__/
  { from: '../../packages/loom/src/', to: '../../runtime/services/src/' },
  { from: '../../packages/workbench/src/', to: '../../runtime/services/src/' },
  { from: '../../packages/protocol-types/', to: '../../core/protocol-types/' },
  { from: '../../packages/cell-engine/', to: '../../core/cell-engine/' },
  { from: '../../packages/shell/', to: '../../runtime/shell/' },
  { from: '../../packages/cdm/', to: '../../packages/cdm/' },
  { from: '../../packages/extraction/', to: '../../packages/extraction/' },
  { from: '../../packages/scada/', to: '../../packages/scada/' },
  { from: '../../packages/policy-runtime/', to: '../../packages/policy-runtime/' },
  { from: '../../packages/games/', to: '../../packages/games/' },
  { from: '../../packages/game-sdk/', to: '../../packages/game-sdk/' },

  // `../*` — relative from old packages/__tests__/ sibling layout.
  { from: '../workbench/src/', to: '../../runtime/services/src/' },
  { from: '../protocol-types/', to: '../../core/protocol-types/' },
  { from: '../cell-engine/', to: '../../core/cell-engine/' },
  { from: '../shell/', to: '../../runtime/shell/' },
  { from: '../cdm/', to: '../../packages/cdm/' },
  { from: '../extraction/', to: '../../packages/extraction/' },
  { from: '../scada/', to: '../../packages/scada/' },
  { from: '../policy-runtime/', to: '../../packages/policy-runtime/' },
  { from: '../games/', to: '../../packages/games/' },
  { from: '../game-sdk/', to: '../../packages/game-sdk/' },
  { from: '../cell-ops/', to: '../../core/cell-ops/' },
  { from: '../metering/', to: '../../packages/metering/' },
  { from: '../mud/', to: '../../apps/mud/' },
  { from: '../node/', to: '../../runtime/node/' },
  { from: '../settlement/', to: '../../apps/settlement/' },

  // Bare `packages/*` — appears inside string literals built against `ROOT`
  // (e.g. join(import.meta.dir, '../..', 'packages/cdm/src/lifecycle.ts')).
  { from: 'packages/loom/src/', to: 'runtime/services/src/' },
  { from: 'packages/workbench/src/', to: 'runtime/services/src/' },
  { from: 'packages/protocol-types/', to: 'core/protocol-types/' },
  { from: 'packages/cell-engine/', to: 'core/cell-engine/' },
  { from: 'packages/shell/', to: 'runtime/shell/' },
  { from: 'packages/cdm/', to: 'packages/cdm/' },
  { from: 'packages/extraction/', to: 'packages/extraction/' },
  { from: 'packages/scada/', to: 'packages/scada/' },
  { from: 'packages/policy-runtime/', to: 'packages/policy-runtime/' },
  { from: 'packages/games/', to: 'packages/games/' },
  { from: 'packages/game-sdk/', to: 'packages/game-sdk/' },
];

/**
 * Match any string literal in the source. We rewrite inside:
 *   - import … from 'X' / "X"
 *   - import('X')
 *   - require('X')
 *   - plain string literals 'packages/…' used to build fs paths
 *
 * Using a regex over all single/double quoted literals is simpler and safer
 * than parsing TS — the literal prefixes are distinctive enough that we
 * won't collide with unrelated text ("packages/" on its own is a common
 * prefix, but only in fs paths we actually do want to rewrite).
 */
// Match single/double-quoted string literals. Body disallows newlines so we
// never run past a stray apostrophe (e.g. "foo's bar") into the next line —
// that desync was eating 80% of matches on larger files.
const STRING_LITERAL = /(['"])((?:\\.|[^\\\n])*?)\1/g;

interface Change {
  file: string;
  before: string;
  after: string;
  verified: boolean;
  reason?: string;
}

function resolveRelative(fromFile: string, spec: string): string | null {
  if (!spec.startsWith('.')) {
    // Treat plain `packages/...` / `core/...` / etc. as repo-root-relative.
    return join(REPO_ROOT, spec);
  }
  return resolve(dirname(fromFile), spec);
}

/** Returns true if the rewritten specifier resolves to a real file. */
function targetExists(fromFile: string, newSpec: string): boolean {
  const abs = resolveRelative(fromFile, newSpec);
  if (!abs) return false;
  // Accept exact match, .ts / .tsx suffix, or index.ts inside a dir.
  if (existsSync(abs) && statSync(abs).isFile()) return true;
  for (const ext of ['.ts', '.tsx', '.d.ts', '.json']) {
    if (existsSync(abs + ext)) return true;
  }
  if (existsSync(abs) && statSync(abs).isDirectory()) {
    for (const ext of ['.ts', '.tsx', '.d.ts']) {
      if (existsSync(join(abs, 'index' + ext))) return true;
    }
    // Directory used as a join() base — accept if the directory itself exists
    // even without an index file (e.g. `join(ROOT, "packages/cell-engine")`).
    return true;
  }
  return false;
}

function rewriteSpec(spec: string): { next: string; rule: Rule } | null {
  for (const rule of RULES) {
    if (spec.startsWith(rule.from)) {
      return { next: rule.to + spec.slice(rule.from.length), rule };
    }
    // Exact match without the trailing slash — covers bare base paths like
    // `packages/cell-engine` used as a join() root.
    const fromNoSlash = rule.from.replace(/\/$/, '');
    const toNoSlash = rule.to.replace(/\/$/, '');
    if (spec === fromNoSlash) {
      return { next: toNoSlash, rule };
    }
  }
  return null;
}

function processFile(path: string): Change[] {
  const src = readFileSync(path, 'utf8');
  const changes: Change[] = [];
  const rewritten = src.replace(STRING_LITERAL, (match, quote, body) => {
    const hit = rewriteSpec(body);
    if (!hit) return match;
    const verified = targetExists(path, hit.next);
    changes.push({
      file: path,
      before: body,
      after: hit.next,
      verified,
      reason: verified ? undefined : 'target does not exist on disk',
    });
    if (!verified) return match; // leave original alone
    return `${quote}${hit.next}${quote}`;
  });

  if (!DRY && rewritten !== src) {
    writeFileSync(path, rewritten);
  }
  return changes;
}

function walk(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(p));
    else if (entry.isFile() && (extname(p) === '.ts' || extname(p) === '.tsx')) out.push(p);
  }
  return out;
}

function main() {
  const files = walk(TESTS_DIR);
  const allChanges: Change[] = [];
  let filesTouched = 0;

  for (const f of files) {
    const changes = processFile(f);
    if (changes.length > 0) {
      filesTouched++;
      allChanges.push(...changes);
    }
  }

  const applied = allChanges.filter(c => c.verified);
  const skipped = allChanges.filter(c => !c.verified);

  console.log(`${DRY ? '[DRY]' : '[APPLIED]'} scanned ${files.length} files, touched ${filesTouched}`);
  console.log(`  applied: ${applied.length} rewrites`);
  console.log(`  skipped: ${skipped.length} (target missing)`);

  if (applied.length > 0) {
    console.log('\n--- applied ---');
    const byBefore = new Map<string, number>();
    for (const c of applied) byBefore.set(c.before, (byBefore.get(c.before) ?? 0) + 1);
    for (const [spec, count] of [...byBefore.entries()].sort((a, b) => b[1] - a[1])) {
      const mapped = rewriteSpec(spec)?.next ?? '?';
      console.log(`  ${count.toString().padStart(3)}  ${spec}  →  ${mapped}`);
    }
  }

  if (skipped.length > 0) {
    console.log('\n--- skipped (manual review) ---');
    for (const c of skipped) {
      console.log(`  ${c.file.replace(REPO_ROOT + '/', '')}: '${c.before}' → '${c.after}' (${c.reason})`);
    }
  }
}

main();

```
