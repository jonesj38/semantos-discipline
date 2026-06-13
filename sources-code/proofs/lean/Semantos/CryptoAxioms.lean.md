---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/CryptoAxioms.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.358091+00:00
---

# proofs/lean/Semantos/CryptoAxioms.lean

```lean
-- Semantos Plane — Cryptographic Axioms
--
-- We axiomatize three standard cryptographic primitives as idealized oracles.
-- This is deliberately stronger than the computational security definitions
-- (which involve PPT bounds and negligible probability). Lean has no notion
-- of computational complexity, so we use perfect (information-theoretic)
-- versions. This is standard practice in mechanized verification — see e.g.
-- the EasyCrypt and CryptoVerif projects.
--
-- The real-world justification rests on decades of cryptanalysis:
-- - SHA-256: no collision found since standardization (2001)
-- - ECDSA/secp256k1: standard assumption in Bitcoin ecosystem since 2009
-- - HMAC-SHA-256: PRF security proven under SHA-256 compression function assumptions
--
-- See Appendix B of docs/FORMAL-VERIFICATION-STRATEGY.md for the
-- two-level assumption structure.

namespace Semantos.Crypto

-- Opaque types for cryptographic primitives.
-- We do not model their internal structure — only their security properties.

axiom Bytes : Type
axiom PubKey : Type
axiom SecKey : Type

-- Primitive operations (axiomatized — we reason only about their security properties)

axiom sha256 : Bytes → Bytes
axiom ecdsaVerify : PubKey → Bytes → Bytes → Bool
axiom derives : PubKey → SecKey → Prop
axiom hmacSha256 : Bytes → Bytes → Bytes

-- Axiom 1: SHA-256 Collision Resistance
--
-- Idealization of: no PPT adversary can find m1 ≠ m2 such that
-- SHA-256(m1) = SHA-256(m2) with non-negligible probability.
--
-- Why idealization is acceptable: In mechanized verification, we cannot
-- express "PPT adversary" or "negligible probability." The perfect
-- collision-free assumption is stronger than needed, which means our
-- proofs hold a fortiori under the standard computational assumption.
-- If SHA-256 collision resistance breaks, the consequences extend far
-- beyond Semantos (Bitcoin, TLS, certificate infrastructure all fail).

axiom sha256_collision_free :
  ∀ (m1 m2 : Bytes), m1 ≠ m2 → sha256 m1 ≠ sha256 m2

-- Axiom 2: ECDSA Existential Unforgeability (secp256k1)
--
-- Idealization of: EUF-CMA (Existential Unforgeability under Chosen
-- Message Attack) security for ECDSA on secp256k1. Under EUF-CMA,
-- no PPT adversary with access to a signing oracle can produce a
-- valid signature on a message not previously queried.
--
-- Our axiom says: if verification succeeds, then there exists a secret
-- key that derives the public key. This does NOT claim unique signatures
-- (ECDSA signatures are randomized). It captures the essential property:
-- a valid signature implies knowledge of the private key.

axiom ecdsa_existential_unforgeability :
  ∀ (pk : PubKey) (msg sig : Bytes),
    ecdsaVerify pk msg sig = true →
    ∃ (sk : SecKey), derives pk sk

-- Axiom 2b: ECDSA Signing — Correctness (Phase W1, paired with axiom 2)
--
-- A signature produced by the secret key sk verifies under the corresponding
-- public key pk. This is the idealized signing oracle that mirrors the
-- existential-unforgeability axiom above. Together they form a complete
-- pair: the signing axiom guarantees that legitimate signatures verify;
-- the unforgeability axiom guarantees that verifying signatures imply
-- knowledge of the key. The pair is what we need to prove K11 for OP_SIGN.

axiom ecdsaSign : SecKey → Bytes → Bytes

axiom ecdsa_sign_verifies :
  ∀ (sk : SecKey) (pk : PubKey) (msg : Bytes),
    derives pk sk → ecdsaVerify pk msg (ecdsaSign sk msg) = true

-- Axiom 3: HMAC-SHA-256 Collision Resistance (as PRF consequence)
--
-- Idealization of: HMAC-SHA-256 is a PRF (Pseudo-Random Function) when
-- keyed with a uniformly random key. A PRF is indistinguishable from
-- a truly random function, which implies collision resistance.
--
-- We state the collision-free property directly because it is what our
-- proofs require. The full PRF assumption is stronger and implies this.

axiom hmac_collision_free :
  ∀ (k : Bytes) (m1 m2 : Bytes),
    m1 ≠ m2 → hmacSha256 k m1 ≠ hmacSha256 k m2

-- ══════════════════════════════════════════════════════════════════════
-- Axiom 4: BKDS — BRC-42 invoice-with-counterparty key derivation
--
-- Mirrors the production implementation at runtime/brain/src/bkds.zig.
-- The invoice on the wire is exactly:
--
--     "BKDS-BRC42-v1" ‖ u8(context_tag) ‖ u32_be(label.len) ‖ label
--
-- and BKDS derivation is:
--
--     shared      := ECDH(parent_priv, counterparty_pub)
--     tweak       := HMAC-SHA-256(invoice, key=shared)        // 32 bytes
--     child_priv  := (parent_priv + tweak) mod n              // n = secp256k1 order
--     child_pub   := child_priv · G                            // secp256k1 base point
--
-- We axiomatise BKDS as a pair-returning operation. We do NOT model
-- the ECDH/HMAC/scalar-add internals — those are proven correct by
-- the underlying primitives' security properties. We only need the
-- two security-relevant properties:
--
--   (a) bkds_derives_correct — the returned (childSk, childPk) is a
--       valid keypair under `derives` (so ECDSA signatures by childSk
--       verify under childPk by ecdsa_sign_verifies).
--   (b) bkds_injective_in_context_tag — different context_tag bytes,
--       same parent + counterparty + label, produce different child
--       pubkeys.
--
-- Justification of (b) — the load-bearing axiom for §2.5 carpenter+
-- musician hat isolation:
--
--     The BRC-42 invoice format embeds the context_tag as a single
--     byte at offset 13 (right after the "BKDS-BRC42-v1" domain
--     prefix). Two invocations with different context_tag bytes but
--     identical parent priv, counterparty pub, and label produce
--     two distinct invoice byte strings (they differ at byte 13).
--     HMAC-SHA-256 keyed with the same shared secret is collision-
--     resistant in its message argument under the standard PRF/CR
--     reduction (Bellare 1996, "Keying Hash Functions for Message
--     Authentication"; FIPS PUB 198-1 §B.1). Therefore the HMAC
--     tweaks differ. secp256k1 scalar addition mod n is a bijection
--     for a fixed parent scalar, so different tweaks → different
--     child private scalars. Scalar multiplication by the secp256k1
--     base point is injective on the scalar field (the base point
--     has order n, so the map x ↦ x·G is a bijection between
--     ℤ/nℤ \ {0} and the cyclic subgroup of secp256k1 generated by
--     G). Therefore different child private scalars → different
--     child public keys.
--
--     The negligible "tweak ⊕ scalar-add lands at 0" failure case
--     (Error.derivation_failed in bkds.zig) is collapsed into the
--     idealised total function here — Lean has no notion of
--     negligible probability, and the production code surfaces it
--     as an error rather than silently producing colliding keys, so
--     this axiomatisation is sound for the proof obligations below.
--
-- Justification of (a) — bkds_derives_correct:
--
--     By construction child_priv is a valid secp256k1 scalar (the
--     bkds.zig code rejects derivations that yield 0 or land outside
--     the curve order) and child_pub = child_priv · G is the
--     corresponding public key. So `derives child_pub child_priv`
--     holds by definition of `derives` (the ECDSA keypair relation).

axiom BKDSInvoice : Type

/-- Wire-format constants for the production BKDS invoice format,
    matching `runtime/brain/src/bkds.zig`'s `INVOICE_DOMAIN` constant.
    Idealised — the byte string is opaque, but the tag byte is
    extractable so the injectivity axiom can quantify over it. -/
axiom bkdsPrefix : Bytes

/-- Construct a BKDS invoice from its three logical fields.
    Mirrors `bkds.buildInvoice` in runtime/brain/src/bkds.zig:139:

        "BKDS-BRC42-v1" ‖ u8(context_tag) ‖ u32_be(label.len) ‖ label

    The Lean axiom is opaque over the byte-level encoding; the
    extractor axioms below let us reason about the two fields the
    proofs care about (contextTag and label). -/
axiom mkInvoice : (contextTag : UInt8) → (label : Bytes) → BKDSInvoice

/-- Read the context_tag byte off an invoice. The production wire
    format puts it at offset 13 (right after the 13-byte domain
    prefix). -/
axiom BKDSInvoice.contextTag : BKDSInvoice → UInt8

/-- Read the label off an invoice. -/
axiom BKDSInvoice.label : BKDSInvoice → Bytes

-- The two extractors are inverses of mkInvoice. Documented as axioms
-- because the wire format is byte-level and Lean models invoices
-- abstractly.

axiom mkInvoice_contextTag :
  ∀ (t : UInt8) (lbl : Bytes), (mkInvoice t lbl).contextTag = t

axiom mkInvoice_label :
  ∀ (t : UInt8) (lbl : Bytes), (mkInvoice t lbl).label = lbl

/-- BRC-42 BKDS derivation — given (parent_priv, counterparty_pub,
    invoice), returns the BKDS-derived (child_priv, child_pub) pair.
    Mirrors `bkds.deriveChildPubkey` (operator-side; brain holds
    parent priv) and `bkds.deriveChildPubkeyFromDevice` (device-side;
    same result by BRC-42 ECDH symmetry).

    See the comment block above for the security-relevant properties.
    The axiom is total — the negligible derivation_failed branch in
    the production code is idealised away. -/
axiom bkdsDerive : SecKey → PubKey → BKDSInvoice → SecKey × PubKey

-- ─────────────────────────────────────────────────────────────────
-- Axiom 4a: BKDS correctness (the derived pair is a valid keypair)
-- ─────────────────────────────────────────────────────────────────

/-- The pair returned by `bkdsDerive` is a valid (priv, pub) pair
    under `derives`. Direct consequence of the construction:
    child_pub = child_priv · G on secp256k1. This pairs with
    `ecdsa_sign_verifies` to prove that ECDSA signatures by the
    derived child priv verify under the derived child pub. -/
axiom bkds_derives_correct :
  ∀ (parentSk : SecKey) (counterpartyPk : PubKey) (inv : BKDSInvoice),
    derives (bkdsDerive parentSk counterpartyPk inv).2
            (bkdsDerive parentSk counterpartyPk inv).1

-- ─────────────────────────────────────────────────────────────────
-- Axiom 4b: BKDS injectivity in the context_tag byte
--
-- The load-bearing property for §2.5 hat-isolation. See the comment
-- block at the top of this section for the BRC-42 + HMAC + secp256k1
-- chain that justifies it.
-- ─────────────────────────────────────────────────────────────────

/-- Different context_tag bytes (with the same parent priv, the same
    counterparty pub, and the same label baked into the invoice)
    produce different child pubkeys.

    Justification chain:
      • BRC-42 invoice format (mirrored in bkds.zig:139) embeds the
        context_tag as one byte → distinct context_tag bytes →
        distinct invoice byte strings.
      • HMAC-SHA-256 collision-resistance in the message argument
        (Bellare 1996; FIPS PUB 198-1) → distinct invoices → distinct
        32-byte HMAC tweaks.
      • secp256k1 scalar arithmetic is a bijection on the scalar
        field for a fixed parent scalar → distinct tweaks → distinct
        child private scalars.
      • Scalar multiplication by G is injective on (ℤ/nℤ)\{0}
        (ord G = n) → distinct child private scalars → distinct
        child public keys.

    This is the cryptographic guarantee that backs the §2.5
    carpenter+musician hat-isolation invariant: a cap minted under
    context_tag 0x10 (carpenter) is bound to a child pubkey that
    cannot be re-derived by any party operating under context_tag
    0x11 (musician), even with full knowledge of the invoice
    structure and the parent's public key. -/
axiom bkds_injective_in_context_tag :
  ∀ (parentSk : SecKey) (counterpartyPk : PubKey) (inv1 inv2 : BKDSInvoice),
    inv1.contextTag ≠ inv2.contextTag →
    (bkdsDerive parentSk counterpartyPk inv1).2 ≠
      (bkdsDerive parentSk counterpartyPk inv2).2

end Semantos.Crypto

```
