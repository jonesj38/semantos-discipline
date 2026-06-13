---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-contracts/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.821725+00:00
---

# core/plexus-contracts/src/index.ts

```ts
/**
 * @plexus/contracts — type definitions for the Plexus ecosystem.
 *
 * Local stand-in package until Dusk Inc ships the real @plexus/contracts.
 * Types only — zero runtime dependencies.
 */

export type {
  Brc52Cert,
  CertIdPreimage,
  CertificatePreimage,
  PlexusCert,
  CertRegistrationRequest,
  CertRegistrationResult,
  CertRegistrationErrorCode,
  Brc100Headers,
  SignedBundle,
} from './identity';
export { canonicalCertPreimage, computeCertId } from './identity';
export type { PlexusNode, PlexusEdge, EdgeRecoveryPolicy } from './graph';
export type { ChallengeSpec, ChallengeAnswer, RecoveryStatus, RecoverySession } from './recovery';
export {
  BRC100_HEADER_IDENTITY_KEY,
  BRC100_HEADER_NONCE,
  BRC100_HEADER_TIMESTAMP,
  BRC100_HEADER_SIGNATURE,
  BRC52_HEADER_CERTIFICATE,
} from './transport';
export {
  // Canonical 3-tier partition (re-exported from @semantos/protocol-types
  // namespace.ts — single source of truth per audit R-1).
  PLEXUS_RESERVED_MAX,
  EXTENDED_PLEXUS_MAX,
  OPERATOR_BASE,
  UINT32_MAX,
  isPlexusReserved,
  isExtendedPlexus,
  isOperatorSovereign,
  namespaceTier,
  isValidNamespaceFlag,
  type NamespaceTier,
  // Deprecated alias of OPERATOR_BASE, kept for back-compat.
  CLIENT_BASE,
  PlexusStandardFlags,
  ClientDomainFlags,
  SemantosDomainFlags,
} from './domain-flags';

```
