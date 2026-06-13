---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-piggybank/src/domain.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.718911+00:00
---

# archive/apps-piggybank/src/domain.ts

```ts
/**
 * Piggy Bank Domain Flags
 *
 * Extends the Plexus domain flag system with piggybank-specific namespaces.
 * These live in the CLIENT_SOVEREIGN range (0x00010000+) so they don't
 * collide with well-known or extended standard flags.
 */

import type { DomainFlag } from '@semantos/core/types/domain-flags.js';

/**
 * PIGGYBANK: 0x00010001
 * Root domain for all piggy bank key derivation.
 * Parent keys for device identity, chore signing, payment receipt.
 */
export const PIGGYBANK: DomainFlag = 0x00010001;

/**
 * CHORE_SIGNING: 0x00010002
 * Domain for keys used to sign chore claims.
 * Kids use this to prove they completed a task.
 */
export const CHORE_SIGNING: DomainFlag = 0x00010002;

/**
 * PAYMENT_RECEIPT: 0x00010003
 * Domain for keys used to receive BSV payments.
 * Each kid's receiving address is derived under this domain.
 */
export const PAYMENT_RECEIPT: DomainFlag = 0x00010003;

/**
 * CHORE_DEFINITION: 0x00010004
 * Domain for keys used by parents to sign chore templates.
 * Proves the parent authorized this chore and its reward value.
 */
export const CHORE_DEFINITION: DomainFlag = 0x00010004;

/**
 * FAMILY_SYNC: 0x00010005
 * Domain for keys used in device-to-device and device-to-app sync.
 * Authenticates sync payloads between piggy banks and the parent app.
 */
export const FAMILY_SYNC: DomainFlag = 0x00010005;

/**
 * SPENDING_AUTH: 0x00010006
 * Domain for keys authorizing outbound spending from a piggy bank.
 * Parent co-signs above the kid's spending threshold.
 */
export const SPENDING_AUTH: DomainFlag = 0x00010006;

```
