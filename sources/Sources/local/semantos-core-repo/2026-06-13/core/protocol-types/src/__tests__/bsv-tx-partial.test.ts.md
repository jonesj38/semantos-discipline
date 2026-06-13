---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/__tests__/bsv-tx-partial.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.884165+00:00
---

# core/protocol-types/src/__tests__/bsv-tx-partial.test.ts

```ts
/**
 * Unit tests for the `bsv.tx.partial.*` wire formats (PR-6 of
 * LOCKSCRIPT-CLEAVAGE.md §6.3 + §8.3).
 *
 * Pinpoints:
 *   1. round-trip identity (encode-then-decode is identity, all four shapes)
 *   2. boundary checks (MAX_COUNTERPARTIES, MAX_INLINE_SIG_BYTES, K ≤ N)
 *   3. strict enum validation (unknown status / cancel reason rejected)
 *   4. wire-byte layout assertions (VERSION at offset 0, etc.)
 *   5. error paths (truncated payload, wrong-length fields)
 */

import { describe, it, expect } from "@jest/globals";

import {
  TX_PARTIAL_WIRE_VERSION,
  MAX_COUNTERPARTIES,
  MAX_INLINE_SIG_BYTES,
  HASH160_BYTES,
  COMPRESSED_PUBKEY_BYTES,
  CELL_HASH_BYTES,
  WORKFLOW_ID_BYTES,
  PartialShellStatus,
  PartialCancelReason,
  PARTIAL_CONTRIBUTION_PREFIX_BYTES,
  PARTIAL_ASSEMBLE_BYTES,
  PARTIAL_CANCEL_BYTES,
  encodePartialShell,
  decodePartialShell,
  encodePartialContribution,
  decodePartialContribution,
  encodePartialAssemble,
  decodePartialAssemble,
  encodePartialCancel,
  decodePartialCancel,
  type PartialShell,
} from "../bsv/tx-partial";

function makeBytes(n: number, seed = 0): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 17 + seed) & 0xff;
  return b;
}

// ─────────────────────────── Shell ────────────────────────────────────

describe("bsv.tx.partial.shell — round-trip", () => {
  it("round-trips a 3-party shell with 0 contributions", () => {
    const shell: PartialShell = {
      workflowId: makeBytes(WORKFLOW_ID_BYTES, 1),
      counterpartyHash160s: [
        makeBytes(HASH160_BYTES, 10),
        makeBytes(HASH160_BYTES, 20),
        makeBytes(HASH160_BYTES, 30),
      ],
      contributions: [],
      status: PartialShellStatus.Active,
    };
    const wire = encodePartialShell(shell);
    const decoded = decodePartialShell(wire);
    expect(decoded.workflowId).toEqual(shell.workflowId);
    expect(decoded.counterpartyHash160s.length).toBe(3);
    for (let i = 0; i < 3; i++) {
      expect(decoded.counterpartyHash160s[i]).toEqual(
        shell.counterpartyHash160s[i],
      );
    }
    expect(decoded.contributions.length).toBe(0);
    expect(decoded.status).toBe(PartialShellStatus.Active);
  });

  it("round-trips a 3-party shell with 2 contributions", () => {
    const shell: PartialShell = {
      workflowId: makeBytes(WORKFLOW_ID_BYTES, 2),
      counterpartyHash160s: [
        makeBytes(HASH160_BYTES, 100),
        makeBytes(HASH160_BYTES, 200),
        makeBytes(HASH160_BYTES, 250),
      ],
      contributions: [
        { partyIndex: 0, contributionCellHash: makeBytes(CELL_HASH_BYTES, 11) },
        { partyIndex: 2, contributionCellHash: makeBytes(CELL_HASH_BYTES, 22) },
      ],
      status: PartialShellStatus.Active,
    };
    const wire = encodePartialShell(shell);
    const decoded = decodePartialShell(wire);
    expect(decoded.contributions.length).toBe(2);
    expect(decoded.contributions[0].partyIndex).toBe(0);
    expect(decoded.contributions[0].contributionCellHash).toEqual(
      shell.contributions[0].contributionCellHash,
    );
    expect(decoded.contributions[1].partyIndex).toBe(2);
    expect(decoded.status).toBe(PartialShellStatus.Active);
  });

  it("round-trips a fully-collected shell at MAX_COUNTERPARTIES", () => {
    const counterpartyHash160s: Uint8Array[] = [];
    const contributions: PartialShell["contributions"][number][] = [];
    for (let i = 0; i < MAX_COUNTERPARTIES; i++) {
      counterpartyHash160s.push(makeBytes(HASH160_BYTES, i));
      contributions.push({
        partyIndex: i,
        contributionCellHash: makeBytes(CELL_HASH_BYTES, 1000 + i),
      });
    }
    const shell: PartialShell = {
      workflowId: makeBytes(WORKFLOW_ID_BYTES, 3),
      counterpartyHash160s,
      contributions,
      status: PartialShellStatus.BroadcastPending,
    };
    const wire = encodePartialShell(shell);
    // Cell payload budget = 1024 - header ≈ 962. At N=K=16 the encoded
    // shell should be 24 + 320 + 528 = 872 bytes, comfortably under.
    expect(wire.length).toBeLessThan(900);
    const decoded = decodePartialShell(wire);
    expect(decoded.counterpartyHash160s.length).toBe(MAX_COUNTERPARTIES);
    expect(decoded.contributions.length).toBe(MAX_COUNTERPARTIES);
    expect(decoded.status).toBe(PartialShellStatus.BroadcastPending);
  });
});

describe("bsv.tx.partial.shell — wire layout", () => {
  it("stamps VERSION at offset 0", () => {
    const wire = encodePartialShell({
      workflowId: makeBytes(WORKFLOW_ID_BYTES),
      counterpartyHash160s: [makeBytes(HASH160_BYTES)],
      contributions: [],
      status: PartialShellStatus.Active,
    });
    expect(wire[0]).toBe(TX_PARTIAL_WIRE_VERSION);
  });

  it("places workflow_id at offsets 1..17", () => {
    const workflowId = makeBytes(WORKFLOW_ID_BYTES, 42);
    const wire = encodePartialShell({
      workflowId,
      counterpartyHash160s: [makeBytes(HASH160_BYTES)],
      contributions: [],
      status: PartialShellStatus.Active,
    });
    expect(wire.slice(1, 1 + WORKFLOW_ID_BYTES)).toEqual(workflowId);
  });

  it("places N at offset 17, then counterparties immediately", () => {
    const h = makeBytes(HASH160_BYTES, 7);
    const wire = encodePartialShell({
      workflowId: makeBytes(WORKFLOW_ID_BYTES),
      counterpartyHash160s: [h],
      contributions: [],
      status: PartialShellStatus.Active,
    });
    expect(wire[17]).toBe(1); // N=1
    expect(wire.slice(18, 18 + HASH160_BYTES)).toEqual(h);
  });

  it("status appears just before the reserved zero byte (tail)", () => {
    const wire = encodePartialShell({
      workflowId: makeBytes(WORKFLOW_ID_BYTES),
      counterpartyHash160s: [makeBytes(HASH160_BYTES)],
      contributions: [],
      status: PartialShellStatus.Cancelled,
    });
    expect(wire[wire.length - 2]).toBe(PartialShellStatus.Cancelled);
    expect(wire[wire.length - 1]).toBe(0);
  });
});

describe("bsv.tx.partial.shell — error paths", () => {
  it("rejects encode with N=0", () => {
    expect(() =>
      encodePartialShell({
        workflowId: makeBytes(WORKFLOW_ID_BYTES),
        counterpartyHash160s: [],
        contributions: [],
        status: PartialShellStatus.Active,
      }),
    ).toThrow(/N must be 1\.\.16/);
  });

  it("rejects encode with N > MAX_COUNTERPARTIES", () => {
    const tooMany = Array.from(
      { length: MAX_COUNTERPARTIES + 1 },
      (_, i) => makeBytes(HASH160_BYTES, i),
    );
    expect(() =>
      encodePartialShell({
        workflowId: makeBytes(WORKFLOW_ID_BYTES),
        counterpartyHash160s: tooMany,
        contributions: [],
        status: PartialShellStatus.Active,
      }),
    ).toThrow(/N must be 1\.\.16/);
  });

  it("rejects encode with K > N", () => {
    expect(() =>
      encodePartialShell({
        workflowId: makeBytes(WORKFLOW_ID_BYTES),
        counterpartyHash160s: [makeBytes(HASH160_BYTES)],
        contributions: [
          { partyIndex: 0, contributionCellHash: makeBytes(CELL_HASH_BYTES) },
          { partyIndex: 0, contributionCellHash: makeBytes(CELL_HASH_BYTES) },
        ],
        status: PartialShellStatus.Active,
      }),
    ).toThrow(/K=2 cannot exceed N=1/);
  });

  it("rejects encode with partyIndex out of [0, N)", () => {
    expect(() =>
      encodePartialShell({
        workflowId: makeBytes(WORKFLOW_ID_BYTES),
        counterpartyHash160s: [
          makeBytes(HASH160_BYTES),
          makeBytes(HASH160_BYTES),
        ],
        contributions: [
          { partyIndex: 5, contributionCellHash: makeBytes(CELL_HASH_BYTES) },
        ],
        status: PartialShellStatus.Active,
      }),
    ).toThrow(/partyIndex=5 out of range/);
  });

  it("rejects encode with a non-WORKFLOW_ID_BYTES workflowId", () => {
    expect(() =>
      encodePartialShell({
        workflowId: makeBytes(8),
        counterpartyHash160s: [makeBytes(HASH160_BYTES)],
        contributions: [],
        status: PartialShellStatus.Active,
      }),
    ).toThrow(/workflowId must be 16 bytes/);
  });

  it("rejects decode of a payload with an unknown status byte", () => {
    const wire = encodePartialShell({
      workflowId: makeBytes(WORKFLOW_ID_BYTES),
      counterpartyHash160s: [makeBytes(HASH160_BYTES)],
      contributions: [],
      status: PartialShellStatus.Active,
    });
    // Status byte sits second-to-last.
    wire[wire.length - 2] = 99;
    expect(() => decodePartialShell(wire)).toThrow(/unknown status=99/);
  });

  it("rejects decode of a payload with non-zero reserved byte", () => {
    const wire = encodePartialShell({
      workflowId: makeBytes(WORKFLOW_ID_BYTES),
      counterpartyHash160s: [makeBytes(HASH160_BYTES)],
      contributions: [],
      status: PartialShellStatus.Active,
    });
    wire[wire.length - 1] = 1;
    expect(() => decodePartialShell(wire)).toThrow(/reserved byte must be 0/);
  });

  it("rejects decode of a truncated payload", () => {
    expect(() => decodePartialShell(new Uint8Array(10))).toThrow(
      /payload too short/,
    );
  });

  it("rejects decode of a payload with wrong VERSION", () => {
    const wire = encodePartialShell({
      workflowId: makeBytes(WORKFLOW_ID_BYTES),
      counterpartyHash160s: [makeBytes(HASH160_BYTES)],
      contributions: [],
      status: PartialShellStatus.Active,
    });
    wire[0] = 2;
    expect(() => decodePartialShell(wire)).toThrow(/unknown VERSION=2/);
  });
});

// ─────────────────────────── Contribution ─────────────────────────────

describe("bsv.tx.partial.contribution — round-trip", () => {
  it("round-trips a typical contribution", () => {
    const c = {
      shellCellHash: makeBytes(CELL_HASH_BYTES, 1),
      partyIndex: 2,
      contributorPubkey: makeBytes(COMPRESSED_PUBKEY_BYTES, 5),
      signature: makeBytes(71, 9), // typical DER+sighash-flag size
    };
    const wire = encodePartialContribution(c);
    expect(wire.length).toBe(PARTIAL_CONTRIBUTION_PREFIX_BYTES + 71);
    const decoded = decodePartialContribution(wire);
    expect(decoded.shellCellHash).toEqual(c.shellCellHash);
    expect(decoded.partyIndex).toBe(c.partyIndex);
    expect(decoded.contributorPubkey).toEqual(c.contributorPubkey);
    expect(decoded.signature).toEqual(c.signature);
  });

  it("round-trips at MAX_INLINE_SIG_BYTES boundary", () => {
    const c = {
      shellCellHash: makeBytes(CELL_HASH_BYTES, 1),
      partyIndex: 0,
      contributorPubkey: makeBytes(COMPRESSED_PUBKEY_BYTES, 2),
      signature: makeBytes(MAX_INLINE_SIG_BYTES, 3),
    };
    const wire = encodePartialContribution(c);
    expect(wire.length).toBe(
      PARTIAL_CONTRIBUTION_PREFIX_BYTES + MAX_INLINE_SIG_BYTES,
    );
    const decoded = decodePartialContribution(wire);
    expect(decoded.signature.length).toBe(MAX_INLINE_SIG_BYTES);
  });
});

describe("bsv.tx.partial.contribution — error paths", () => {
  it("rejects encode with wrong shellCellHash size", () => {
    expect(() =>
      encodePartialContribution({
        shellCellHash: makeBytes(8),
        partyIndex: 0,
        contributorPubkey: makeBytes(COMPRESSED_PUBKEY_BYTES),
        signature: makeBytes(64),
      }),
    ).toThrow(/shellCellHash must be 32 bytes/);
  });

  it("rejects encode with wrong contributorPubkey size", () => {
    expect(() =>
      encodePartialContribution({
        shellCellHash: makeBytes(CELL_HASH_BYTES),
        partyIndex: 0,
        contributorPubkey: makeBytes(20),
        signature: makeBytes(64),
      }),
    ).toThrow(/contributorPubkey must be 33 bytes/);
  });

  it("rejects encode with sig over MAX_INLINE_SIG_BYTES", () => {
    expect(() =>
      encodePartialContribution({
        shellCellHash: makeBytes(CELL_HASH_BYTES),
        partyIndex: 0,
        contributorPubkey: makeBytes(COMPRESSED_PUBKEY_BYTES),
        signature: makeBytes(MAX_INLINE_SIG_BYTES + 1),
      }),
    ).toThrow(/signature length .* out of range/);
  });

  it("rejects encode with empty signature", () => {
    expect(() =>
      encodePartialContribution({
        shellCellHash: makeBytes(CELL_HASH_BYTES),
        partyIndex: 0,
        contributorPubkey: makeBytes(COMPRESSED_PUBKEY_BYTES),
        signature: new Uint8Array(),
      }),
    ).toThrow(/signature length 0 out of range/);
  });

  it("rejects decode of truncated payload", () => {
    expect(() => decodePartialContribution(new Uint8Array(20))).toThrow(
      /payload too short/,
    );
  });
});

// ─────────────────────────── Assemble ─────────────────────────────────

describe("bsv.tx.partial.assemble — round-trip + layout", () => {
  it("round-trips with nLockTime 0", () => {
    const a = { shellCellHash: makeBytes(CELL_HASH_BYTES, 1), nLockTime: 0 };
    const wire = encodePartialAssemble(a);
    expect(wire.length).toBe(PARTIAL_ASSEMBLE_BYTES);
    expect(decodePartialAssemble(wire)).toEqual(a);
  });

  it("round-trips with high nLockTime preserving u32 unsignedness", () => {
    const a = {
      shellCellHash: makeBytes(CELL_HASH_BYTES, 2),
      nLockTime: 0xfeedbeef,
    };
    const wire = encodePartialAssemble(a);
    const decoded = decodePartialAssemble(wire);
    expect(decoded.nLockTime).toBe(0xfeedbeef);
  });

  it("LE-encodes nLockTime at offsets 33..37", () => {
    const wire = encodePartialAssemble({
      shellCellHash: makeBytes(CELL_HASH_BYTES),
      nLockTime: 0x01020304,
    });
    expect(wire[33]).toBe(0x04);
    expect(wire[34]).toBe(0x03);
    expect(wire[35]).toBe(0x02);
    expect(wire[36]).toBe(0x01);
  });

  it("rejects decode of a too-short payload", () => {
    expect(() => decodePartialAssemble(new Uint8Array(20))).toThrow(
      /payload must be ≥ 37 bytes/,
    );
  });
});

// ─────────────────────────── Cancel ───────────────────────────────────

describe("bsv.tx.partial.cancel — round-trip + layout", () => {
  it("round-trips each reason value", () => {
    for (const reason of Object.values(PartialCancelReason) as number[]) {
      const c = {
        shellCellHash: makeBytes(CELL_HASH_BYTES, reason),
        reason: reason as PartialCancelReason,
      };
      const wire = encodePartialCancel(c);
      expect(wire.length).toBe(PARTIAL_CANCEL_BYTES);
      expect(decodePartialCancel(wire)).toEqual(c);
    }
  });

  it("places reason byte at offset 33", () => {
    const wire = encodePartialCancel({
      shellCellHash: makeBytes(CELL_HASH_BYTES),
      reason: PartialCancelReason.TimedOut,
    });
    expect(wire[33]).toBe(PartialCancelReason.TimedOut);
  });

  it("rejects decode of unknown reason value", () => {
    const wire = encodePartialCancel({
      shellCellHash: makeBytes(CELL_HASH_BYTES),
      reason: PartialCancelReason.Unspecified,
    });
    wire[33] = 99;
    expect(() => decodePartialCancel(wire)).toThrow(/unknown reason=99/);
  });
});

```
