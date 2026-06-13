---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mfp/protocol-id.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.868847+00:00
---

# core/protocol-types/src/mfp/protocol-id.ts

```ts
/**
 * MFP (Metered-Flow-Protocol) BRC-43 protocolID convention.
 *
 * The metered-flow vault is not a storage location — it's a
 * `(protocolID, cap)` spending grant scoped through BRC-100. This module
 * defines the BRC-43 protocolID that scopes a metered flow's spending
 * authority, so the same grant resolves identically across any BRC-100
 * wallet backend (Metanet Desktop permission dialog, Semantos browser
 * iframe wallet IndexedDB budget, wallet-headers cartridge, or an
 * embedded agent wallet like Dolphin Milk).
 *
 * See esp32-hackkit/docs/x402-over-cells.md for the cell-mesh transport
 * binding and docs/design/WALLET-TIER-CUSTODY.md §7.1 for the Tier-0
 * no-prompt micropayment budget this protocolID scopes.
 *
 * Why security level 2: a metered-flow grant is per-app AND
 * per-counterparty — "allow up to F sats to THIS provider for THIS
 * commodity." Level 2 (BRC-43) is exactly per-app + per-counterparty
 * permission, which is the right granularity for a spending cap bound to
 * one provider. The counterparty is supplied separately on each
 * createAction/createSignature call (the provider's identity key); the
 * protocolID string carries the commodity so distinct commodities from
 * the same provider get distinct grants.
 */

import type { WalletProtocol, SecurityLevel } from '@bsv/sdk';

/** Security level for all MFP grants — per-app, per-counterparty. */
export const MFP_SECURITY_LEVEL: SecurityLevel = 2;

/** Protocol-string prefix; the commodity id is appended. */
export const MFP_PROTOCOL_PREFIX = 'mfp metering';

/**
 * Build the BRC-43 protocolID for a metered flow of a given commodity.
 *
 * The commodity id (e.g. "energy.wh", "bandwidth.mb", "water.l") becomes
 * part of the protocol string so the wallet derives a distinct key +
 * tracks a distinct spending grant per commodity. The counterparty
 * (provider identity key) is passed separately on the wallet call — it
 * is NOT baked into the protocolID, so one grant string covers a
 * commodity and the wallet's level-2 permissioning handles the
 * per-counterparty scoping.
 *
 * BRC-43 constrains the protocol string to 5..400 bytes, lowercase
 * letters/numbers/spaces, no leading/trailing space, no double spaces.
 * We normalize the commodity id (dots → spaces) to satisfy that.
 */
export function mfpProtocolID(commodityId: string): WalletProtocol {
  const normalized = normalizeCommodity(commodityId);
  const proto = `${MFP_PROTOCOL_PREFIX} ${normalized}`;
  assertValidProtocolString(proto);
  return [MFP_SECURITY_LEVEL, proto];
}

/**
 * keyID convention for a specific flow instance under the commodity
 * protocolID. Each open channel / grant gets a fresh keyID so the
 * BRC-42 derivation produces a unique signing key per flow (fresh-key-
 * per-flow, mirroring the wallet's fresh-key-per-tx default). The flow
 * id is an opaque caller-chosen string (e.g. a 16-byte hex offer/flow
 * id).
 */
export function mfpKeyID(flowId: string): string {
  return `flow ${flowId}`;
}

// ── BRC-43 protocol-string validation ───────────────────────────────

function normalizeCommodity(commodityId: string): string {
  return commodityId
    .toLowerCase()
    .replace(/[._/]+/g, ' ')   // dots / underscores / slashes → space
    .replace(/[^a-z0-9 ]+/g, '') // strip anything else
    .replace(/\s+/g, ' ')      // collapse whitespace
    .trim();
}

/** Throws if `s` violates BRC-43's protocol-string rules. */
export function assertValidProtocolString(s: string): void {
  if (s.length < 5 || s.length > 400) {
    throw new Error(`MFP protocol string must be 5..400 bytes, got ${s.length}`);
  }
  if (!/^[a-z0-9 ]+$/.test(s)) {
    throw new Error(`MFP protocol string must be lowercase letters/numbers/spaces: "${s}"`);
  }
  if (s !== s.trim() || s.includes('  ')) {
    throw new Error(`MFP protocol string must not have leading/trailing/double spaces: "${s}"`);
  }
}

```
