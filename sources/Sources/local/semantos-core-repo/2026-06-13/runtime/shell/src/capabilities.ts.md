---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/capabilities.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.367053+00:00
---

# runtime/shell/src/capabilities.ts

```ts
/**
 * Capability mapping — maps shell verbs to Plexus domain flags.
 *
 * From PLEXUS-INTEGRATION-MAP.md:
 *   0x00010001 = View/Read
 *   0x00010002 = Create
 *   0x00010003 = Edit/Patch
 *   0x00010004 = Delete/Revoke
 *   0x00010005 = Publish
 *   0x00010006 = Govern (Vote)
 *   0x00010007 = Govern (Propose)
 *   0x00010008 = Stake
 *   0x00010009 = Transfer
 *   0x0001000A = Admin
 *
 * Phase 19.5: D19.5.3
 */

/** Maps mutation verb → required Plexus domain flag. */
export const CAPABILITY_MAP: Record<string, number> = {
  new:         0x00010002,  // Create
  patch:       0x00010003,  // Edit/Patch
  publish:     0x00010005,  // Publish
  revoke:      0x00010004,  // Delete/Revoke
  stake:       0x00010008,  // Stake
  vote:        0x00010006,  // Govern (Vote)
  dispute:     0x00010007,  // Govern (Propose)
  transfer:    0x00010009,  // Transfer
  settle:      0x00010009,  // Transfer (settlement is a value transfer)
  cdm:         0x00010002,  // Create (CDM operations)
  'host.exec': 0x0001000b,  // Phase 38 — Host Execute (HOST_EXEC)
};

/** Human-readable name for a domain flag. */
const FLAG_NAMES: Record<number, string> = {
  0x00010001: 'View/Read',
  0x00010002: 'Create',
  0x00010003: 'Edit/Patch',
  0x00010004: 'Delete/Revoke',
  0x00010005: 'Publish',
  0x00010006: 'Govern (Vote)',
  0x00010007: 'Govern (Propose)',
  0x00010008: 'Stake',
  0x00010009: 'Transfer',
  0x0001000A: 'Admin',
  0x0001000B: 'Host Execute',
};

/** Also support legacy loom capability numbers (1-10). */
const LEGACY_NAMES: Record<number, string> = {
  1: 'View/Read',
  2: 'Create',
  3: 'Edit/Patch',
  4: 'Delete/Revoke',
  5: 'Publish',
  6: 'Govern (Vote)',
  7: 'Govern (Propose)',
  8: 'Stake',
  9: 'Transfer',
  10: 'Admin',
};

/** Get the required domain flag for a mutation verb, or null for read-only verbs. */
export function getRequiredCapability(verb: string): number | null {
  return CAPABILITY_MAP[verb] ?? null;
}

/** Get human-readable name for a capability number or domain flag. */
export function getCapabilityName(capOrFlag: number): string {
  return FLAG_NAMES[capOrFlag] ?? LEGACY_NAMES[capOrFlag] ?? `Unknown(0x${capOrFlag.toString(16)})`;
}

/** Set of verbs that require capability checks (all mutation verbs). */
export const MUTATION_VERBS = new Set(Object.keys(CAPABILITY_MAP));

```
