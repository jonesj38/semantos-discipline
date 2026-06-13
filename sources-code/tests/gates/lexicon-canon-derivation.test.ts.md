---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/lexicon-canon-derivation.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.579219+00:00
---

# tests/gates/lexicon-canon-derivation.test.ts

```ts
/**
 * CC0b — lexicon-canon derivation gate (Wave Canonical-Cartridge).
 *
 * Ref: docs/design/CANONICAL-CARTRIDGE-MODEL.md C2; commission CC0b;
 * Todd 2026-05-17 decision: "manifest-as-index; Lean/TS sources stay
 * truth — canon becomes a render, not a parallel truth."
 *
 * `docs/canon/lexicons.yml` must NOT be a parallel source of truth.
 * This gate proves its *mechanical* content (each lexicon's category
 * set) is a faithful projection of the structured TS lexicon source
 * `core/semantos-sir/src/lexicons.ts` `ALL_LEXICONS` (which carries
 * the Lean-mirrored proven vocabulary). If the canon yml drifts from
 * the TS source for any declared lexicon, CI fails — so the yml is a
 * derived render, the TS/Lean source stays authoritative. Editorial
 * fields (status, prose `description`) are intentionally out of scope:
 * they are authored, not derivable, and the gate does not police them.
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';
import { ALL_LEXICONS } from '../../core/semantos-sir/src/lexicons';

const REPO = join(import.meta.dir, '..', '..');

/** Minimal parse of lexicons.yml: id → its `categories:` list (the
 *  only mechanical field this gate polices). The file's entry shape is
 *  fixed (`  - id: X` … `    categories:` … `      - cat`). */
function parseLexiconsYml(src: string): Map<string, string[]> {
  const out = new Map<string, string[]>();
  const lines = src.split('\n');
  let id: string | null = null;
  let inCats = false;
  let cats: string[] = [];
  const flush = () => {
    if (id) out.set(id, cats);
    id = null;
    cats = [];
    inCats = false;
  };
  for (const line of lines) {
    const idM = line.match(/^\s*-\s+id:\s*(\S+)\s*$/);
    if (idM) {
      flush();
      id = idM[1];
      continue;
    }
    if (id && /^\s{4}categories:\s*$/.test(line)) {
      inCats = true;
      continue;
    }
    if (inCats) {
      const c = line.match(/^\s{6}-\s+(\S+)\s*$/);
      if (c) {
        cats.push(c[1]);
        continue;
      }
      // any non-list line at/under the entry ends the categories block
      if (line.trim() !== '' && !/^\s{6}-\s+/.test(line)) inCats = false;
    }
  }
  flush();
  return out;
}

describe('CC0b — lexicons.yml is a render of the TS lexicon source (no parallel truth)', () => {
  const yml = parseLexiconsYml(
    readFileSync(join(REPO, 'docs/canon/lexicons.yml'), 'utf-8'),
  );
  // The TS Lexicon keys its identity on `name` (e.g. TradesLexicon
  // = { name: 'trades', categories: [...] }); the yml `id` matches it.
  const byId = new Map(
    ALL_LEXICONS.map((l) => [(l as { name: string }).name, l]),
  );

  test('lexicons.yml declares at least one entry (sanity)', () => {
    expect(yml.size).toBeGreaterThan(0);
  });

  test('every yml lexicon resolves to a TS lexicon (yml cannot invent lexicons)', () => {
    for (const id of yml.keys()) {
      expect(byId.has(id)).toBe(true);
    }
  });

  test('each yml lexicon category set === the TS source category set (no drift)', () => {
    for (const [id, ymlCats] of yml) {
      const ts = byId.get(id);
      if (!ts) continue; // covered by the resolve test
      const tsCats = [...(ts.categories as readonly string[])].sort();
      expect([...ymlCats].sort()).toEqual(tsCats);
    }
  });
});

```
