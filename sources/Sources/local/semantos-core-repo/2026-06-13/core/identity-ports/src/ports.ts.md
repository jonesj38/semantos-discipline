---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/identity-ports/src/ports.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.943924+00:00
---

# core/identity-ports/src/ports.ts

```ts
/**
 * The four port instances. Apps `import { identityPort, ... }` and call
 * `.bind(impl)` once during boot; downstream call sites use `.get()`.
 *
 * The instances themselves are typed by the interfaces in `./types.ts`; the
 * concrete bindings live in `./stub-binding.ts` (tests/demos) and
 * `./vendor-sdk-binding.ts` (production).
 *
 * Ports are package-scoped singletons (one shared instance across the whole
 * app process). This matches the cluster-1 pattern from the refactor session
 * (`broadcasterPort`, `walletPort`, `signerPort` etc.) — `bind()` once at
 * boot, `get()` everywhere, `unbind()` between test cases.
 */

import { port, type Port } from '@semantos/state';

import type {
  AttestationPort,
  CapabilityPort,
  EconomicPort,
  IdentityPort,
  RecoveryPort,
} from './types.js';

export const identityPort: Port<IdentityPort> = port<IdentityPort>('IdentityPort');
export const recoveryPort: Port<RecoveryPort> = port<RecoveryPort>('RecoveryPort');
export const attestationPort: Port<AttestationPort> = port<AttestationPort>('AttestationPort');
export const capabilityPort: Port<CapabilityPort> = port<CapabilityPort>('CapabilityPort');
export const economicPort: Port<EconomicPort> = port<EconomicPort>('EconomicPort');

/**
 * Convenience: bind all four ports to a single bundle. The stub and
 * vendor-sdk bindings each export a function returning this shape, so apps
 * can do:
 *
 *   bindAllIdentityPorts(stubIdentityBundle());
 *
 * or
 *
 *   bindAllIdentityPorts(vendorSdkBundle({ vendorSdk: new VendorSDK(...) }));
 */
export interface IdentityPortBundle {
  identity: IdentityPort;
  recovery: RecoveryPort;
  attestation: AttestationPort;
  capability: CapabilityPort;
  /** Optional — bindings that don't carry money may leave this unset. */
  economic?: EconomicPort;
}

export function bindAllIdentityPorts(bundle: IdentityPortBundle): void {
  identityPort.bind(bundle.identity);
  recoveryPort.bind(bundle.recovery);
  attestationPort.bind(bundle.attestation);
  capabilityPort.bind(bundle.capability);
  if (bundle.economic) economicPort.bind(bundle.economic);
}

export function unbindAllIdentityPorts(): void {
  identityPort.unbind();
  recoveryPort.unbind();
  attestationPort.unbind();
  capabilityPort.unbind();
  economicPort.unbind();
}

```
