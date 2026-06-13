---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/re-desk-stub/src/capabilities.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.536731+00:00
---

# packages/re-desk-stub/src/capabilities.ts

```ts
/**
 * D-O11 phase O11a — re-desk-stub capability mints.
 *
 * Single capability: `cap.re-desk.dispatch`. Gates the
 * `MaintenanceRequest` `draft → dispatched` transition (the moment a
 * dispatch envelope is created). Held by the property-management
 * operator's hat at first boot.
 *
 * Domain-flag namespace: per the canonical low-bits page allocation
 * documented in `extensions/oddjobz/src/capabilities.ts`, oddjobz claims
 * `0x000101xx`. This extension claims the next page (`0x000102xx`) and
 * mints `cap.re-desk.dispatch` at `0x00010201`. Out of band of every
 * other shipping extension's page; auditable by raw flag value.
 *
 * The module is deliberately thin; the stub's purpose is structural,
 * not feature-rich.
 *
 * Cell-mint shape: re-uses the canonical 1024-byte oddjobz cap-cell
 * layout — same magic, linearity (LINEAR), version, type-hash, owner-id
 * scheme. The kernel-gate doesn't care which extension minted the cap;
 * `OP_CHECKDOMAINFLAG` reads only the 4-byte flag at header offset 24.
 * This is what makes the cross-vertical dispatch composition work
 * without any kernel-side schema awareness.
 */

import { mintCapabilityCell } from '@semantos/oddjobz';
import type { CapHolder } from '@semantos/oddjobz';

export const RE_DESK_CAP_NAMES = ['cap.re-desk.dispatch'] as const;
export type ReDeskCapName = (typeof RE_DESK_CAP_NAMES)[number];

/**
 * Capability declaration shape — structurally identical to
 * `OddjobzCapability` but with its own name discriminant. The kernel-
 * gate machinery in `@semantos/oddjobz` treats both shapes uniformly
 * because the gating logic keys on `domainFlag` only.
 */
export interface ReDeskCapability {
  readonly name: ReDeskCapName;
  readonly domainFlag: number;
  readonly description: string;
  readonly roleInFsm: string;
  readonly gates: readonly string[];
  readonly holder: CapHolder;
}

export const capDispatchReDesk: ReDeskCapability = Object.freeze({
  name: 'cap.re-desk.dispatch',
  domainFlag: 0x0001_0201,
  description:
    'Authorises creating a dispatch envelope from a MaintenanceRequest. ' +
    'Held by the property-management operator root cert; gates the ' +
    "MaintenanceRequest FSM 'draft → dispatched' transition.",
  roleInFsm:
    "Spent on the MaintenanceRequest FSM 'draft → dispatched' " +
    'transition; mints a `dispatch.envelope.v1` cell carrying the ' +
    'MaintenanceRequest payload signed by the PM hat.',
  gates: ['draft → dispatched'],
  holder: 'operator-root',
});

export const RE_DESK_CAPABILITIES: readonly ReDeskCapability[] = Object.freeze([
  capDispatchReDesk,
]);

export const capabilityByName: Readonly<Record<ReDeskCapName, ReDeskCapability>> =
  Object.freeze(
    Object.fromEntries(
      RE_DESK_CAPABILITIES.map((c) => [c.name, c]),
    ) as Record<ReDeskCapName, ReDeskCapability>,
  );

/**
 * Mint the cap UTXO under a contextTag + ownerId. Same byte layout as
 * `mintCapabilityCell` from `@semantos/oddjobz` — the cap-presentation
 * machinery is shared. We adapt the type-side by aliasing the cap as
 * `OddjobzCapability` for the call (the byte layout is identical).
 */
export function mintReDeskCapability(
  cap: ReDeskCapability,
  contextTag: number,
  ownerId: Uint8Array,
): Uint8Array {
  // The mintCapabilityCell function only reads `name`, `domainFlag`,
  // and `holder` from the cap declaration. Re-deck's cap shape is
  // structurally compatible; we cast through `unknown` to satisfy the
  // imported function's typed parameter without losing safety on the
  // values themselves (validated by the cap-cell decoder on the
  // receive side).
  return mintCapabilityCell(
    cap as unknown as Parameters<typeof mintCapabilityCell>[0],
    contextTag,
    ownerId,
  );
}

```
