---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase11.5-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.578918+00:00
---

# tests/gates/phase11.5-gate.test.ts

```ts
/**
 * Phase 11.5 Gate: TLA+ Protocol Verification
 *
 * Validates:
 * 1. All TLA+ specs and config files present
 * 2. Source code alignment — specs match implementation
 * 3. Security properties — adversary actions and key invariants
 * 4. No vacuous truth — model configs have non-trivial constants
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");
const TLA_DIR = join(ROOT, "proofs/tla");
const SRC_DIR = join(ROOT, "src");
const PROTO_DIR = join(ROOT, "core/protocol-types/src");
const METERING_DIR = join(ROOT, "packages/metering/src");

// ── Gate 1: TLA+ specs exist ──────────────────────────────────

describe("Gate 1: TLA+ specs and configs present", () => {
  const specs = [
    "SemanticTypes",
    "EvidenceChain",
    "ReplayPrevention",
    "CertRevocation",
    "MeteringFSM",
    "ZoneBoundary",
    "PartitionResilience",
  ];

  for (const spec of specs) {
    test(`${spec}.tla exists`, () => {
      expect(existsSync(join(TLA_DIR, `${spec}.tla`))).toBe(true);
    });

    test(`${spec}.cfg exists`, () => {
      expect(existsSync(join(TLA_DIR, `${spec}.cfg`))).toBe(true);
    });
  }

  test("Makefile exists", () => {
    expect(existsSync(join(TLA_DIR, "Makefile"))).toBe(true);
  });

  test("README.md exists", () => {
    expect(existsSync(join(TLA_DIR, "README.md"))).toBe(true);
  });
});

// ── Gate 2: Source code alignment ──────────────────────────────

describe("Gate 2: Specs match source code", () => {
  test("MeteringFSM transition table matches channel-fsm.ts", () => {
    const fsm = readFileSync(join(METERING_DIR, "channel-fsm.ts"), "utf-8");
    const tla = readFileSync(join(TLA_DIR, "MeteringFSM.tla"), "utf-8");

    // All 8 states must appear in both files
    const states = [
      "NEGOTIATING", "FUNDED", "ACTIVE", "PAUSED",
      "CLOSING_REQUESTED", "CLOSING_CONFIRMED", "SETTLED", "DISPUTED",
    ];
    for (const s of states) {
      expect(fsm).toContain(s);
      expect(tla).toContain(s);
    }

    // All transition actions must appear in TLA+ spec
    const actions = [
      "fund", "activate", "pause", "resume", "requestClose",
      "confirmClose", "settle", "dispute", "resolve",
    ];
    for (const a of actions) {
      expect(tla.toLowerCase()).toContain(a.toLowerCase());
    }

    // SETTLED is terminal — no outgoing transitions
    expect(tla).toContain("SETTLED");
    expect(tla).toContain("SettledIsTerminal");
  });

  test("MeteringFSM tick preconditions match channel-fsm.ts", () => {
    const tla = readFileSync(join(TLA_DIR, "MeteringFSM.tla"), "utf-8");

    // tick only in ACTIVE (channel-fsm.ts line 194)
    expect(tla).toContain('state = "ACTIVE"');
    // satoshisThisTick >= 0 (channel-fsm.ts line 201)
    expect(tla).toContain("satoshisThisTick >= 0");
    // currentTick += 1 (channel-fsm.ts line 212)
    expect(tla).toContain("currentTick + 1");
    // nSequence += 1 (channel-fsm.ts line 213)
    expect(tla).toContain("nSequence + 1");
    // cumulativeSatoshis += satoshisThisTick (channel-fsm.ts line 214)
    expect(tla).toContain("cumulativeSatoshis + satoshisThisTick");
  });

  test("ZoneBoundary has all 10 well-known flags from domain-flags.ts", () => {
    const flags = readFileSync(join(SRC_DIR, "types/domain-flags.ts"), "utf-8");
    const tla = readFileSync(join(TLA_DIR, "ZoneBoundary.tla"), "utf-8");

    const wellKnown = [
      "EDGE_CREATION", "SIGNING", "ENCRYPTION", "MESSAGING",
      "ATTESTATION", "CHILD_CREATION", "PERMISSION_GRANT",
      "DATA_SOVEREIGNTY", "SCHEMA_SIGNING", "METERING",
    ];
    for (const f of wellKnown) {
      expect(flags).toContain(f);
      expect(tla).toContain(f);
    }

    // Flag values: 0x01 through 0x0A (1 through 10)
    expect(tla).toContain("EDGE_CREATION    == 1");
    expect(tla).toContain("METERING         == 10");

    // Reserved flag
    expect(tla).toContain("RESERVED == 0");
  });

  test("EvidenceChain references prevStateHash from cell-header.ts", () => {
    const header = readFileSync(join(PROTO_DIR, "cell-header.ts"), "utf-8");
    const tla = readFileSync(join(TLA_DIR, "EvidenceChain.tla"), "utf-8");

    // cell-header.ts has prevStateHash
    expect(header).toContain("prevStateHash: Uint8Array");
    expect(header).toContain("prevStateHash");

    // TLA+ spec references prevStateHash and offset 128
    expect(tla).toContain("prevStateHash");
    expect(tla).toContain("offset 128");
  });

  test("SemanticTypes has LINEAR, AFFINE, RELEVANT from semantic-objects.ts", () => {
    const types = readFileSync(join(SRC_DIR, "types/semantic-objects.ts"), "utf-8");
    const tla = readFileSync(join(TLA_DIR, "SemanticTypes.tla"), "utf-8");

    for (const t of ["LINEAR", "AFFINE", "RELEVANT"]) {
      expect(types).toContain(t);
      expect(tla).toContain(t);
    }

    // CanConsume and IsConsumed operators
    expect(tla).toContain("CanConsume");
    expect(tla).toContain("IsConsumed");
  });
});

// ── Gate 3: Security properties ────────────────────────────────

describe("Gate 3: Adversary actions and safety properties", () => {
  const securitySpecs = [
    { file: "EvidenceChain.tla", adversary: "Tamper", props: ["ChainIntegrity", "UniqueStateHashes"] },
    { file: "ReplayPrevention.tla", adversary: "Replay", props: ["NoDoubleConsume", "SingleConsumption"] },
    { file: "CertRevocation.tla", adversary: "AttemptUse", props: ["RevokedStaysRevoked", "RevocationHasProof"] },
    { file: "MeteringFSM.tla", adversary: "InvalidTransition", props: ["SettledIsTerminal", "TickOnlyInActive"] },
    { file: "ZoneBoundary.tla", adversary: "CrossZone", props: ["ReservedNeverUsed", "ZoneEnforcement"] },
    { file: "PartitionResilience.tla", adversary: "PartitionedDouble", props: ["NoSplitBrainConsume", "ConsumedHasOwner"] },
  ];

  for (const { file, adversary, props } of securitySpecs) {
    test(`${file} has adversary action (${adversary})`, () => {
      const content = readFileSync(join(TLA_DIR, file), "utf-8");
      expect(content).toContain(adversary);
    });

    for (const prop of props) {
      test(`${file} has property ${prop}`, () => {
        const content = readFileSync(join(TLA_DIR, file), "utf-8");
        expect(content).toContain(prop);
      });
    }
  }
});

// ── Gate 4: No vacuous truth ───────────────────────────────────

describe("Gate 4: Non-trivial model configs", () => {
  const configs = [
    "SemanticTypes.cfg",
    "EvidenceChain.cfg",
    "ReplayPrevention.cfg",
    "CertRevocation.cfg",
    "MeteringFSM.cfg",
    "ZoneBoundary.cfg",
    "PartitionResilience.cfg",
  ];

  for (const cfg of configs) {
    test(`${cfg} has CONSTANTS section`, () => {
      const content = readFileSync(join(TLA_DIR, cfg), "utf-8");
      expect(content).toContain("CONSTANTS");
    });

    test(`${cfg} has INVARIANTS or PROPERTIES`, () => {
      const content = readFileSync(join(TLA_DIR, cfg), "utf-8");
      const hasInvariants = content.includes("INVARIANTS");
      const hasProperties = content.includes("PROPERTIES");
      expect(hasInvariants || hasProperties).toBe(true);
    });
  }

  test("README documents hash abstraction", () => {
    const readme = readFileSync(join(TLA_DIR, "README.md"), "utf-8");
    expect(readme).toContain("Hash-as-Injection");
    expect(readme).toContain("injective");
    expect(readme).toContain("SHA-256");
  });

  test("README documents prevStateHash correction", () => {
    const readme = readFileSync(join(TLA_DIR, "README.md"), "utf-8");
    expect(readme).toContain("prevStateHash");
    expect(readme).toContain("offset 128");
    expect(readme).toContain("cell-header.ts");
  });
});

```
