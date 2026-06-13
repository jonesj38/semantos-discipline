---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/re-desk-stub/src/state-machines/kernel-gate.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.540150+00:00
---

# packages/re-desk-stub/src/state-machines/kernel-gate.ts

```ts
/**
 * D-O11 phase O11a — kernel-gate verifier stub specialised for
 * re-desk-stub capabilities.
 *
 * Re-uses the `Result` / `ConsumedCellSet` / `PresentedCap` /
 * `KernelGateFailure` shapes from `@semantos/oddjobz` so the K1/K2/K4
 * surface is identical to the oddjobz Job FSM. The only re-desk-
 * specific piece is the cap-name → domain-flag lookup, which keys
 * against this extension's `capabilityByName` registry.
 *
 * The K3 (hat-isolation) story re-uses
 * `@semantos/oddjobz/conversation/hat-scoping` directly — context-tag
 * is a substrate-level concept independent of which extension owns the
 * cap. The dispatch-envelope handler (D-O11 phase O11b) calls
 * `assertHatScopedCap` regardless of payload type.
 */

import {
  ok,
  err,
  presentedFlag,
  type ConsumedCellSet,
  type KernelGateFailure,
  type PresentedCap,
  type Result,
  type SigningPrincipal,
} from '@semantos/oddjobz';

import {
  capabilityByName as reDeskCapabilityByName,
  type ReDeskCapName,
} from '../capabilities.js';

export {
  type ConsumedCellSet,
  type KernelGateFailure,
  type PresentedCap,
  type Result,
  type SigningPrincipal,
};

export {
  ok,
  err,
  presentedFlag,
};

/**
 * Specialised `OP_CHECKDOMAINFLAG` analogue for re-desk-stub caps.
 * Mirror of `@semantos/oddjobz`'s `checkDomainFlag` but keys on the
 * re-desk capability registry instead of the oddjobz one.
 */
export function checkDomainFlag(
  capName: ReDeskCapName,
  presented: PresentedCap | null,
): Result<true, KernelGateFailure> {
  const cap = reDeskCapabilityByName[capName];
  if (cap === undefined) {
    return err({
      kind: 'wrong_cap',
      message: `unknown re-desk cap name: ${capName}`,
    });
  }
  if (presented === null) {
    return err({
      kind: 'cap_required',
      message: `transition requires ${capName} but no cap was presented`,
    });
  }
  const flag = presentedFlag(presented);
  if ((flag >>> 0) !== (cap.domainFlag >>> 0)) {
    return err({
      kind: 'wrong_cap',
      message:
        `presented domain flag 0x${flag.toString(16).padStart(8, '0')} ` +
        `≠ expected 0x${cap.domainFlag.toString(16).padStart(8, '0')} for ${capName}`,
      presentedDomainFlag: flag,
    });
  }
  return ok(true);
}

/** K1 substrate stub — unchanged from the oddjobz analogue. */
export function assertLinear(
  consumed: ConsumedCellSet,
  cellId: string,
): Result<true, KernelGateFailure> {
  if (consumed.has(cellId)) {
    return err({
      kind: 'cell_already_consumed',
      message: `cell ${cellId} already consumed in a prior transition`,
      consumedCellId: cellId,
    });
  }
  return ok(true);
}

```
