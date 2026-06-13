---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/identity-ports/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.942788+00:00
---

# core/identity-ports/src/index.ts

```ts
/**
 * @semantos/identity-ports — application-facing port surface for the
 * Plexus identity, recovery, attestation, and capability domains.
 *
 * Apps import the four port instances from here, call `.bind(impl)` once
 * during boot (typically with a stub binding in tests/demos and a
 * vendor-sdk binding in production), and call `.get()` from downstream
 * code. See the `README.md` and the JSDoc on `./types.ts` for the
 * Plexus-spec mapping.
 */

export type {
  IdentityPort,
  RecoveryPort,
  AttestationPort,
  CapabilityPort,
  CapabilityType,
  CapabilityCheck,
  EconomicPort,
  SignSpendInput,
  SignedSpend,
  PaymentVerification,
  IdentityRegistration,
  IdentityResolution,
  ChildDerivation,
  ChildNodeRef,
  EdgeCreation,
  SubtreeQuery,
  RecoveryInitiation,
  RecoveryVerdict,
  SPVAttestation,
} from './types.js';

export {
  identityPort,
  recoveryPort,
  attestationPort,
  capabilityPort,
  economicPort,
  bindAllIdentityPorts,
  unbindAllIdentityPorts,
  type IdentityPortBundle,
} from './ports.js';

```
