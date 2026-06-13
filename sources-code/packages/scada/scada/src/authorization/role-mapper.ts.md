---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/role-mapper.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.472200+00:00
---

# packages/scada/scada/src/authorization/role-mapper.ts

```ts
/**
 * Role mapper — pure: operator role → required capability set, plus the
 * supervisor / dual-auth role predicates the orchestrator needs.
 *
 * Re-exports `ROLE_CAPABILITIES` (defined in `../types`) at the new
 * authorization-module surface so callers don't have to reach across
 * directories. Adds the small predicate `isSupervisorRole` that the
 * legacy `shiftHandover` flow used inline.
 */

import { ROLE_CAPABILITIES } from '../types';
import type { OperatorRole } from '../types';

/** Capability numbers entitled by a role (delegated to the canonical map). */
export function capabilitiesForRole(role: OperatorRole): readonly number[] {
  return ROLE_CAPABILITIES[role];
}

/**
 * Returns true if the role is allowed to authorize a shift handover.
 * Mirrors the predicate hard-coded inside the legacy `shiftHandover`
 * branch: shift-supervisor, plant-manager, safety-officer.
 */
export function isSupervisorRole(role: OperatorRole): boolean {
  return (
    role === 'shift-supervisor' ||
    role === 'plant-manager' ||
    role === 'safety-officer'
  );
}

/** Re-export so the authorization sub-module is self-contained. */
export { ROLE_CAPABILITIES };
export type { OperatorRole };

```
