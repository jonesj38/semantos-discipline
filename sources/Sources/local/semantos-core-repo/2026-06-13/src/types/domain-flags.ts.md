---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/types/domain-flags.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.397807+00:00
---

# src/types/domain-flags.ts

```ts
/**
 * Domain Flags: Functional namespace isolation in Plexus
 *
 * Domain flags are uint32 values that uniquely identify key derivation paths
 * and protocol contexts. They organize the Plexus functional space into
 * three tiers: well-known (global), extended (standard), and sovereign (client).
 */

/**
 * DomainFlag: A uint32 semantic identifier for a key derivation namespace.
 * Plain number type — no branding, just semantics.
 */
export type DomainFlag = number;

/**
 * PLEXUS_WELL_KNOWN: Range [0x00000001, 0x000000FF]
 * Global, immutable flag identifiers defined by Plexus protocol.
 */
export const PLEXUS_WELL_KNOWN_MIN = 0x00000001;
export const PLEXUS_WELL_KNOWN_MAX = 0x000000ff;

/**
 * EXTENDED_STANDARD: Range [0x00000100, 0x0000FFFF]
 * Standard extensions and application-specific flags reserved by Dusk.
 */
export const EXTENDED_STANDARD_MIN = 0x00000100;
export const EXTENDED_STANDARD_MAX = 0x0000ffff;

/**
 * CLIENT_SOVEREIGN: Range [0x00010000, 0xFFFFFFFF]
 * Freely available for client application use.
 */
export const CLIENT_SOVEREIGN_MIN = 0x00010000;
export const CLIENT_SOVEREIGN_MAX = 0xffffffff;

/**
 * EDGE_CREATION: 0x01
 * Domain for deriving keys used in identity graph edge creation.
 */
export const EDGE_CREATION: DomainFlag = 0x01;

/**
 * SIGNING: 0x02
 * Domain for general-purpose ECDSA signing keys.
 */
export const SIGNING: DomainFlag = 0x02;

/**
 * ENCRYPTION: 0x03
 * Domain for ECDH encryption keys.
 */
export const ENCRYPTION: DomainFlag = 0x03;

/**
 * MESSAGING: 0x04
 * Domain for keys used in secure messaging protocols.
 */
export const MESSAGING: DomainFlag = 0x04;

/**
 * ATTESTATION: 0x05
 * Domain for keys used in proof-of-custody and attestation protocols.
 */
export const ATTESTATION: DomainFlag = 0x05;

/**
 * CHILD_CREATION: 0x06
 * Domain for deriving keys used in child identity issuance.
 */
export const CHILD_CREATION: DomainFlag = 0x06;

/**
 * PERMISSION_GRANT: 0x07
 * Domain for keys used in capability token issuance.
 */
export const PERMISSION_GRANT: DomainFlag = 0x07;

/**
 * DATA_SOVEREIGNTY: 0x08
 * Domain for keys used in data ownership and recovery protocols.
 */
export const DATA_SOVEREIGNTY: DomainFlag = 0x08;

/**
 * SCHEMA_SIGNING: 0x09
 * Domain for keys used in schema definition and evolution.
 */
export const SCHEMA_SIGNING: DomainFlag = 0x09;

/**
 * METERING: 0x0A
 * Domain for keys used in metered flow protocol channels.
 */
export const METERING: DomainFlag = 0x0a;

/**
 * Classify a domain flag by its tier.
 *
 * @param flag The domain flag to classify
 * @returns The tier: 'well-known', 'extended', or 'sovereign'
 */
export function classifyFlag(flag: DomainFlag): 'well-known' | 'extended' | 'sovereign' {
  if (flag >= PLEXUS_WELL_KNOWN_MIN && flag <= PLEXUS_WELL_KNOWN_MAX) {
    return 'well-known';
  }
  if (flag >= EXTENDED_STANDARD_MIN && flag <= EXTENDED_STANDARD_MAX) {
    return 'extended';
  }
  if (flag >= CLIENT_SOVEREIGN_MIN && flag <= CLIENT_SOVEREIGN_MAX) {
    return 'sovereign';
  }
  // Flag is outside all ranges (e.g., 0x00000000)
  return 'well-known'; // Default fallback for classification purposes
}

/**
 * Check if a domain flag is reserved (invalid).
 *
 * 0x00000000 is explicitly reserved and cannot be used.
 *
 * @param flag The domain flag to check
 * @returns true if the flag is reserved/invalid
 */
export function isReserved(flag: DomainFlag): boolean {
  return flag === 0x00000000;
}

/**
 * Convert a domain flag to BRC-43 protocolID format.
 *
 * Produces a two-element array compatible with @bsv/sdk's protocol ID system:
 * [securityLevel, `plexus-domain-${hex}`]
 *
 * @param flag The domain flag
 * @returns A tuple [securityLevel, protocolIdString] for BRC-43
 */
export function toProtocolId(flag: DomainFlag): [number, string] {
  // Security level: use 1 (full verification) for well-known, 0 (custom) for others
  const securityLevel = flag >= PLEXUS_WELL_KNOWN_MIN && flag <= PLEXUS_WELL_KNOWN_MAX ? 1 : 0;
  return [securityLevel, `plexus-domain-${flag.toString(16)}`];
}

```
