---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase18-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.576931+00:00
---

# tests/gates/phase18-gate.test.ts

```ts
/**
 * Phase 18 Gate: Metering Control Plane
 *
 * Tests T1–T12 covering channel objects, FSM flow, guard evaluation,
 * transaction-as-patch, dispute bridge, CashLanes stub, and boundary checks.
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");
const WORKBENCH_SRC = join(ROOT, "runtime/services/src");
const CONFIG_PATH = join(ROOT, "configs/extensions/core.json");

// Load and parse core.json
const coreConfig = JSON.parse(readFileSync(CONFIG_PATH, "utf-8"));

// ── T1: PaymentChannel in core.json with LINEAR linearity ──────────

describe("T1: PaymentChannel object type", () => {
  const paymentChannel = coreConfig.objectTypes.find(
    (t: any) => t.name === "PaymentChannel"
  );

  test("PaymentChannel type exists in core.json", () => {
    expect(paymentChannel).toBeDefined();
  });

  test("PaymentChannel has LINEAR linearity", () => {
    expect(paymentChannel.linearity).toBe("LINEAR");
  });

  test("PaymentChannel has metering.channel category", () => {
    expect(paymentChannel.category).toBe("metering.channel");
  });

  test("PaymentChannel has instrument archetype", () => {
    expect(paymentChannel.archetype).toBe("instrument");
  });

  test("PaymentChannel has 64-char hex typeHash", () => {
    expect(paymentChannel.typeHash).toMatch(/^[0-9a-f]{64}$/);
  });

  test("PaymentChannel has METERING (10) and MESSAGING (4) capabilities", () => {
    expect(paymentChannel.defaultCapabilities).toContain(10);
    expect(paymentChannel.defaultCapabilities).toContain(4);
  });

  test("PaymentChannel has required fields", () => {
    const fieldNames = paymentChannel.fields.map((f: any) => f.name);
    expect(fieldNames).toContain("counterpartyCertId");
    expect(fieldNames).toContain("fundingSatoshis");
    expect(fieldNames).toContain("policyObjectId");
    expect(fieldNames).toContain("channelCertId");
    expect(fieldNames).toContain("meterUnit");
    expect(fieldNames).toContain("status");
    expect(fieldNames).toContain("settlementConfirmed");
  });

  test("PaymentChannel status enum has all lifecycle phases", () => {
    const statusField = paymentChannel.fields.find((f: any) => f.name === "status");
    expect(statusField.type).toBe("enum");
    expect(statusField.values).toContain("prefunding");
    expect(statusField.values).toContain("funding");
    expect(statusField.values).toContain("active");
    expect(statusField.values).toContain("settling");
    expect(statusField.values).toContain("settled");
    expect(statusField.values).toContain("disputed");
    expect(statusField.values).toContain("closed");
  });
});

// ── T2: ChannelPolicy in core.json with RELEVANT linearity ──────────

describe("T2: ChannelPolicy object type", () => {
  const channelPolicy = coreConfig.objectTypes.find(
    (t: any) => t.name === "ChannelPolicy"
  );

  test("ChannelPolicy type exists in core.json", () => {
    expect(channelPolicy).toBeDefined();
  });

  test("ChannelPolicy has RELEVANT linearity", () => {
    expect(channelPolicy.linearity).toBe("RELEVANT");
  });

  test("ChannelPolicy has metering.policy category", () => {
    expect(channelPolicy.category).toBe("metering.policy");
  });

  test("ChannelPolicy has 64-char hex typeHash", () => {
    expect(channelPolicy.typeHash).toMatch(/^[0-9a-f]{64}$/);
  });

  test("ChannelPolicy has meterUnit field (string type, generic)", () => {
    const meterUnitField = channelPolicy.fields.find((f: any) => f.name === "meterUnit");
    expect(meterUnitField).toBeDefined();
    expect(meterUnitField.type).toBe("string");
    // meterUnit has no enum values — it's a generic string for any unit
    expect(meterUnitField.values).toBeUndefined();
  });

  test("ChannelPolicy has metering rules fields", () => {
    const fieldNames = channelPolicy.fields.map((f: any) => f.name);
    expect(fieldNames).toContain("minFundingSatoshis");
    expect(fieldNames).toContain("maxChannelDurationSeconds");
    expect(fieldNames).toContain("disputeWindowSeconds");
    expect(fieldNames).toContain("settlementFeePercent");
    expect(fieldNames).toContain("pricePerUnit");
    expect(fieldNames).toContain("autoSettleThreshold");
  });
});

// ── T3: Channel lifecycle flow with phases and guards ──────────

describe("T3: Channel lifecycle flow definition", () => {
  const lifecycle = coreConfig.channelLifecycle;

  test("channelLifecycle exists in core.json", () => {
    expect(lifecycle).toBeDefined();
  });

  test("lifecycle has all required phases", () => {
    const phaseIds = lifecycle.phases.map((p: any) => p.phaseId);
    expect(phaseIds).toContain("prefunding");
    expect(phaseIds).toContain("funding");
    expect(phaseIds).toContain("active");
    expect(phaseIds).toContain("settling");
    expect(phaseIds).toContain("settled");
    expect(phaseIds).toContain("disputed");
    expect(phaseIds).toContain("closed");
  });

  test("every transition has a guard", () => {
    for (const phase of lifecycle.phases) {
      for (const transition of phase.transitions) {
        expect(transition.guard).toBeDefined();
        expect(transition.guard.type).toBeDefined();
        expect(transition.guard.field).toBeDefined();
        expect(transition.guard.operator).toBeDefined();
        expect(transition.guard.value).toBeDefined();
      }
    }
  });

  test("closed phase has no transitions (terminal)", () => {
    const closedPhase = lifecycle.phases.find((p: any) => p.phaseId === "closed");
    expect(closedPhase.transitions).toHaveLength(0);
  });

  test("active phase can self-transition (transact)", () => {
    const activePhase = lifecycle.phases.find((p: any) => p.phaseId === "active");
    const selfTransition = activePhase.transitions.find((t: any) => t.targetPhase === "active");
    expect(selfTransition).toBeDefined();
    expect(selfTransition.displayName).toBe("Transact");
  });

  test("channel-open conversation flow exists", () => {
    const flow = coreConfig.flows.find((f: any) => f.id === "channel-open");
    expect(flow).toBeDefined();
    expect(flow.steps.length).toBeGreaterThanOrEqual(3);
    expect(flow.onComplete.type).toBe("create");
    expect(flow.onComplete.objectType).toBe("PaymentChannel");
  });
});

// ── T4: ObjectPatch.kind includes channel types ──────────

describe("T4: ObjectPatch.kind union extensions", () => {
  test("ObjectPatch.kind includes channel_transaction", () => {
    const src = readFileSync(join(WORKBENCH_SRC, "types/loom.ts"), "utf-8");
    expect(src).toContain("channel_transaction");
  });

  test("ObjectPatch.kind includes channel_settlement", () => {
    const src = readFileSync(join(WORKBENCH_SRC, "types/loom.ts"), "utf-8");
    expect(src).toContain("channel_settlement");
  });

  test("EvidenceChain has KIND_COLORS for channel types", () => {
    const src = readFileSync(join(WORKBENCH_SRC, "inspector/EvidenceChain.tsx"), "utf-8");
    expect(src).toContain("channel_transaction");
    expect(src).toContain("channel_settlement");
  });
});

// ── T5: LoomStore has channel methods ──────────

describe("T5: LoomStore channel methods", () => {
  const storeSrc = readFileSync(join(WORKBENCH_SRC, "services/LoomStore.ts"), "utf-8");

  test("createPaymentChannel method exists", () => {
    expect(storeSrc).toContain("createPaymentChannel");
  });

  test("advanceChannelPhase method exists", () => {
    expect(storeSrc).toContain("advanceChannelPhase");
  });

  test("recordChannelTransaction method exists", () => {
    expect(storeSrc).toContain("recordChannelTransaction");
  });

  test("channel cert derived via metering domain 0x0A", () => {
    expect(storeSrc).toContain("0x0A");
    expect(storeSrc).toContain("metering.channel");
  });

  test("counterparty edge created via createEdge", () => {
    expect(storeSrc).toContain("createEdge");
  });

  test("witness hash computation present", () => {
    expect(storeSrc).toContain("witnessHash");
    expect(storeSrc).toContain("sha256hex");
  });
});

// ── T6: FlowRunner has phase transition and guard evaluation ──────────

describe("T6: FlowRunner phase transitions", () => {
  const runnerSrc = readFileSync(join(WORKBENCH_SRC, "services/FlowRunner.ts"), "utf-8");

  test("transitionPhase method exists", () => {
    expect(runnerSrc).toContain("transitionPhase");
  });

  test("evaluateGuard function exists", () => {
    expect(runnerSrc).toContain("evaluateGuard");
  });

  test("FlowStepGuard interface exported", () => {
    expect(runnerSrc).toContain("export interface FlowStepGuard");
  });

  test("ChannelLifecycleFlow interface exported", () => {
    expect(runnerSrc).toContain("export interface ChannelLifecycleFlow");
  });

  test("guard evaluation supports capability checks", () => {
    expect(runnerSrc).toContain("includes_all");
  });

  test("guard evaluation supports time checks", () => {
    expect(runnerSrc).toContain("now()");
  });

  // Functional test: evaluateGuard works correctly
  test("evaluateGuard evaluates capability guard correctly", async () => {
    const { evaluateGuard } = require("../../runtime/services/src/services/FlowRunner");

    const guard = {
      type: "capability",
      field: "identity.capabilities",
      operator: "includes_all",
      value: [2, 8],
    };

    // Should pass when all capabilities present
    expect(evaluateGuard(guard, { identity: { capabilities: [2, 8, 10] } })).toBe(true);
    // Should fail when missing a capability
    expect(evaluateGuard(guard, { identity: { capabilities: [2, 10] } })).toBe(false);
  });

  test("evaluateGuard evaluates value guard correctly", async () => {
    const { evaluateGuard } = require("../../runtime/services/src/services/FlowRunner");

    const guard = {
      type: "value",
      field: "object.fundingSatoshis",
      operator: "gte",
      value: 10000,
    };

    expect(evaluateGuard(guard, { object: { fundingSatoshis: 50000 } })).toBe(true);
    expect(evaluateGuard(guard, { object: { fundingSatoshis: 5000 } })).toBe(false);
  });

  test("evaluateGuard evaluates contextual guard correctly", async () => {
    const { evaluateGuard } = require("../../runtime/services/src/services/FlowRunner");

    const guard = {
      type: "contextual",
      field: "ballot.resolution",
      operator: "eq",
      value: "force_close",
    };

    expect(evaluateGuard(guard, { ballot: { resolution: "force_close" } })).toBe(true);
    expect(evaluateGuard(guard, { ballot: { resolution: "settle" } })).toBe(false);
  });

  // Functional test: transitionPhase works correctly
  test("FlowRunner.transitionPhase validates transitions", async () => {
    const { FlowRunner } = require("../../runtime/services/src/services/FlowRunner");
    const runner = new FlowRunner();

    const result = runner.transitionPhase(
      coreConfig.channelLifecycle,
      "prefunding",
      "funding",
      { identity: { capabilities: [2, 8] } },
    );
    expect(result.ok).toBe(true);
    expect(result.fromPhase).toBe("prefunding");
    expect(result.toPhase).toBe("funding");
  });

  test("FlowRunner.transitionPhase rejects invalid transition", async () => {
    const { FlowRunner } = require("../../runtime/services/src/services/FlowRunner");
    const runner = new FlowRunner();

    // Cannot go from prefunding directly to active
    const result = runner.transitionPhase(
      coreConfig.channelLifecycle,
      "prefunding",
      "active",
      { identity: { capabilities: [2, 8] } },
    );
    expect(result.ok).toBe(false);
  });

  test("FlowRunner.transitionPhase rejects when guard fails", async () => {
    const { FlowRunner } = require("../../runtime/services/src/services/FlowRunner");
    const runner = new FlowRunner();

    // Missing required capabilities
    const result = runner.transitionPhase(
      coreConfig.channelLifecycle,
      "prefunding",
      "funding",
      { identity: { capabilities: [2] } }, // Missing 8
    );
    expect(result.ok).toBe(false);
  });
});

// ── T7: CashLanesService exists with settlement methods ──────────

describe("T7: CashLanesService", () => {
  const cashLanesSrc = readFileSync(join(WORKBENCH_SRC, "plexus/CashLanesService.ts"), "utf-8");

  test("CashLanesService file exists", () => {
    expect(existsSync(join(WORKBENCH_SRC, "plexus/CashLanesService.ts"))).toBe(true);
  });

  test("prepareCashLanesSettlement method exists", () => {
    expect(cashLanesSrc).toContain("prepareCashLanesSettlement");
  });

  test("collectCashLanesSignatures method exists", () => {
    expect(cashLanesSrc).toContain("collectCashLanesSignatures");
  });

  test("broadcastCashLanesSettlement method exists", () => {
    expect(cashLanesSrc).toContain("broadcastCashLanesSettlement");
  });

  test("awaitCashLanesConfirmation method exists", () => {
    expect(cashLanesSrc).toContain("awaitCashLanesConfirmation");
  });

  // Functional test: stub returns valid results
  test("CashLanesService stub returns settlement data", async () => {
    const { CashLanesService } = require("../../runtime/services/src/plexus/CashLanesService");
    const service = new CashLanesService();

    const tx = await service.prepareCashLanesSettlement("ch-1", 5000, 3000, 1);
    expect(tx.unsignedTx).toBeDefined();
    expect(typeof tx.unsignedTx).toBe("string");
    expect(tx.channelId).toBe("ch-1");

    const sigs = await service.collectCashLanesSignatures("ch-1", "cert:abc", tx);
    expect(sigs.ownerSig).toBeDefined();
    expect(sigs.counterpartySig).toBeDefined();

    const settlement = await service.broadcastCashLanesSettlement("ch-1", tx, sigs);
    expect(settlement.txid).toBeDefined();
    expect(settlement.status).toBe("broadcast");

    const confirmation = await service.awaitCashLanesConfirmation(settlement.txid);
    expect(confirmation.confirmed).toBe(true);
    expect(confirmation.blockHeight).toBeGreaterThan(0);
  });
});

// ── T8: ChannelInspectorPanel exists ──────────

describe("T8: ChannelInspectorPanel", () => {
  test("ChannelInspectorPanel file exists", () => {
    expect(existsSync(join(WORKBENCH_SRC, "inspector/ChannelInspectorPanel.tsx"))).toBe(true);
  });

  test("ChannelInspectorPanel checks for metering.channel category", () => {
    const src = readFileSync(join(WORKBENCH_SRC, "inspector/ChannelInspectorPanel.tsx"), "utf-8");
    expect(src).toContain("metering.channel");
  });

  test("ObjectInspector imports and renders ChannelInspectorPanel", () => {
    const src = readFileSync(join(WORKBENCH_SRC, "inspector/ObjectInspector.tsx"), "utf-8");
    expect(src).toContain("ChannelInspectorPanel");
    expect(src).toContain("metering.channel");
  });
});

// ── T9: Dispute bridge in LoomStore ──────────

describe("T9: Dispute bridge", () => {
  const storeSrc = readFileSync(join(WORKBENCH_SRC, "services/LoomStore.ts"), "utf-8");

  test("advanceChannelPhase creates Dispute on disputed phase", () => {
    expect(storeSrc).toContain("createDisputeForChannel");
    expect(storeSrc).toContain("governance.dispute");
  });

  test("advanceChannelPhase creates Ballot on disputed phase", () => {
    expect(storeSrc).toContain("governance.ballot");
    expect(storeSrc).toContain("Channel Settlement Dispute");
  });

  test("dispute and ballot IDs stored on channel payload", () => {
    expect(storeSrc).toContain("disputeId");
    expect(storeSrc).toContain("ballotId");
  });
});

// ── T10: meterUnit is generic string ──────────

describe("T10: Generic metering", () => {
  test("meterUnit field in ChannelPolicy is string type (not enum)", () => {
    const policy = coreConfig.objectTypes.find((t: any) => t.name === "ChannelPolicy");
    const meterUnit = policy.fields.find((f: any) => f.name === "meterUnit");
    expect(meterUnit.type).toBe("string");
    // No hardcoded enum values
    expect(meterUnit.values).toBeUndefined();
  });

  test("meterUnit field in PaymentChannel is string type (not enum)", () => {
    const channel = coreConfig.objectTypes.find((t: any) => t.name === "PaymentChannel");
    const meterUnit = channel.fields.find((f: any) => f.name === "meterUnit");
    expect(meterUnit.type).toBe("string");
    expect(meterUnit.values).toBeUndefined();
  });

  test("no hardcoded meterUnit values in lifecycle guards", () => {
    const lifecycleStr = JSON.stringify(coreConfig.channelLifecycle);
    // Guard values should not contain specific unit names
    expect(lifecycleStr).not.toContain('"api_call"');
    expect(lifecycleStr).not.toContain('"byte"');
    expect(lifecycleStr).not.toContain('"second"');
  });
});

// ── T11: Channel cert derived via domain 0x0A ──────────

describe("T11: Channel identity derivation", () => {
  test("LoomStore uses domain flag 0x0A for metering", () => {
    const src = readFileSync(join(WORKBENCH_SRC, "services/LoomStore.ts"), "utf-8");
    expect(src).toContain("0x0A");
  });

  test("LoomStore derives channel cert via deriveChild", () => {
    const src = readFileSync(join(WORKBENCH_SRC, "services/LoomStore.ts"), "utf-8");
    expect(src).toContain("deriveChild");
    expect(src).toContain("'metering.channel'");
  });
});

// ── T12: Boundary checks ──────────

describe("T12: Boundary and import checks", () => {
  test("CashLanesService does not import from @plexus", () => {
    const src = readFileSync(join(WORKBENCH_SRC, "plexus/CashLanesService.ts"), "utf-8");
    expect(src).not.toContain("@plexus/");
    expect(src).not.toContain("from '@plexus");
  });

  test("CashLanesService does not contain Bitcoin signing logic", () => {
    const src = readFileSync(join(WORKBENCH_SRC, "plexus/CashLanesService.ts"), "utf-8");
    // No Bitcoin-specific operations
    expect(src).not.toContain("OP_CHECKMULTISIG");
    expect(src).not.toContain("scriptPubKey");
    expect(src).not.toContain("UTXO");
    expect(src).not.toContain("PrivateKey");
  });

  test("FlowRunner does not import PlexusAdapter", () => {
    const src = readFileSync(join(WORKBENCH_SRC, "services/FlowRunner.ts"), "utf-8");
    expect(src).not.toContain("PlexusAdapter");
    expect(src).not.toContain("@plexus/");
  });

  test("settlement patch recorded as channel_settlement evidence", () => {
    const src = readFileSync(join(WORKBENCH_SRC, "services/LoomStore.ts"), "utf-8");
    expect(src).toContain("channel_settlement");
    expect(src).toContain("txid");
    expect(src).toContain("broadcastTime");
  });
});

```
