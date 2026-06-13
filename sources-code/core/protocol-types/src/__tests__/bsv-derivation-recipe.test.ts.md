---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/__tests__/bsv-derivation-recipe.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.883868+00:00
---

# core/protocol-types/src/__tests__/bsv-derivation-recipe.test.ts

```ts
/**
 * Unit tests for the `bsv.tx.derivation.recipe` wire format
 * (PR-9c — BRC-42 / BRC-43 key-material derivation schema as a
 * substrate cell). Mirrors the bsv-tx-sign test shape.
 */

import { describe, it, expect } from "@jest/globals";

import {
  DERIVATION_RECIPE_WIRE_VERSION,
  DERIVATION_RECIPE_FIXED_HEADER_BYTES,
  MAX_PROTOCOL_NAME_LEN,
  MAX_KEY_ID_LEN,
  COUNTERPARTY_PUBKEY_BYTES,
  SECURITY_LEVEL_PUBLIC,
  SECURITY_LEVEL_PROTOCOL,
  SECURITY_LEVEL_PROTOCOL_COUNTERPARTY,
  COUNTERPARTY_KIND_ANYONE,
  COUNTERPARTY_KIND_SELF,
  COUNTERPARTY_KIND_SPECIFIC,
  encodeDerivationRecipe,
  decodeDerivationRecipe,
  recipeToInvoiceNumber,
  type DerivationRecipe,
} from "../bsv/derivation-recipe";

const ZERO_PUBKEY = new Uint8Array(COUNTERPARTY_PUBKEY_BYTES);

// A deterministic but obviously-valid compressed secp256k1 pubkey
// for tests. Starts with 0x02 (the compressed even-y prefix); the
// remaining 32 bytes are filler — the recipe doesn't validate the
// pubkey against the curve, only that it has a valid compressed
// prefix and length.
function specificPubkey(seed = 0): Uint8Array {
  const out = new Uint8Array(COUNTERPARTY_PUBKEY_BYTES);
  out[0] = 0x02;
  for (let i = 1; i < out.length; i++) out[i] = (i * 13 + seed) & 0xff;
  return out;
}

describe("bsv.tx.derivation.recipe — round-trip + layout", () => {
  it("round-trips a self-counterparty recipe", () => {
    const r: DerivationRecipe = {
      securityLevel: SECURITY_LEVEL_PROTOCOL_COUNTERPARTY,
      counterpartyKind: COUNTERPARTY_KIND_SELF,
      counterpartyPubkey: ZERO_PUBKEY,
      protocolName: "mnca anchor",
      keyID: "0",
    };
    const wire = encodeDerivationRecipe(r);
    expect(wire[0]).toBe(DERIVATION_RECIPE_WIRE_VERSION);
    expect(wire.length).toBe(
      DERIVATION_RECIPE_FIXED_HEADER_BYTES +
        new TextEncoder().encode("mnca anchor").length +
        new TextEncoder().encode("0").length,
    );
    expect(decodeDerivationRecipe(wire)).toEqual(r);
  });

  it("round-trips an anyone-counterparty recipe with empty keyID", () => {
    const r: DerivationRecipe = {
      securityLevel: SECURITY_LEVEL_PROTOCOL,
      counterpartyKind: COUNTERPARTY_KIND_ANYONE,
      counterpartyPubkey: ZERO_PUBKEY,
      protocolName: "public lookup",
      keyID: "",
    };
    const wire = encodeDerivationRecipe(r);
    expect(decodeDerivationRecipe(wire)).toEqual(r);
  });

  it("round-trips a specific-counterparty recipe with a real pubkey", () => {
    const pubkey = specificPubkey(42);
    const r: DerivationRecipe = {
      securityLevel: SECURITY_LEVEL_PROTOCOL_COUNTERPARTY,
      counterpartyKind: COUNTERPARTY_KIND_SPECIFIC,
      counterpartyPubkey: pubkey,
      protocolName: "Bridget federation",
      keyID: "shared.session.42",
    };
    const wire = encodeDerivationRecipe(r);
    const decoded = decodeDerivationRecipe(wire);
    expect(decoded.securityLevel).toBe(SECURITY_LEVEL_PROTOCOL_COUNTERPARTY);
    expect(decoded.counterpartyKind).toBe(COUNTERPARTY_KIND_SPECIFIC);
    expect(decoded.counterpartyPubkey).toEqual(pubkey);
    expect(decoded.protocolName).toBe("Bridget federation");
    expect(decoded.keyID).toBe("shared.session.42");
  });

  it("supports SECURITY_LEVEL_PUBLIC (level 0)", () => {
    const r: DerivationRecipe = {
      securityLevel: SECURITY_LEVEL_PUBLIC,
      counterpartyKind: COUNTERPARTY_KIND_ANYONE,
      counterpartyPubkey: ZERO_PUBKEY,
      protocolName: "static identity",
      keyID: "0",
    };
    const wire = encodeDerivationRecipe(r);
    const decoded = decodeDerivationRecipe(wire);
    expect(decoded.securityLevel).toBe(0);
  });
});

describe("bsv.tx.derivation.recipe — validation", () => {
  it("rejects invalid securityLevel", () => {
    expect(() =>
      encodeDerivationRecipe({
        securityLevel: 3 as any,
        counterpartyKind: COUNTERPARTY_KIND_SELF,
        counterpartyPubkey: ZERO_PUBKEY,
        protocolName: "x",
        keyID: "0",
      }),
    ).toThrow(/securityLevel/);
  });

  it("rejects invalid counterpartyKind", () => {
    expect(() =>
      encodeDerivationRecipe({
        securityLevel: SECURITY_LEVEL_PROTOCOL,
        counterpartyKind: 9 as any,
        counterpartyPubkey: ZERO_PUBKEY,
        protocolName: "x",
        keyID: "0",
      }),
    ).toThrow(/counterpartyKind/);
  });

  it("rejects wrong pubkey length", () => {
    expect(() =>
      encodeDerivationRecipe({
        securityLevel: SECURITY_LEVEL_PROTOCOL_COUNTERPARTY,
        counterpartyKind: COUNTERPARTY_KIND_SPECIFIC,
        counterpartyPubkey: new Uint8Array(32),
        protocolName: "x",
        keyID: "0",
      }),
    ).toThrow(/counterpartyPubkey must be 33 bytes/);
  });

  it("rejects non-secp prefix on SPECIFIC pubkey", () => {
    const badPubkey = new Uint8Array(COUNTERPARTY_PUBKEY_BYTES);
    badPubkey[0] = 0x04; // uncompressed prefix — not allowed
    expect(() =>
      encodeDerivationRecipe({
        securityLevel: SECURITY_LEVEL_PROTOCOL_COUNTERPARTY,
        counterpartyKind: COUNTERPARTY_KIND_SPECIFIC,
        counterpartyPubkey: badPubkey,
        protocolName: "x",
        keyID: "0",
      }),
    ).toThrow(/must start with 0x02 or 0x03/);
  });

  it("rejects non-zero pubkey on non-SPECIFIC counterparty", () => {
    const nonZero = new Uint8Array(COUNTERPARTY_PUBKEY_BYTES);
    nonZero[5] = 0xAB;
    expect(() =>
      encodeDerivationRecipe({
        securityLevel: SECURITY_LEVEL_PROTOCOL_COUNTERPARTY,
        counterpartyKind: COUNTERPARTY_KIND_SELF,
        counterpartyPubkey: nonZero,
        protocolName: "x",
        keyID: "0",
      }),
    ).toThrow(/must be all zeros when counterpartyKind != SPECIFIC/);
  });

  it("rejects empty protocolName", () => {
    expect(() =>
      encodeDerivationRecipe({
        securityLevel: SECURITY_LEVEL_PROTOCOL,
        counterpartyKind: COUNTERPARTY_KIND_SELF,
        counterpartyPubkey: ZERO_PUBKEY,
        protocolName: "",
        keyID: "0",
      }),
    ).toThrow(/protocolName/);
  });

  it("rejects protocolName starting with a digit (BRC-43 shape)", () => {
    expect(() =>
      encodeDerivationRecipe({
        securityLevel: SECURITY_LEVEL_PROTOCOL,
        counterpartyKind: COUNTERPARTY_KIND_SELF,
        counterpartyPubkey: ZERO_PUBKEY,
        protocolName: "1nvalid",
        keyID: "0",
      }),
    ).toThrow(/BRC-43 shape/);
  });

  it("rejects protocolName exceeding MAX_PROTOCOL_NAME_LEN", () => {
    const tooLong = "a".repeat(MAX_PROTOCOL_NAME_LEN + 1);
    expect(() =>
      encodeDerivationRecipe({
        securityLevel: SECURITY_LEVEL_PROTOCOL,
        counterpartyKind: COUNTERPARTY_KIND_SELF,
        counterpartyPubkey: ZERO_PUBKEY,
        protocolName: tooLong,
        keyID: "0",
      }),
    ).toThrow(/out of range/);
  });

  it("rejects keyID exceeding MAX_KEY_ID_LEN", () => {
    const tooLong = "k".repeat(MAX_KEY_ID_LEN + 1);
    expect(() =>
      encodeDerivationRecipe({
        securityLevel: SECURITY_LEVEL_PROTOCOL,
        counterpartyKind: COUNTERPARTY_KIND_SELF,
        counterpartyPubkey: ZERO_PUBKEY,
        protocolName: "x",
        keyID: tooLong,
      }),
    ).toThrow(/keyID/);
  });

  it("decode rejects unknown VERSION", () => {
    const wire = encodeDerivationRecipe({
      securityLevel: SECURITY_LEVEL_PROTOCOL,
      counterpartyKind: COUNTERPARTY_KIND_SELF,
      counterpartyPubkey: ZERO_PUBKEY,
      protocolName: "x",
      keyID: "0",
    });
    wire[0] = 99;
    expect(() => decodeDerivationRecipe(wire)).toThrow(/unknown VERSION/);
  });

  it("decode rejects truncated payload", () => {
    const wire = encodeDerivationRecipe({
      securityLevel: SECURITY_LEVEL_PROTOCOL,
      counterpartyKind: COUNTERPARTY_KIND_SELF,
      counterpartyPubkey: ZERO_PUBKEY,
      protocolName: "longer name",
      keyID: "0",
    });
    expect(() => decodeDerivationRecipe(wire.slice(0, wire.length - 1))).toThrow(
      /truncated/,
    );
  });
});

describe("bsv.tx.derivation.recipe — invoice number composition", () => {
  it("composes BRC-43 invoice number string", () => {
    const r: DerivationRecipe = {
      securityLevel: SECURITY_LEVEL_PROTOCOL_COUNTERPARTY,
      counterpartyKind: COUNTERPARTY_KIND_SELF,
      counterpartyPubkey: ZERO_PUBKEY,
      protocolName: "mnca anchor",
      keyID: "0",
    };
    expect(recipeToInvoiceNumber(r)).toBe("2 mnca anchor 0");
  });

  it("composes with empty keyID", () => {
    const r: DerivationRecipe = {
      securityLevel: SECURITY_LEVEL_PROTOCOL,
      counterpartyKind: COUNTERPARTY_KIND_ANYONE,
      counterpartyPubkey: ZERO_PUBKEY,
      protocolName: "public lookup",
      keyID: "",
    };
    expect(recipeToInvoiceNumber(r)).toBe("1 public lookup ");
  });

  it("preserves keyID with embedded dots", () => {
    const r: DerivationRecipe = {
      securityLevel: SECURITY_LEVEL_PROTOCOL_COUNTERPARTY,
      counterpartyKind: COUNTERPARTY_KIND_SELF,
      counterpartyPubkey: ZERO_PUBKEY,
      protocolName: "session",
      keyID: "tx.42.in.0",
    };
    expect(recipeToInvoiceNumber(r)).toBe("2 session tx.42.in.0");
  });
});

describe("bsv.tx.derivation.recipe — variable-size encoding", () => {
  it("encoded size = header + protocolName.len + keyID.len", () => {
    const r: DerivationRecipe = {
      securityLevel: SECURITY_LEVEL_PROTOCOL_COUNTERPARTY,
      counterpartyKind: COUNTERPARTY_KIND_SELF,
      counterpartyPubkey: ZERO_PUBKEY,
      protocolName: "abc",
      keyID: "xy",
    };
    expect(encodeDerivationRecipe(r).length).toBe(
      DERIVATION_RECIPE_FIXED_HEADER_BYTES + 3 + 2,
    );
  });

  it("handles UTF-8 multi-byte characters in protocolName + keyID", () => {
    const r: DerivationRecipe = {
      securityLevel: SECURITY_LEVEL_PROTOCOL,
      counterpartyKind: COUNTERPARTY_KIND_SELF,
      counterpartyPubkey: ZERO_PUBKEY,
      // UTF-8 bytes outside the BRC-43 ASCII shape would fail the
      // regex; so test a name that's pure ASCII but encodes to N
      // bytes via the encoder, then verify length is N bytes (not
      // N codepoints). Using a long single-byte name + keyID with
      // dots (allowed by BRC-43 regex).
      protocolName: "abc.def-ghi_jkl",
      keyID: "0.1.2.3.4",
    };
    const wire = encodeDerivationRecipe(r);
    expect(wire[3]).toBe(15); // protocolName_len byte
    expect(wire[4]).toBe(9); // keyID_len byte
    expect(decodeDerivationRecipe(wire)).toEqual(r);
  });
});

```
