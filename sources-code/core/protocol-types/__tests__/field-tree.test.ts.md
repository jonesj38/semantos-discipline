---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/field-tree.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.861664+00:00
---

# core/protocol-types/__tests__/field-tree.test.ts

```ts
/**
 * Per-field intra-tx Merkle tree tests.
 *
 * CW Lift L8 (docs/canon/cw-lift-matrix.yml).
 *
 * Pins the wire format of the leaf-hash preimage (magic + version +
 * domain separator + schema fingerprint binding), proves canonical-
 * order independence, round-trips disclosure proofs, and asserts
 * fail-closed verification on every form of tampering.
 *
 * Reference: docs/canon/cw-lift-matrix.yml L8; docs/prd/CW-LIFT-ROADMAP.md §2.
 */

import { describe, expect, test } from 'bun:test';
import { createHash } from 'crypto';
import {
  buildFieldTree,
  computeFieldLeaf,
  discloseField,
  FIELD_TREE_DOMAIN,
  FIELD_TREE_MAGIC,
  FIELD_TREE_VERSION,
  verifyFieldDisclosure,
  type FieldLeaf,
} from '../src/field-tree';

function fp(seed: number): Uint8Array {
  const b = new Uint8Array(32);
  for (let i = 0; i < 32; i++) b[i] = (seed * 11 + i * 7) & 0xff;
  return b;
}

function field(label: string, valueStr: string): FieldLeaf {
  return { label, value: new TextEncoder().encode(valueStr) };
}

function hex(b: Uint8Array): string {
  return Buffer.from(b).toString('hex');
}

describe('CW Lift L8: per-field intra-tx Merkle tree', () => {
  describe('constants + wire-format pins', () => {
    test('FIELD_TREE_MAGIC is "VARP"', () => {
      expect(FIELD_TREE_MAGIC).toEqual(new Uint8Array([0x56, 0x41, 0x52, 0x50]));
      expect(Buffer.from(FIELD_TREE_MAGIC).toString('ascii')).toBe('VARP');
    });

    test('FIELD_TREE_VERSION is 1 and FIELD_TREE_DOMAIN is pinned', () => {
      expect(FIELD_TREE_VERSION).toBe(1);
      expect(FIELD_TREE_DOMAIN).toBe('semantos.field-tree/v1');
    });
  });

  describe('computeFieldLeaf', () => {
    test('deterministic — same input always produces the same leaf hash', () => {
      const f = field('amount', '12345');
      const a = computeFieldLeaf(fp(1), f);
      const b = computeFieldLeaf(fp(1), f);
      expect(a).toEqual(b);
      expect(a.byteLength).toBe(32);
    });

    test('different schema fingerprints → different leaf hashes (binding)', () => {
      const f = field('amount', '12345');
      const a = computeFieldLeaf(fp(1), f);
      const b = computeFieldLeaf(fp(2), f);
      expect(hex(a)).not.toBe(hex(b));
    });

    test('different labels under same value → different leaf hashes', () => {
      const a = computeFieldLeaf(fp(1), field('amount', '12345'));
      const b = computeFieldLeaf(fp(1), field('total', '12345'));
      expect(hex(a)).not.toBe(hex(b));
    });

    test('different values under same label → different leaf hashes', () => {
      const a = computeFieldLeaf(fp(1), field('amount', '12345'));
      const b = computeFieldLeaf(fp(1), field('amount', '67890'));
      expect(hex(a)).not.toBe(hex(b));
    });

    test('rejects non-32B schema fingerprint', () => {
      expect(() => computeFieldLeaf(new Uint8Array(31), field('a', '1'))).toThrow();
      expect(() => computeFieldLeaf(new Uint8Array(33), field('a', '1'))).toThrow();
    });

    test('wire-format KAT pin — fixed input produces a stable hash', () => {
      // Locks the leaf-hash preimage shape. Changing this hash means
      // the wire format changed; downstream-stored field trees are
      // invalidated.
      const fpBytes = new Uint8Array(32); // all zeros
      const f: FieldLeaf = {
        label: 'amount',
        value: new TextEncoder().encode('100'),
      };
      const leaf = computeFieldLeaf(fpBytes, f);
      // Computed from this code's exact preimage shape:
      //   "VARP" || 0x01 || varint(22) || "semantos.field-tree/v1"
      //   || varint(32) || 32x00 || varint(6) || "amount"
      //   || varint(3) || "100"
      // (pinned after first run)
      expect(hex(leaf)).toBe(
        '57874a7e1c5bfb21e0e25614c60e7954678466faa571bb57839ccbc8775f3734',
      );
    });
  });

  describe('buildFieldTree', () => {
    test('produces a 32B root with sorted fields', () => {
      const tree = buildFieldTree(fp(1), [
        field('amount', '500'),
        field('currency', 'GBP'),
        field('memo', 'invoice 7'),
      ]);
      expect(tree.root.byteLength).toBe(32);
      expect(tree.leafCount).toBe(3);
      // Sorted lex ascending by label
      expect(tree.fields.map(f => f.label)).toEqual(['amount', 'currency', 'memo']);
    });

    test('same field set in different submission order → same root', () => {
      const a = buildFieldTree(fp(1), [
        field('amount', '500'),
        field('currency', 'GBP'),
        field('memo', 'invoice 7'),
      ]);
      const b = buildFieldTree(fp(1), [
        field('memo', 'invoice 7'),
        field('amount', '500'),
        field('currency', 'GBP'),
      ]);
      expect(hex(a.root)).toBe(hex(b.root));
    });

    test('different schema → different root for same fields', () => {
      const fields = [field('a', '1'), field('b', '2')];
      const a = buildFieldTree(fp(1), fields);
      const b = buildFieldTree(fp(2), fields);
      expect(hex(a.root)).not.toBe(hex(b.root));
    });

    test('rejects duplicate labels', () => {
      expect(() =>
        buildFieldTree(fp(1), [field('a', '1'), field('a', '2')]),
      ).toThrow('duplicate label');
    });

    test('rejects empty field set', () => {
      expect(() => buildFieldTree(fp(1), [])).toThrow('non-empty');
    });

    test('single-field tree: root === leaf hash', () => {
      const f = field('only', 'one');
      const tree = buildFieldTree(fp(1), [f]);
      const leaf = computeFieldLeaf(fp(1), f);
      expect(hex(tree.root)).toBe(hex(leaf));
    });

    test('odd-leaf-count trees handle the duplicate-last rule', () => {
      // 3 leaves → level 1 has 2 nodes (pair[0,1] + pair[2,2])
      // → root from those 2.
      const tree3 = buildFieldTree(fp(1), [
        field('a', '1'),
        field('b', '2'),
        field('c', '3'),
      ]);
      expect(tree3.root.byteLength).toBe(32);
      // 5 leaves → level1 has 3 → level2 has 2 → root.
      const tree5 = buildFieldTree(fp(1), [
        field('a', '1'),
        field('b', '2'),
        field('c', '3'),
        field('d', '4'),
        field('e', '5'),
      ]);
      expect(tree5.root.byteLength).toBe(32);
    });
  });

  describe('discloseField + verifyFieldDisclosure (round-trip)', () => {
    const fields = [
      field('amount', '500'),
      field('currency', 'GBP'),
      field('memo', 'invoice 7'),
      field('vat', '100'),
      field('total', '600'),
    ];

    test('disclosure proof verifies against the tree root', () => {
      const tree = buildFieldTree(fp(1), fields);
      const proof = discloseField(fp(1), fields, 'vat');
      expect(verifyFieldDisclosure(proof, tree.root)).toBe(true);
    });

    test('every field can be individually disclosed + verified', () => {
      const tree = buildFieldTree(fp(1), fields);
      for (const f of fields) {
        const proof = discloseField(fp(1), fields, f.label);
        expect(verifyFieldDisclosure(proof, tree.root)).toBe(true);
        // The proof carries only this field's value, not the others
        expect(new TextDecoder().decode(proof.value)).toBe(
          new TextDecoder().decode(f.value),
        );
      }
    });

    test('disclosing a non-existent field throws', () => {
      expect(() => discloseField(fp(1), fields, 'nonexistent')).toThrow();
    });
  });

  describe('verifyFieldDisclosure — fail-closed', () => {
    const fields = [field('amount', '500'), field('currency', 'GBP'), field('memo', 'inv')];

    test('rejects when expectedRoot differs', () => {
      const tree = buildFieldTree(fp(1), fields);
      const proof = discloseField(fp(1), fields, 'amount');
      const wrongRoot = new Uint8Array(32).fill(0xFF);
      expect(verifyFieldDisclosure(proof, wrongRoot)).toBe(false);
      // proof.root itself is correct, but expectedRoot is the trust input
      expect(verifyFieldDisclosure(proof, tree.root)).toBe(true);
    });

    test('rejects when proof.value has been swapped (commitment mismatch)', () => {
      const tree = buildFieldTree(fp(1), fields);
      const proof = discloseField(fp(1), fields, 'amount');
      const tampered = {
        ...proof,
        value: new TextEncoder().encode('999'), // attacker substitutes
      };
      expect(verifyFieldDisclosure(tampered, tree.root)).toBe(false);
    });

    test('rejects when proof.label has been swapped (commitment mismatch)', () => {
      const tree = buildFieldTree(fp(1), fields);
      const proof = discloseField(fp(1), fields, 'amount');
      const tampered = { ...proof, label: 'currency' };
      expect(verifyFieldDisclosure(tampered, tree.root)).toBe(false);
    });

    test('rejects when sibling hashes are tampered', () => {
      const tree = buildFieldTree(fp(1), fields);
      const proof = discloseField(fp(1), fields, 'amount');
      const tamperedSiblings = proof.siblings.map((s, i) =>
        i === 0 ? { hash: new Uint8Array(32).fill(0xEE), position: s.position } : s,
      );
      const tampered = { ...proof, siblings: tamperedSiblings };
      expect(verifyFieldDisclosure(tampered, tree.root)).toBe(false);
    });

    test('rejects when schema fingerprint is swapped', () => {
      const tree = buildFieldTree(fp(1), fields);
      const proof = discloseField(fp(1), fields, 'amount');
      const tampered = { ...proof, schemaFingerprint: fp(2) };
      expect(verifyFieldDisclosure(tampered, tree.root)).toBe(false);
    });
  });

  describe('selective disclosure preserves privacy of other fields', () => {
    test('disclosure proof for one field does not leak the others by value', () => {
      // Two trees with identical structure for two of three fields, but
      // a DIFFERENT value for the third. A disclosure proof for one of
      // the unchanged fields should verify against both trees' roots
      // ONLY IF the trees have the same root — but the roots differ
      // because the third field differs. So a verifier holding the
      // disclosed (amount, 500) + the trusted root can confirm
      // membership without ever seeing the memo's value.
      const fieldsA = [field('amount', '500'), field('currency', 'GBP'), field('memo', 'A')];
      const fieldsB = [field('amount', '500'), field('currency', 'GBP'), field('memo', 'B')];
      const treeA = buildFieldTree(fp(1), fieldsA);
      const treeB = buildFieldTree(fp(1), fieldsB);
      // Different roots because memo differs
      expect(hex(treeA.root)).not.toBe(hex(treeB.root));
      // Disclose amount from A
      const proofA = discloseField(fp(1), fieldsA, 'amount');
      // Verifies against A's root, not B's
      expect(verifyFieldDisclosure(proofA, treeA.root)).toBe(true);
      expect(verifyFieldDisclosure(proofA, treeB.root)).toBe(false);
      // The proof body itself never contains 'A' or 'B' (the memo value)
      const proofJson = JSON.stringify(proofA, (_k, v) =>
        v instanceof Uint8Array ? hex(v) : v,
      );
      expect(proofJson).not.toContain('"A"');
      expect(proofJson).not.toContain('"B"');
    });
  });
});

```
