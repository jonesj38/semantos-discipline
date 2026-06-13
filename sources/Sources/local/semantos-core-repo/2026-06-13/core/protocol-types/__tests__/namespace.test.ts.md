---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/namespace.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.855903+00:00
---

# core/protocol-types/__tests__/namespace.test.ts

```ts
/**
 * Namespace partition tests — verifies the §8 Q2 three-tier partition
 * implementation in `src/namespace.ts`.
 *
 * Per `docs/audits/2026-05-13-namespace-partition-vs-brc43-brc123.md`
 * Recommendation 1.
 */

import { describe, test, expect } from "bun:test";
import {
  PLEXUS_RESERVED_MAX,
  EXTENDED_PLEXUS_MAX,
  OPERATOR_BASE,
  UINT32_MAX,
  isPlexusReserved,
  isExtendedPlexus,
  isOperatorSovereign,
  isValidNamespaceFlag,
  namespaceTier,
} from "../src/namespace";

describe("tier boundary constants", () => {
  test("PLEXUS_RESERVED_MAX is 0x000000ff", () => {
    expect(PLEXUS_RESERVED_MAX).toBe(0x000000ff);
  });

  test("EXTENDED_PLEXUS_MAX is 0x0000ffff", () => {
    expect(EXTENDED_PLEXUS_MAX).toBe(0x0000ffff);
  });

  test("OPERATOR_BASE is 0x00010000", () => {
    expect(OPERATOR_BASE).toBe(0x00010000);
  });

  test("UINT32_MAX is 0xffffffff", () => {
    expect(UINT32_MAX).toBe(0xffffffff);
  });

  test("tier boundaries are contiguous (no gaps)", () => {
    expect(PLEXUS_RESERVED_MAX + 1).toBe(0x00000100);
    expect(EXTENDED_PLEXUS_MAX + 1).toBe(OPERATOR_BASE);
  });
});

describe("isPlexusReserved (Tier 1)", () => {
  test("accepts canonical Plexus flag values", () => {
    // From core/plexus-contracts/src/domain-flags.ts PlexusStandardFlags
    expect(isPlexusReserved(0x01)).toBe(true); // EDGE_CREATION
    expect(isPlexusReserved(0x05)).toBe(true); // ATTESTATION
    expect(isPlexusReserved(0x0a)).toBe(true); // METERING
    expect(isPlexusReserved(0x0b)).toBe(true); // ZONE_KEY / EXPERIENCE (§8 Q1)
    expect(isPlexusReserved(0x0c)).toBe(true); // MESSAGING
    expect(isPlexusReserved(0x0d)).toBe(true); // HOST_EXEC
  });

  test("accepts boundary values 1 and 0xFF", () => {
    expect(isPlexusReserved(1)).toBe(true);
    expect(isPlexusReserved(0xff)).toBe(true);
  });

  test("rejects 0 (reserved as null/sentinel)", () => {
    expect(isPlexusReserved(0)).toBe(false);
  });

  test("rejects values above 0xFF", () => {
    expect(isPlexusReserved(0x100)).toBe(false);
    expect(isPlexusReserved(0x10000)).toBe(false);
  });

  test("rejects negative numbers and non-integers", () => {
    expect(isPlexusReserved(-1)).toBe(false);
    expect(isPlexusReserved(1.5)).toBe(false);
    expect(isPlexusReserved(NaN)).toBe(false);
  });
});

describe("isExtendedPlexus (Tier 2)", () => {
  test("accepts boundary values 0x100 and 0xFFFF", () => {
    expect(isExtendedPlexus(0x100)).toBe(true);
    expect(isExtendedPlexus(0xffff)).toBe(true);
  });

  test("accepts a mid-range value", () => {
    expect(isExtendedPlexus(0x1000)).toBe(true);
  });

  test("rejects Tier 1 values", () => {
    expect(isExtendedPlexus(0xff)).toBe(false);
    expect(isExtendedPlexus(1)).toBe(false);
  });

  test("rejects Tier 3 values", () => {
    expect(isExtendedPlexus(0x10000)).toBe(false);
    expect(isExtendedPlexus(0xffffffff)).toBe(false);
  });

  test("Tier 2 is empty in current code (per GD9 audit)", () => {
    // This is informational: no shipped flag currently lives in Tier 2.
    // If a Plexus flag is added in the range 0x100–0xFFFF, this test
    // documents that it's a Tier 2 value (which is allowed but worth
    // noticing during review).
    expect(isExtendedPlexus(0x100)).toBe(true); // would be the first Tier 2 flag
  });
});

describe("isOperatorSovereign (Tier 3)", () => {
  test("accepts canonical client flag values", () => {
    // From core/plexus-contracts/src/domain-flags.ts ClientDomainFlags
    expect(isOperatorSovereign(0x00010001)).toBe(true); // VIEW
    expect(isOperatorSovereign(0x00010002)).toBe(true); // CREATE
    expect(isOperatorSovereign(0x0001000b)).toBe(true); // HOST_EXEC (client-side)
  });

  test("accepts agent-context default (0x00020001)", () => {
    expect(isOperatorSovereign(0x00020001)).toBe(true);
  });

  test("accepts boundary values 0x10000 and 0xFFFFFFFF", () => {
    expect(isOperatorSovereign(0x00010000)).toBe(true);
    expect(isOperatorSovereign(0xffffffff)).toBe(true);
  });

  test("rejects Tier 1 and Tier 2 values", () => {
    expect(isOperatorSovereign(0x01)).toBe(false);
    expect(isOperatorSovereign(0x0c)).toBe(false);
    expect(isOperatorSovereign(0xff)).toBe(false);
    expect(isOperatorSovereign(0x100)).toBe(false);
    expect(isOperatorSovereign(0xffff)).toBe(false);
  });

  test("rejects values above UINT32_MAX", () => {
    expect(isOperatorSovereign(0x1_00000000)).toBe(false);
  });
});

describe("namespaceTier (composite classifier)", () => {
  test("classifies Tier 1 values as plexus", () => {
    expect(namespaceTier(0x01)).toBe("plexus");
    expect(namespaceTier(0xff)).toBe("plexus");
  });

  test("classifies Tier 2 values as extended", () => {
    expect(namespaceTier(0x100)).toBe("extended");
    expect(namespaceTier(0xffff)).toBe("extended");
  });

  test("classifies Tier 3 values as operator", () => {
    expect(namespaceTier(0x10000)).toBe("operator");
    expect(namespaceTier(0xffffffff)).toBe("operator");
  });

  test("classifies 0 and out-of-range as invalid", () => {
    expect(namespaceTier(0)).toBe("invalid");
    expect(namespaceTier(-1)).toBe("invalid");
    expect(namespaceTier(0x1_00000000)).toBe("invalid");
  });

  test("classifies non-integers as invalid", () => {
    expect(namespaceTier(1.5)).toBe("invalid");
    expect(namespaceTier(NaN)).toBe("invalid");
    expect(namespaceTier(Infinity)).toBe("invalid");
  });

  test("predicates are mutually exclusive for every valid flag", () => {
    const samples = [
      0x01, 0x05, 0x0a, 0x0d, 0xff,           // Tier 1
      0x100, 0x500, 0x1000, 0xffff,           // Tier 2
      0x10000, 0x20001, 0xff000000, 0xffffffff, // Tier 3
    ];
    for (const v of samples) {
      const flags = [
        isPlexusReserved(v),
        isExtendedPlexus(v),
        isOperatorSovereign(v),
      ];
      // Exactly one should be true.
      expect(flags.filter(Boolean).length).toBe(1);
    }
  });
});

describe("isValidNamespaceFlag", () => {
  test("accepts every Tier 1/2/3 value", () => {
    expect(isValidNamespaceFlag(0x01)).toBe(true);
    expect(isValidNamespaceFlag(0x100)).toBe(true);
    expect(isValidNamespaceFlag(0x10000)).toBe(true);
    expect(isValidNamespaceFlag(0xffffffff)).toBe(true);
  });

  test("rejects 0 and out-of-range", () => {
    expect(isValidNamespaceFlag(0)).toBe(false);
    expect(isValidNamespaceFlag(-1)).toBe(false);
    expect(isValidNamespaceFlag(0x1_00000000)).toBe(false);
    expect(isValidNamespaceFlag(NaN)).toBe(false);
  });
});

describe("compatibility with existing domain-flags.ts", () => {
  // The existing core/plexus-contracts/src/domain-flags.ts uses
  // PLEXUS_RESERVED_MAX = 0x0000ffff (two-tier collapse). This module
  // uses PLEXUS_RESERVED_MAX = 0x000000ff (three-tier split). Document
  // the relationship:
  //
  // - This module's EXTENDED_PLEXUS_MAX (0xFFFF) equals the existing
  //   PLEXUS_RESERVED_MAX from domain-flags.ts. Code that uses the
  //   existing constant as an "upper bound for any Plexus flag" can
  //   migrate to EXTENDED_PLEXUS_MAX with no semantic change.
  // - This module's OPERATOR_BASE (0x10000) equals the existing
  //   CLIENT_BASE from domain-flags.ts. Direct equivalence.

  test("EXTENDED_PLEXUS_MAX equals legacy two-tier PLEXUS_RESERVED_MAX", () => {
    expect(EXTENDED_PLEXUS_MAX).toBe(0x0000ffff);
  });

  test("OPERATOR_BASE equals legacy CLIENT_BASE", () => {
    expect(OPERATOR_BASE).toBe(0x00010000);
  });

  test("every current Plexus flag still lives in Tier 1", () => {
    // From domain-flags.ts PlexusStandardFlags
    const plexusFlags = [0x01, 0x05, 0x0a, 0x0b, 0x0c, 0x0d];
    for (const f of plexusFlags) {
      expect(namespaceTier(f)).toBe("plexus");
    }
  });

  test("every current Client flag still lives in Tier 3", () => {
    // From domain-flags.ts ClientDomainFlags
    const clientFlags = [
      0x00010001, 0x00010002, 0x00010003, 0x00010004,
      0x00010005, 0x00010006, 0x00010007, 0x00010008,
      0x00010009, 0x0001000a, 0x0001000b,
    ];
    for (const f of clientFlags) {
      expect(namespaceTier(f)).toBe("operator");
    }
  });
});

```
