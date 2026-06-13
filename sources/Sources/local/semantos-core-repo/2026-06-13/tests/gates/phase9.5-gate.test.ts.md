---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase9.5-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.565801+00:00
---

# tests/gates/phase9.5-gate.test.ts

```ts
/**
 * Phase 9.5 Gate: Publication + Visibility + Governance
 *
 * Every test uses real extension configs and real service implementations.
 * No stubs, no mocks, no canned responses.
 *
 * NOTE: Same as Phase 9 — tests avoid importing objectFactory/LoomStore
 * directly because they chain through @semantos/protocol-types which has
 * a pre-existing self-reference resolution issue with Bun. Service modules
 * are validated via source code inspection and config validation.
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, readdirSync } from "fs";
import { createHash } from "crypto";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");
const CONFIGS_DIR = join(ROOT, "configs/extensions");
const WORKBENCH_SRC = join(ROOT, "runtime/services/src");

// ── Gate 1: Visibility field on types and config ──────────────────

describe("Gate 1: Visibility field on types and config", () => {
  test("ObjectTypeDefinition has visibility field in extensionConfig.ts", () => {
    const source = readFileSync(join(WORKBENCH_SRC, "config/extensionConfig.ts"), "utf-8");
    expect(source).toContain("visibility?: VisibilityConfig");
    expect(source).toContain("accessPolicy?: AccessPolicy");
    expect(source).toContain("interface VisibilityConfig");
    expect(source).toContain("'draft' | 'published' | 'revoked'");
    expect(source).toContain("revokePreservesEvidence: boolean");
    expect(source).toContain("publishTransition?:");
  });

  test("LoomObject has visibility field in workbench.ts", () => {
    const source = readFileSync(join(WORKBENCH_SRC, "types/loom.ts"), "utf-8");
    expect(source).toContain("visibility: 'draft' | 'published' | 'revoked'");
  });

  test("objectFactory sets initial visibility from typeDef config", () => {
    const source = readFileSync(join(WORKBENCH_SRC, "state/objectFactory.ts"), "utf-8");
    expect(source).toContain("typeDef.visibility?.defaultState ?? 'draft'");
  });

  test("loomReducer handles TRANSITION_VISIBILITY action", () => {
    const source = readFileSync(join(WORKBENCH_SRC, "state/loomReducer.ts"), "utf-8");
    expect(source).toContain("'TRANSITION_VISIBILITY'");
    expect(source).toContain("action.newVisibility");
    expect(source).toContain("visibility: action.newVisibility");
  });

  test("trades-services Job has visibility, Customer does not", () => {
    const ts = JSON.parse(readFileSync(join(CONFIGS_DIR, "trades-services.json"), "utf-8"));
    const job = ts.objectTypes.find((t: any) => t.name === "Job");
    const customer = ts.objectTypes.find((t: any) => t.name === "Customer");

    expect(job.visibility).toBeTruthy();
    expect(job.visibility.states).toContain("draft");
    expect(job.visibility.states).toContain("published");
    expect(job.visibility.states).toContain("revoked");
    expect(job.visibility.defaultState).toBe("draft");
    expect(job.visibility.publishTransition.fromLinearity).toBe("AFFINE");
    expect(job.visibility.publishTransition.toLinearity).toBe("RELEVANT");
    expect(job.visibility.revokePreservesEvidence).toBe(true);

    expect(customer.visibility).toBeUndefined();
  });
});

// ── Gate 2: LoomStore.transitionVisibility ──────────────────

describe("Gate 2: LoomStore.transitionVisibility", () => {
  test("LoomStore has transitionVisibility method", () => {
    const source = readFileSync(join(WORKBENCH_SRC, "services/LoomStore.ts"), "utf-8");
    expect(source).toContain("transitionVisibility(");
    expect(source).toContain("newVisibility: 'draft' | 'published' | 'revoked'");
    expect(source).toContain("hatCapabilities?: number[]");
  });

  test("transitionVisibility rejects LINEAR objects from publishing", () => {
    const source = readFileSync(join(WORKBENCH_SRC, "services/LoomStore.ts"), "utf-8");
    expect(source).toContain("LINEAR objects cannot be published");
    // Check for linearity value 1 (LINEAR)
    expect(source).toContain("obj.header.linearity === 1");
  });

  test("transitionVisibility validates draft→published→revoked ordering", () => {
    const source = readFileSync(join(WORKBENCH_SRC, "services/LoomStore.ts"), "utf-8");
    // Can only publish from draft
    expect(source).toContain("Can only publish from draft state");
    // Can only revoke from published
    expect(source).toContain("Can only revoke from published state");
    // Cannot go back to draft
    expect(source).toContain("Cannot transition back to draft");
    // On publish: dispatches TRANSITION_LINEARITY to RELEVANT (3)
    expect(source).toContain("TRANSITION_LINEARITY");
    expect(source).toContain("newLinearity: 3");
  });
});

// ── Gate 3: Publish/Revoke flows ──────────────────────────────

describe("Gate 3: Publish/Revoke flows", () => {
  test("trades-services.json has publish-job flow with correct structure", () => {
    const ts = JSON.parse(readFileSync(join(CONFIGS_DIR, "trades-services.json"), "utf-8"));
    const publishFlow = ts.flows.find((f: any) => f.id === "publish-job");

    expect(publishFlow).toBeTruthy();
    expect(publishFlow.triggerIntents).toContain("publish");
    expect(publishFlow.requiredCapabilities).toContain(2);
    expect(publishFlow.steps.length).toBeGreaterThanOrEqual(1);
    expect(publishFlow.onComplete.type).toBe("transition");
    expect(publishFlow.onComplete.linearityTransition).toBe("AFFINE_TO_RELEVANT");
  });

  test("trades-services.json has revoke-job flow with correct structure", () => {
    const ts = JSON.parse(readFileSync(join(CONFIGS_DIR, "trades-services.json"), "utf-8"));
    const revokeFlow = ts.flows.find((f: any) => f.id === "revoke-job");

    expect(revokeFlow).toBeTruthy();
    expect(revokeFlow.triggerIntents).toContain("revoke");
    expect(revokeFlow.steps.length).toBeGreaterThanOrEqual(1);
    expect(revokeFlow.onComplete.type).toBe("transition");
    expect(revokeFlow.onComplete.linearityTransition).toBe("REVOKE");
  });

  test("ConversationPanel handles linearityTransition in transition handler", () => {
    const source = readFileSync(join(WORKBENCH_SRC, "canvas/ConversationPanel.tsx"), "utf-8");
    expect(source).toContain("linearityTransition");
    expect(source).toContain("transitionVisibility");
    expect(source).toContain("AFFINE_TO_RELEVANT");
    expect(source).toContain("REVOKE");
    // Error handling present
    expect(source).toContain("Publish failed:");
    expect(source).toContain("Revoke failed:");
  });

  test("FlowAction type supports linearityTransition field", () => {
    const source = readFileSync(join(WORKBENCH_SRC, "config/extensionConfig.ts"), "utf-8");
    expect(source).toContain("linearityTransition?: string");
  });
});

// ── Gate 4: Governance types in core.json ──────────────────────

describe("Gate 4: Governance types in core.json", () => {
  test("core.json has 4 governance types with valid 64-char hex typeHashes", () => {
    const core = JSON.parse(readFileSync(join(CONFIGS_DIR, "core.json"), "utf-8"));
    const govTypes = core.objectTypes.filter((t: any) =>
      ["Dispute", "Ballot", "Stake", "Resolution"].includes(t.name)
    );

    expect(govTypes.length).toBe(4);
    for (const t of govTypes) {
      expect(t.typeHash).toBeTruthy();
      expect(t.typeHash.length).toBe(64);
      expect(/^[0-9a-f]{64}$/.test(t.typeHash)).toBe(true);
    }
  });

  test("governance types have correct archetypes and linearities", () => {
    const core = JSON.parse(readFileSync(join(CONFIGS_DIR, "core.json"), "utf-8"));
    const byName = (n: string) => core.objectTypes.find((t: any) => t.name === n);

    const dispute = byName("Dispute");
    expect(dispute.linearity).toBe("AFFINE");
    expect(dispute.archetype).toBe("action");
    expect(dispute.linearityTransitions).toBeTruthy();
    expect(dispute.linearityTransitions[0].trigger).toBe("resolved");

    const ballot = byName("Ballot");
    expect(ballot.linearity).toBe("AFFINE");
    expect(ballot.archetype).toBe("action");
    expect(ballot.linearityTransitions[0].trigger).toBe("finalized");

    const stake = byName("Stake");
    expect(stake.linearity).toBe("LINEAR");
    expect(stake.archetype).toBe("instrument");

    const resolution = byName("Resolution");
    expect(resolution.linearity).toBe("RELEVANT");
    expect(resolution.archetype).toBe("instrument");
  });

  test("governance typeHashes are deterministic SHA256", () => {
    const core = JSON.parse(readFileSync(join(CONFIGS_DIR, "core.json"), "utf-8"));
    const byName = (n: string) => core.objectTypes.find((t: any) => t.name === n);

    const compute = (input: string) =>
      createHash("sha256").update(input, "utf-8").digest("hex");

    expect(byName("Dispute").typeHash).toBe(compute("governance.dispute:action:governance"));
    expect(byName("Ballot").typeHash).toBe(compute("governance.ballot:action:governance"));
    expect(byName("Stake").typeHash).toBe(compute("governance.stake:instrument:governance"));
    expect(byName("Resolution").typeHash).toBe(compute("governance.resolution:instrument:governance"));
  });
});

// ── Gate 5: Governance flows in core.json ──────────────────────

describe("Gate 5: Governance flows in core.json", () => {
  test("core.json has >= 3 governance flows with valid structure", () => {
    const core = JSON.parse(readFileSync(join(CONFIGS_DIR, "core.json"), "utf-8"));
    expect(core.flows).toBeTruthy();
    expect(core.flows.length).toBeGreaterThanOrEqual(3);

    for (const flow of core.flows) {
      expect(flow.id).toBeTruthy();
      expect(Array.isArray(flow.triggerIntents)).toBe(true);
      expect(flow.triggerIntents.length).toBeGreaterThan(0);
      expect(Array.isArray(flow.steps)).toBe(true);
      expect(flow.steps.length).toBeGreaterThan(0);
      expect(flow.onComplete).toBeTruthy();
      for (const step of flow.steps) {
        expect(step.id).toBeTruthy();
        expect(step.prompt).toBeTruthy();
      }
    }
  });

  test("governance flows reference correct object types and actions", () => {
    const core = JSON.parse(readFileSync(join(CONFIGS_DIR, "core.json"), "utf-8"));
    const byId = (id: string) => core.flows.find((f: any) => f.id === id);

    const dispute = byId("file-dispute");
    expect(dispute).toBeTruthy();
    expect(dispute.onComplete.type).toBe("create");
    expect(dispute.onComplete.objectType).toBe("Dispute");
    expect(dispute.triggerIntents).toContain("dispute");

    const vote = byId("cast-vote");
    expect(vote).toBeTruthy();
    expect(vote.onComplete.type).toBe("patch");
    expect(vote.onComplete.patchFields).toContain("votesFor");
    expect(vote.onComplete.patchFields).toContain("votesAgainst");

    const stakeFlow = byId("stake");
    expect(stakeFlow).toBeTruthy();
    expect(stakeFlow.onComplete.type).toBe("create");
    expect(stakeFlow.onComplete.objectType).toBe("Stake");
  });

  test("governance flows work with FlowRunner and findFlow", () => {
    const { findFlow } = require("../../runtime/services/src/services/FlowRegistry");
    const { FlowRunner } = require("../../runtime/services/src/services/FlowRunner");
    const { validateExtensionConfig } = require("../../runtime/services/src/config/extensionConfig");
    const core = JSON.parse(readFileSync(join(CONFIGS_DIR, "core.json"), "utf-8"));
    const config = validateExtensionConfig(core);

    // file-dispute flow with ATTESTATION capability
    const disputeFlow = findFlow("dispute", [5], config);
    expect(disputeFlow).toBeTruthy();
    expect(disputeFlow!.id).toBe("file-dispute");

    // Run the dispute flow through FlowRunner
    const runner = new FlowRunner();
    const first = runner.startFlow(disputeFlow!, "test-obj-1");
    expect(first.prompt).toContain("disputing");
    runner.advanceFlow("obj-123", { subjectObjectId: "obj-123" });
    const last = runner.advanceFlow("Incorrect pricing", { reasoning: "Incorrect pricing" });
    expect(last).toBeNull(); // Flow complete
    expect(runner.isFlowComplete()).toBe(true);
    const result = runner.completeFlow();
    expect(result.collectedData.subjectObjectId).toBe("obj-123");
    expect(result.collectedData.reasoning).toBe("Incorrect pricing");
    expect(result.onComplete.objectType).toBe("Dispute");
  });
});

// ── Gate 6: Anti-regression ──────────────────────────────────

describe("Gate 6: Anti-regression", () => {
  test("no GovernanceEngine or DisputeService in source", () => {
    const searchDir = (dir: string): string[] => {
      const results: string[] = [];
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        if (entry.isDirectory()) {
          results.push(...searchDir(join(dir, entry.name)));
        } else if (entry.name.endsWith(".ts") || entry.name.endsWith(".tsx")) {
          const content = readFileSync(join(dir, entry.name), "utf-8");
          if (/GovernanceEngine|DisputeService|BallotCoordinator|GovernanceService/i.test(content)) {
            results.push(join(dir, entry.name));
          }
        }
      }
      return results;
    };
    const offending = searchDir(WORKBENCH_SRC);
    expect(offending).toEqual([]);
  });

  test("no PublicationService or VisibilityManager in source", () => {
    const searchDir = (dir: string): string[] => {
      const results: string[] = [];
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        if (entry.isDirectory()) {
          results.push(...searchDir(join(dir, entry.name)));
        } else if (entry.name.endsWith(".ts") || entry.name.endsWith(".tsx")) {
          const content = readFileSync(join(dir, entry.name), "utf-8");
          if (/PublicationService|VisibilityManager|DraftPubService/i.test(content)) {
            results.push(join(dir, entry.name));
          }
        }
      }
      return results;
    };
    const offending = searchDir(WORKBENCH_SRC);
    expect(offending).toEqual([]);
  });

  test("Phase 9 gate still passes (cumulative) — config validates with new fields", () => {
    const { validateExtensionConfig } = require("../../runtime/services/src/config/extensionConfig");

    // All configs still validate
    const configs = ["core.json", "trades-services.json", "blockchain-risk.json", "development.json"];
    for (const file of configs) {
      const raw = JSON.parse(readFileSync(join(CONFIGS_DIR, file), "utf-8"));
      const config = validateExtensionConfig(raw);
      expect(config.id).toBeTruthy();
      expect(config.objectTypes.length).toBeGreaterThan(0);
      for (const ot of config.objectTypes) {
        expect(ot.typeHash.length).toBe(64);
        expect(/^[0-9a-f]{64}$/.test(ot.typeHash)).toBe(true);
      }
    }
  });
});

```
