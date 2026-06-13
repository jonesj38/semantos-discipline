---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/bsv/derivation-recipe.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.870921+00:00
---

# core/protocol-types/src/bsv/derivation-recipe.ts

```ts
/**
 * Wire format for `bsv.tx.derivation.recipe` — the BRC-42 / BRC-43
 * key-material derivation schema, as a substrate cellType.
 *
 * What this IS (concept disambiguation per PR-9 v2):
 *
 *   A DerivationRecipe is the content-addressable specification two
 *   parties feed to a BRC-42 derivation to arrive at the same leaf
 *   key (or pubkey) without sharing private material. It carries
 *   `(securityLevel, protocolName, keyID, counterparty)` — the exact
 *   inputs BRC-43's invoice-number derivation expects. The recipe is
 *   load-bearing for:
 *
 *     - **Recovery**: given a root seed + a recipe cell-hash, the
 *       holder can reproduce ANY derived key for any output bound to
 *       that recipe. No per-output state needs to be retained.
 *
 *     - **E2E p2p interop**: two peers with their respective root
 *       keys + the shared recipe independently arrive at the same
 *       shared pubkey (counterparty path) without round-tripping.
 *
 *     - **Sign.request resolution**: the `recipe_id` field at offset
 *       33 of a `bsv.tx.sign.request` payload (per
 *       `tx-sign.ts::TxSignRequest.recipeId`) carries the cell-hash
 *       of a `bsv.tx.derivation.recipe` cell. The wallet reads it,
 *       resolves to the recipe, derives the right leaf key, signs
 *       the digest.
 *
 * What this IS NOT:
 *
 *   - Not a SpendPolicy (`runtime/semantos-brain/src/spend_policy.zig`).
 *     SpendPolicy is the brain-side on-chain-enforcement-dispatch
 *     contract (sighash flag + structural predicate + grind surface);
 *     DerivationRecipe is the wallet-side key-material composition
 *     spec. These are orthogonal: one recipe (key) can be used with
 *     multiple policies (tx shapes); one policy (tx shape) can be
 *     used with multiple recipes (keys). PR-9 v1 briefly conflated
 *     them; PR-9 v2 split + this PR (PR-9c) defines the recipe side.
 *
 * Reference: BRC-42 (BRC-42 Public Key Derivation), BRC-43
 * (Security Levels + Invoice Number Construction), LOCKSCRIPT-
 * CLEAVAGE.md §3.5 (the sign.request's derivation-recipe seam).
 *
 * Note on scope: PR-9c ships the wire format + cellType registration
 * + encode/decode + tests. The brain-side wiring that actually
 * populates the sign.request `recipe_id` with a real derivation-
 * recipe cell-hash (instead of the PR-9 v2 reserved zeros) lands in
 * a future PR — likely PR-8b-vi-3's planned semantics.
 */

import { TX_PARTIAL_WIRE_VERSION } from "./tx-partial";

/** Re-exported for callers wiring only the derivation-recipe path. */
export const DERIVATION_RECIPE_WIRE_VERSION = TX_PARTIAL_WIRE_VERSION;

/**
 * BRC-43 security levels.
 *
 *   - 0 (PUBLIC): no derivation; key is reuseable across all
 *     counterparties + all keyIDs. Used for static identity keys.
 *   - 1 (PROTOCOL): per-protocol derivation, shared across keyIDs
 *     within the protocol.
 *   - 2 (PROTOCOL_COUNTERPARTY): per-protocol AND per-counterparty
 *     derivation. The strictest level; used for sensitive signing
 *     operations (most spend contexts).
 */
export const SECURITY_LEVEL_PUBLIC = 0 as const;
export const SECURITY_LEVEL_PROTOCOL = 1 as const;
export const SECURITY_LEVEL_PROTOCOL_COUNTERPARTY = 2 as const;
export type SecurityLevel = 0 | 1 | 2;

/**
 * Counterparty selector. Two well-known string identifiers OR an
 * explicit secp256k1 compressed pubkey.
 *
 *   - "anyone": canonical public counterparty (BRC-42 §5)
 *   - "self": derive against the operator's own identity key
 *   - "specific" + pubkey: explicit counterparty pubkey
 */
export const COUNTERPARTY_KIND_ANYONE = 0 as const;
export const COUNTERPARTY_KIND_SELF = 1 as const;
export const COUNTERPARTY_KIND_SPECIFIC = 2 as const;
export type CounterpartyKind = 0 | 1 | 2;

/**
 * Length bounds on the variable-size fields. Chosen to keep the
 * encoded recipe well under the 768-byte cell payload budget even
 * at maximum sizes (38 fixed + 128 + 128 = 294 bytes max).
 *
 * BRC-43 protocol names are typically short (< 32 chars in practice);
 * 128 is a generous bound for future-proofing. KeyIDs are usually
 * numeric indices but BRC-43 allows arbitrary strings.
 */
export const MAX_PROTOCOL_NAME_LEN = 128 as const;
export const MAX_KEY_ID_LEN = 128 as const;
export const COUNTERPARTY_PUBKEY_BYTES = 33 as const;

/**
 * Decoded DerivationRecipe payload.
 *
 * Layout (variable-size; 38 fixed header + variable strings):
 *
 *     0   1   VERSION = 1
 *     1   1   security_level (0 | 1 | 2)
 *     2   1   counterparty_kind (0 = anyone | 1 = self | 2 = specific)
 *     3   1   protocol_name_len (1..MAX_PROTOCOL_NAME_LEN)
 *     4   1   key_id_len (0..MAX_KEY_ID_LEN)
 *     5  33   counterparty_pubkey (zeros when kind != 2; raw
 *             compressed secp256k1 pubkey when kind == 2)
 *    38  protocol_name_len  protocol_name (UTF-8)
 *     ?  key_id_len         key_id (UTF-8)
 *
 * Total = 38 + protocol_name_len + key_id_len bytes.
 */
export const DERIVATION_RECIPE_FIXED_HEADER_BYTES = 38 as const;

export interface DerivationRecipe {
  readonly securityLevel: SecurityLevel;
  readonly counterpartyKind: CounterpartyKind;
  /**
   * Compressed secp256k1 pubkey (33 bytes). Required when
   * `counterpartyKind === COUNTERPARTY_KIND_SPECIFIC`. Must be 33
   * bytes of zeros for the other kinds.
   */
  readonly counterpartyPubkey: Uint8Array;
  /**
   * BRC-43 protocol name. ASCII letters / digits / common
   * punctuation. The TS validator here mirrors the brain's strict
   * shape (`/^[a-zA-Z][a-zA-Z0-9._\- ]*$/` — leading letter, then
   * letters/digits/dot/underscore/dash/space). Metanet Desktop's
   * input validator rejects names with dots; that's a wallet
   * choice, not a BRC-43 requirement.
   */
  readonly protocolName: string;
  /**
   * BRC-43 keyID. Often a numeric index ("0", "1", …) but the spec
   * allows arbitrary strings. May be empty (length 0).
   */
  readonly keyID: string;
}

const PROTOCOL_NAME_RE = /^[a-zA-Z][a-zA-Z0-9._\- ]*$/;

/**
 * Encode a DerivationRecipe to its substrate-cell payload bytes.
 * Throws on out-of-range fields. The result fits in a single
 * 1024-byte cell's payload section (≤ 294 bytes encoded).
 */
export function encodeDerivationRecipe(r: DerivationRecipe): Uint8Array {
  if (
    r.securityLevel !== 0 &&
    r.securityLevel !== 1 &&
    r.securityLevel !== 2
  ) {
    throw new RangeError(
      `encodeDerivationRecipe: securityLevel must be 0, 1, or 2 ` +
        `(got ${r.securityLevel})`,
    );
  }
  if (
    r.counterpartyKind !== 0 &&
    r.counterpartyKind !== 1 &&
    r.counterpartyKind !== 2
  ) {
    throw new RangeError(
      `encodeDerivationRecipe: counterpartyKind must be 0, 1, or 2 ` +
        `(got ${r.counterpartyKind})`,
    );
  }
  if (r.counterpartyPubkey.length !== COUNTERPARTY_PUBKEY_BYTES) {
    throw new RangeError(
      `encodeDerivationRecipe: counterpartyPubkey must be ` +
        `${COUNTERPARTY_PUBKEY_BYTES} bytes (got ${r.counterpartyPubkey.length})`,
    );
  }
  if (r.counterpartyKind === COUNTERPARTY_KIND_SPECIFIC) {
    if (
      r.counterpartyPubkey[0] !== 0x02 &&
      r.counterpartyPubkey[0] !== 0x03
    ) {
      throw new RangeError(
        `encodeDerivationRecipe: SPECIFIC counterparty pubkey must ` +
          `start with 0x02 or 0x03 (compressed secp256k1); got 0x` +
          r.counterpartyPubkey[0].toString(16),
      );
    }
  } else {
    for (let i = 0; i < r.counterpartyPubkey.length; i++) {
      if (r.counterpartyPubkey[i] !== 0) {
        throw new RangeError(
          `encodeDerivationRecipe: counterpartyPubkey must be all ` +
            `zeros when counterpartyKind != SPECIFIC`,
        );
      }
    }
  }
  if (!PROTOCOL_NAME_RE.test(r.protocolName)) {
    throw new RangeError(
      `encodeDerivationRecipe: protocolName "${r.protocolName}" ` +
        `fails BRC-43 shape /^[a-zA-Z][a-zA-Z0-9._\\- ]*$/`,
    );
  }
  const protocolNameBytes = new TextEncoder().encode(r.protocolName);
  if (
    protocolNameBytes.length < 1 ||
    protocolNameBytes.length > MAX_PROTOCOL_NAME_LEN
  ) {
    throw new RangeError(
      `encodeDerivationRecipe: protocolName UTF-8 length ` +
        `${protocolNameBytes.length} out of range [1, ${MAX_PROTOCOL_NAME_LEN}]`,
    );
  }
  const keyIDBytes = new TextEncoder().encode(r.keyID);
  if (keyIDBytes.length > MAX_KEY_ID_LEN) {
    throw new RangeError(
      `encodeDerivationRecipe: keyID UTF-8 length ` +
        `${keyIDBytes.length} > ${MAX_KEY_ID_LEN}`,
    );
  }

  const total =
    DERIVATION_RECIPE_FIXED_HEADER_BYTES +
    protocolNameBytes.length +
    keyIDBytes.length;
  const out = new Uint8Array(total);
  out[0] = DERIVATION_RECIPE_WIRE_VERSION;
  out[1] = r.securityLevel;
  out[2] = r.counterpartyKind;
  out[3] = protocolNameBytes.length;
  out[4] = keyIDBytes.length;
  // 5..38 = counterparty_pubkey (33 bytes)
  out.set(r.counterpartyPubkey, 5);
  out.set(protocolNameBytes, DERIVATION_RECIPE_FIXED_HEADER_BYTES);
  out.set(
    keyIDBytes,
    DERIVATION_RECIPE_FIXED_HEADER_BYTES + protocolNameBytes.length,
  );
  return out;
}

/** Decode the encoded payload bytes. Strict validation. */
export function decodeDerivationRecipe(payload: Uint8Array): DerivationRecipe {
  if (payload.length < DERIVATION_RECIPE_FIXED_HEADER_BYTES) {
    throw new RangeError(
      `decodeDerivationRecipe: payload < ${DERIVATION_RECIPE_FIXED_HEADER_BYTES} ` +
        `bytes (got ${payload.length})`,
    );
  }
  if (payload[0] !== DERIVATION_RECIPE_WIRE_VERSION) {
    throw new RangeError(
      `decodeDerivationRecipe: unknown VERSION=${payload[0]}`,
    );
  }
  const securityLevel = payload[1];
  if (securityLevel !== 0 && securityLevel !== 1 && securityLevel !== 2) {
    throw new RangeError(
      `decodeDerivationRecipe: invalid securityLevel=${securityLevel}`,
    );
  }
  const counterpartyKind = payload[2];
  if (
    counterpartyKind !== 0 &&
    counterpartyKind !== 1 &&
    counterpartyKind !== 2
  ) {
    throw new RangeError(
      `decodeDerivationRecipe: invalid counterpartyKind=${counterpartyKind}`,
    );
  }
  const protocolNameLen = payload[3];
  const keyIDLen = payload[4];
  if (protocolNameLen < 1 || protocolNameLen > MAX_PROTOCOL_NAME_LEN) {
    throw new RangeError(
      `decodeDerivationRecipe: protocol_name_len=${protocolNameLen} out of range`,
    );
  }
  if (keyIDLen > MAX_KEY_ID_LEN) {
    throw new RangeError(
      `decodeDerivationRecipe: key_id_len=${keyIDLen} > ${MAX_KEY_ID_LEN}`,
    );
  }
  const required =
    DERIVATION_RECIPE_FIXED_HEADER_BYTES + protocolNameLen + keyIDLen;
  if (payload.length < required) {
    throw new RangeError(
      `decodeDerivationRecipe: payload truncated; needed ${required}, ` +
        `got ${payload.length}`,
    );
  }
  const counterpartyPubkey = payload.slice(5, 5 + COUNTERPARTY_PUBKEY_BYTES);
  const protocolName = new TextDecoder().decode(
    payload.slice(
      DERIVATION_RECIPE_FIXED_HEADER_BYTES,
      DERIVATION_RECIPE_FIXED_HEADER_BYTES + protocolNameLen,
    ),
  );
  const keyID = new TextDecoder().decode(
    payload.slice(
      DERIVATION_RECIPE_FIXED_HEADER_BYTES + protocolNameLen,
      DERIVATION_RECIPE_FIXED_HEADER_BYTES + protocolNameLen + keyIDLen,
    ),
  );
  return {
    securityLevel: securityLevel as SecurityLevel,
    counterpartyKind: counterpartyKind as CounterpartyKind,
    counterpartyPubkey,
    protocolName,
    keyID,
  };
}

/**
 * Compose the BRC-43 invoice number from a recipe. The invoice
 * number is the string the wallet feeds into the derivation
 * function (HMAC over the root key, etc. — see BRC-42 §3 + BRC-43
 * §4). Shape:
 *
 *     "<securityLevel> <protocolName> <keyID>"
 *
 * Note: BRC-43 specifies a space separator. Real wallets may
 * normalize further (e.g. lowercase the protocol name); this
 * helper returns the canonical un-normalized form so the brain +
 * the wallet can negotiate the exact normalisation independently.
 */
export function recipeToInvoiceNumber(r: DerivationRecipe): string {
  return `${r.securityLevel} ${r.protocolName} ${r.keyID}`;
}

```
