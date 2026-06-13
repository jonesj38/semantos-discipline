---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/rtc-substrate-one-way-dep.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.564677+00:00
---

# tests/gates/rtc-substrate-one-way-dep.test.ts

```ts
/**
 * RTC substrate one-way-dep gate — RTC matrix row S7 axis I (D-RTC-S7-I).
 *
 * The structural guarantee that makes `rtc/` substrate, not a cartridge:
 *
 *   cartridges/* MAY import rtc.   rtc/ SHALL NOT import a cartridge.
 *
 * Telehealth, betterment check-ins, oddjobz walk-throughs, and a jam-room
 * video layer are all *different cartridges* that need the *same* calling
 * primitive. The shell owns the media stack (how); cartridges express the
 * typed surface (what). A reverse edge — rtc/ reaching into a cartridge —
 * would collapse that separation, so this gate rejects it mechanically.
 *
 * This mirrors the substrate one-way-dep gate
 * (tests/gates/substrate-one-way-dep.test.ts) and the XMPP substrate gate
 * pattern. rtc/ lives in a runtime package, so — unlike a core/ substrate —
 * it MAY import other runtime substrate (the merged XMPP node) and core/
 * protocol-types. Only cartridge reverse-deps are forbidden.
 *
 * Cross-reference: docs/prd/RTC-ROADMAP.md §4 (the structural guarantee),
 * docs/canon/rtc-matrix.yml row S7.
 */

import { describe, test, expect } from 'bun:test';
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { resolve, join, relative } from 'node:path';

const REPO_ROOT = resolve(__dirname, '..', '..');
const RTC_ROOT = join(REPO_ROOT, 'runtime', 'session-protocol', 'src', 'rtc');

/** Cartridge package aliases rtc/ must never import (from the L26 deny-list). */
const FORBIDDEN_CARTRIDGE_ALIASES = [
  '@semantos/betterment',
  '@semantos/bsv-anchor-bundle',
  '@semantos/oddjobz',
  '@semantos/scg',
  '@semantos/tessera',
  '@semantos/wallet-browser',
  '@semantos/world-app-chess-game',
  '@semantos/world-app-jam-room',
];

const EXCLUDED_SUFFIXES = ['.test.ts', '.test.tsx', '.spec.ts', '.d.ts'];

function tsSourceFiles(dir: string): string[] {
  const out: string[] = [];
  if (!existsSync(dir)) return out;
  for (const ent of readdirSync(dir)) {
    if (ent === '__tests__' || ent === 'node_modules') continue;
    const p = join(dir, ent);
    if (statSync(p).isDirectory()) out.push(...tsSourceFiles(p));
    else if (/\.tsx?$/.test(ent) && !EXCLUDED_SUFFIXES.some((s) => ent.endsWith(s))) out.push(p);
  }
  return out;
}

function importSpecifiers(src: string): string[] {
  const specs: string[] = [];
  const re = /(?:import|export)\s[^;]*?\sfrom\s+["']([^"']+)["']/g;
  const bare = /\bimport\s+["']([^"']+)["']/g;
  const dyn = /\bimport\s*\(\s*["']([^"']+)["']\s*\)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) specs.push(m[1]!);
  while ((m = bare.exec(src)) !== null) specs.push(m[1]!);
  while ((m = dyn.exec(src)) !== null) specs.push(m[1]!);
  return specs;
}

function cartridgeReverseDeps(file: string): string[] {
  const src = readFileSync(file, 'utf8');
  const hits: string[] = [];
  for (const spec of importSpecifiers(src)) {
    if (spec.startsWith('.')) {
      const rel = relative(REPO_ROOT, resolve(file, '..', spec));
      if (rel.startsWith('cartridges/') || rel === 'cartridges') {
        hits.push(`${relative(REPO_ROOT, file)} → ${spec} (resolves into cartridges/)`);
      }
      continue;
    }
    if (spec.startsWith('@semantos/')) {
      const head = spec.split('/').slice(0, 2).join('/');
      if (FORBIDDEN_CARTRIDGE_ALIASES.includes(head)) {
        hits.push(`${relative(REPO_ROOT, file)} → ${spec} (cartridge package)`);
      }
      continue;
    }
    if (spec.startsWith('cartridges/')) {
      hits.push(`${relative(REPO_ROOT, file)} → ${spec}`);
    }
  }
  return hits;
}

describe('D-RTC-S7-I — rtc/ substrate one-way-dep gate', () => {
  test('rtc/ has source to check', () => {
    expect(tsSourceFiles(RTC_ROOT).length).toBeGreaterThan(0);
  });

  test('no rtc/ source imports a cartridge', () => {
    const violations: string[] = [];
    for (const f of tsSourceFiles(RTC_ROOT)) violations.push(...cartridgeReverseDeps(f));
    expect(violations).toEqual([]);
  });
});

```
