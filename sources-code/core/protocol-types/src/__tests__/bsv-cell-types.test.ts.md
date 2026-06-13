---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/__tests__/bsv-cell-types.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.885613+00:00
---

# core/protocol-types/src/__tests__/bsv-cell-types.test.ts

```ts
/**
 * Catalog tests for `BsvCellTypeName` + `BsvTransformEdges` after PR-6
 * lands the partial-tx state-machine cell-type group.
 *
 * The actual typeHash bytes for each name come from the cartridge.json
 * triples at boot — these tests cover the JS/TS-side catalog only.
 */

import { describe, it, expect } from "@jest/globals";

import {
  BsvCellTypeName,
  BSV_CELL_TYPE_NAMES,
  BsvTransformEdges,
  isBsvTransform,
} from "../bsv/cell-types";

describe("BsvCellTypeName catalog after PR-6", () => {
  it("exposes every partial-tx state-machine name", () => {
    expect(BsvCellTypeName.PARTIAL_SHELL).toBe("bsv.tx.partial.shell");
    expect(BsvCellTypeName.PARTIAL_CONTRIBUTION).toBe(
      "bsv.tx.partial.contribution",
    );
    expect(BsvCellTypeName.PARTIAL_ASSEMBLE).toBe("bsv.tx.partial.assemble");
    expect(BsvCellTypeName.PARTIAL_CANCEL).toBe("bsv.tx.partial.cancel");
  });

  it("exposes the sign request/response pair", () => {
    expect(BsvCellTypeName.TX_SIGN_REQUEST).toBe("bsv.tx.sign.request");
    expect(BsvCellTypeName.TX_SIGN_RESPONSE).toBe("bsv.tx.sign.response");
  });

  it("exposes the assemble/broadcast trigger + result names", () => {
    expect(BsvCellTypeName.TX_ASSEMBLE_INTENT).toBe("bsv.tx.assemble.intent");
    expect(BsvCellTypeName.TX_BROADCAST_INTENT).toBe(
      "bsv.tx.broadcast.intent",
    );
    expect(BsvCellTypeName.TX_BROADCAST_RESULT).toBe(
      "bsv.tx.broadcast.result",
    );
  });

  it("retains pre-PR-6 names (catalog is append-only)", () => {
    expect(BsvCellTypeName.SPV_VERIFY_INTENT).toBe("bsv.spv.verify.intent");
    expect(BsvCellTypeName.LINEAR_ANCHOR).toBe("bsv.linear.anchor");
    expect(BsvCellTypeName.BEEF_CARRIAGE_HEAD).toBe("bsv.beef.carriage.head");
  });

  it("has 6 pre-PR-6 + 9 PR-6 = 15 names total", () => {
    // SPV intent + result (2), linear anchor + status (2), beef head + body (2)
    // = 6 pre. Partial-tx (4) + sign pair (2) + assemble + broadcast intent
    // + broadcast result (3) = 9 added.
    expect(BSV_CELL_TYPE_NAMES.length).toBe(15);
  });

  it("has no duplicate names", () => {
    const seen = new Set<string>();
    for (const n of BSV_CELL_TYPE_NAMES) {
      expect(seen.has(n)).toBe(false);
      seen.add(n);
    }
  });
});

describe("BsvTransformEdges after PR-6", () => {
  it("shell → shell (contribution-walk: handler emits successor LINEAR shell)", () => {
    expect(
      isBsvTransform(BsvCellTypeName.PARTIAL_SHELL, BsvCellTypeName.PARTIAL_SHELL),
    ).toBe(true);
  });

  it("shell → assemble.intent", () => {
    expect(
      isBsvTransform(
        BsvCellTypeName.PARTIAL_SHELL,
        BsvCellTypeName.TX_ASSEMBLE_INTENT,
      ),
    ).toBe(true);
  });

  it("sign.request → sign.response (reachability edge)", () => {
    expect(
      isBsvTransform(
        BsvCellTypeName.TX_SIGN_REQUEST,
        BsvCellTypeName.TX_SIGN_RESPONSE,
      ),
    ).toBe(true);
  });

  it("assemble.intent → broadcast.intent", () => {
    expect(
      isBsvTransform(
        BsvCellTypeName.TX_ASSEMBLE_INTENT,
        BsvCellTypeName.TX_BROADCAST_INTENT,
      ),
    ).toBe(true);
  });

  it("broadcast.intent → broadcast.result", () => {
    expect(
      isBsvTransform(
        BsvCellTypeName.TX_BROADCAST_INTENT,
        BsvCellTypeName.TX_BROADCAST_RESULT,
      ),
    ).toBe(true);
  });

  it("does NOT include shell → cancel as a forward transform (cancel is terminal)", () => {
    // Cancel doesn't emit a successor cell — it just transitions the
    // shell to status=Cancelled. The edge is shell-internal status
    // change, not a directed type-to-type transform.
    expect(
      isBsvTransform(
        BsvCellTypeName.PARTIAL_SHELL,
        BsvCellTypeName.PARTIAL_CANCEL,
      ),
    ).toBe(false);
  });

  it("rejects unrelated pairs", () => {
    expect(
      isBsvTransform(
        BsvCellTypeName.SPV_VERIFY_INTENT,
        BsvCellTypeName.PARTIAL_SHELL,
      ),
    ).toBe(false);
  });
});

```
