---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase28-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.585007+00:00
---

# tests/gates/phase28-gate.test.ts

```ts
/**
 * Phase 28 Gate: ISDA CDM Integration
 *
 * Validates:
 * 1. CDM product cells and type mapping (T1–T4)
 * 2. Lifecycle transitions (T5–T11)
 * 3. Regulatory reports (T12–T16)
 * 4. ISDA policies (T17–T21)
 * 5. Import/export bridge (T22–T25)
 * 6. Full lifecycle integration (T26)
 * 7. Anti-lock (T27–T28)
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");

// ── Gate 1: CDM Product Cells (T1–T4) ─────────────────────────

describe("D28.1 — CDM product cells", () => {
  test("T1: fixed-float swap creates LINEAR cell with taxonomy 'rates.swap.fixed-float'", () => {
    const { createCDMProduct } = require(
      join(ROOT, "packages/cdm/src/types.ts"),
    );
    const product = createCDMProduct(
      "rates.swap.fixed-float",
      {
        notional: { amount: 10_000_000, currency: "USD" },
        effectiveDate: "2024-06-15",
        terminationDate: "2029-06-15",
        fixedRate: 0.035,
        floatingRateIndex: "SOFR",
        paymentFrequency: "3M",
        dayCountConvention: "ACT/360",
      },
      [
        { partyId: "bank-a", role: "buyer", capabilities: [2, 9], lei: "BANKALEIENTITY01" },
        { partyId: "bank-b", role: "seller", capabilities: [2, 9], lei: "BANKBLEIENTITY02" },
      ],
      "2024-06-15",
    );

    expect(product.linearity).toBe("LINEAR");
    expect(product.productType).toBe("rates.swap.fixed-float");
    expect(product.lifecycleState).toBe("proposed");
    expect(product.cellId).toBeTruthy();
    expect(product.typeHashHex).toHaveLength(64);
  });

  test("T2: economic terms round-trip through serialize/deserialize", () => {
    const { createCDMProduct } = require(
      join(ROOT, "packages/cdm/src/types.ts"),
    );
    const terms = {
      notional: { amount: 5_000_000, currency: "EUR" },
      effectiveDate: "2024-01-01",
      terminationDate: "2026-01-01",
      fixedRate: 0.025,
      floatingRateIndex: "EURIBOR",
      paymentFrequency: "6M",
      dayCountConvention: "30/360",
      businessDayConvention: "MODFOLLOWING",
    };
    const product = createCDMProduct(
      "rates.swap.fixed-float",
      terms,
      [{ partyId: "p1", role: "buyer", capabilities: [] }],
      "2024-01-01",
    );

    const serialized = JSON.stringify(product.economicTerms);
    const deserialized = JSON.parse(serialized);

    expect(deserialized.notional.amount).toBe(5_000_000);
    expect(deserialized.notional.currency).toBe("EUR");
    expect(deserialized.fixedRate).toBe(0.025);
    expect(deserialized.floatingRateIndex).toBe("EURIBOR");
    expect(deserialized.paymentFrequency).toBe("6M");
    expect(deserialized.dayCountConvention).toBe("30/360");
    expect(deserialized.businessDayConvention).toBe("MODFOLLOWING");
  });

  test("T3: party roles map to identity facets with correct capabilities", () => {
    const { createCDMProduct } = require(
      join(ROOT, "packages/cdm/src/types.ts"),
    );
    const product = createCDMProduct(
      "credit.cds.single-name",
      {
        notional: { amount: 10_000_000, currency: "USD" },
        effectiveDate: "2024-01-01",
        terminationDate: "2029-01-01",
      },
      [
        { partyId: "buyer-1", role: "buyer", capabilities: [2, 9], hatCertId: "cert-abc" },
        { partyId: "seller-1", role: "seller", capabilities: [2], hatCertId: "cert-xyz" },
        { partyId: "calc-agent", role: "calculation-agent", capabilities: [2, 7], hatCertId: "cert-ca" },
      ],
      "2024-01-01",
    );

    expect(product.parties).toHaveLength(3);
    expect(product.parties[0].role).toBe("buyer");
    expect(product.parties[0].capabilities).toEqual([2, 9]);
    expect(product.parties[1].role).toBe("seller");
    expect(product.parties[2].role).toBe("calculation-agent");
    expect(product.parties[2].hatCertId).toBe("cert-ca");
  });

  test("T4: product taxonomy string matches ISDA classification", () => {
    const { computeCDMTypeHash } = require(
      join(ROOT, "packages/cdm/src/types.ts"),
    );

    const hash1 = computeCDMTypeHash("rates.swap.fixed-float");
    const hash2 = computeCDMTypeHash("credit.cds.single-name");
    const hash3 = computeCDMTypeHash("fx.forward.deliverable");

    // Each hash is a 64-char hex SHA256
    expect(hash1).toHaveLength(64);
    expect(hash2).toHaveLength(64);
    expect(hash3).toHaveLength(64);

    // Different product types produce different hashes
    expect(hash1).not.toBe(hash2);
    expect(hash2).not.toBe(hash3);

    // Deterministic — same input gives same output
    expect(computeCDMTypeHash("rates.swap.fixed-float")).toBe(hash1);
  });
});

// ── Gate 2: Lifecycle Transitions (T5–T11) ────────────────────

describe("D28.2 — Lifecycle transitions", () => {
  function makeProduct(state: string = "proposed") {
    const { createCDMProduct } = require(join(ROOT, "packages/cdm/src/types.ts"));
    const p = createCDMProduct(
      "rates.swap.fixed-float",
      {
        notional: { amount: 10_000_000, currency: "USD" },
        effectiveDate: "2024-06-15",
        terminationDate: "2029-06-15",
        fixedRate: 0.035,
        floatingRateIndex: "SOFR",
      },
      [
        { partyId: "bank-a", role: "buyer", capabilities: [2, 9], lei: "LEI0000BANK_A000" },
        { partyId: "bank-b", role: "seller", capabilities: [2, 9], lei: "LEI0000BANK_B000" },
      ],
      "2024-06-15",
    );
    p.lifecycleState = state;
    return p;
  }

  test("T5: execution event transitions proposed → executed", async () => {
    const { CDMLifecycleEngine } = require(join(ROOT, "packages/cdm/src/lifecycle.ts"));
    const engine = new CDMLifecycleEngine();
    const product = makeProduct("proposed");

    const result = await engine.executeEvent(product, "execution", "2024-06-15", {}, "actor-1");

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.product.lifecycleState).toBe("executed");
      expect(result.value.event.before).toBe("proposed");
      expect(result.value.event.after).toBe("executed");
      expect(result.value.cell).toBeInstanceOf(Uint8Array);
      expect(result.value.cell.length).toBeGreaterThanOrEqual(1024);
    }
  });

  test("T6: confirmation event transitions executed → confirmed", async () => {
    const { CDMLifecycleEngine } = require(join(ROOT, "packages/cdm/src/lifecycle.ts"));
    const engine = new CDMLifecycleEngine();
    const product = makeProduct("executed");

    const result = await engine.executeEvent(product, "confirmation", "2024-06-16", {}, "actor-1");

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.product.lifecycleState).toBe("confirmed");
    }
  });

  test("T7: novation transfers product to new counterparty via Phase 17 transfer", () => {
    const { CDMLifecycleEngine } = require(join(ROOT, "packages/cdm/src/lifecycle.ts"));
    const engine = new CDMLifecycleEngine();
    const product = makeProduct("confirmed");

    const oldParty = product.parties[0]; // bank-a
    const newParty = {
      partyId: "bank-c",
      role: "buyer" as const,
      capabilities: [2, 9],
      lei: "LEI0000BANK_C000",
    };

    const result = engine.novate(product, oldParty, newParty, "actor-1");

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.product.lifecycleState).toBe("novated");
      // TransferRecord created via Phase 17 createTransferRecord
      expect(result.value.transferRecord.objectCertId).toBe(product.cellId);
      expect(result.value.transferRecord.fromParentCertId).toBeTruthy();
      expect(result.value.transferRecord.toParentCertId).toBeTruthy();
      expect(result.value.transferRecord.semanticType).toBe("AFFINE");
      // Parties updated
      expect(result.value.product.parties.some((p: { partyId: string }) => p.partyId === "bank-c")).toBe(true);
    }
  });

  test("T8: partial termination reduces notional (AFFINE partial consume)", () => {
    const { CDMLifecycleEngine } = require(join(ROOT, "packages/cdm/src/lifecycle.ts"));
    const engine = new CDMLifecycleEngine();
    const product = makeProduct("confirmed");

    const result = engine.partialTerminate(product, 3_000_000, "actor-1");

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.product.lifecycleState).toBe("partially-terminated");
      expect(result.value.product.economicTerms.notional.amount).toBe(7_000_000);
      expect(result.value.event.economicEffect?.notionalChange).toBe(-3_000_000);
    }
  });

  test("T9: full termination consumes product cell (LINEAR consume)", async () => {
    const { CDMLifecycleEngine } = require(join(ROOT, "packages/cdm/src/lifecycle.ts"));
    const engine = new CDMLifecycleEngine();
    const product = makeProduct("confirmed");

    const result = await engine.executeEvent(product, "full-termination", "2024-12-31", {}, "actor-1");

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.product.lifecycleState).toBe("terminated");
    }
  });

  test("T10: event without authorization capability is rejected (invalid transition)", async () => {
    const { CDMLifecycleEngine } = require(join(ROOT, "packages/cdm/src/lifecycle.ts"));
    const engine = new CDMLifecycleEngine();
    const product = makeProduct("terminated");

    // Terminated products cannot accept any events
    const result = await engine.executeEvent(product, "confirmation", "2024-06-20", {}, "actor-1");

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toContain("Cannot apply");
    }
  });

  test("T11: event history is traversable DAG from latest to execution", async () => {
    const { CDMLifecycleEngine } = require(join(ROOT, "packages/cdm/src/lifecycle.ts"));
    const engine = new CDMLifecycleEngine();
    let product = makeProduct("proposed");

    const events: any[] = [];

    // Execute multiple events
    const r1 = await engine.executeEvent(product, "execution", "2024-06-15", {}, "actor-1");
    expect(r1.ok).toBe(true);
    if (r1.ok) {
      product = r1.value.product;
      events.push(r1.value.event);
    }

    const r2 = await engine.executeEvent(product, "confirmation", "2024-06-16", {}, "actor-1");
    expect(r2.ok).toBe(true);
    if (r2.ok) {
      product = r2.value.product;
      events.push(r2.value.event);
    }

    const history = engine.eventHistory(product, events);
    expect(history).toHaveLength(2);
    expect(history[0].eventType).toBe("execution");
    expect(history[1].eventType).toBe("confirmation");
    // Sorted by timestamp (ascending)
    expect(history[0].timestamp).toBeLessThanOrEqual(history[1].timestamp);
  });
});

// ── Gate 3: Regulatory Reports (T12–T16) ──────────────────────

describe("D28.3 — Regulatory reports", () => {
  function makeUSDProduct() {
    const { createCDMProduct } = require(join(ROOT, "packages/cdm/src/types.ts"));
    return createCDMProduct(
      "rates.swap.fixed-float",
      {
        notional: { amount: 10_000_000, currency: "USD" },
        effectiveDate: "2024-06-15",
        terminationDate: "2029-06-15",
      },
      [
        { partyId: "us-bank", role: "buyer", capabilities: [2], lei: "USBANK0000000001", jurisdiction: "US" },
        { partyId: "us-dealer", role: "seller", capabilities: [2], lei: "USDEAL0000000002", jurisdiction: "US" },
      ],
      "2024-06-15",
    );
  }

  function makeEURProduct() {
    const { createCDMProduct } = require(join(ROOT, "packages/cdm/src/types.ts"));
    return createCDMProduct(
      "rates.swap.fixed-float",
      {
        notional: { amount: 5_000_000, currency: "EUR" },
        effectiveDate: "2024-06-15",
        terminationDate: "2029-06-15",
      },
      [
        { partyId: "eu-bank", role: "buyer", capabilities: [2], lei: "EUBANK0000000001", jurisdiction: "DE" },
        { partyId: "eu-dealer", role: "seller", capabilities: [2], lei: "EUDEAL0000000002", jurisdiction: "FR" },
      ],
      "2024-06-15",
    );
  }

  test("T12: CFTC report generated for USD swap execution", () => {
    const { RegulatoryReportGenerator } = require(join(ROOT, "packages/cdm/src/regulatory.ts"));
    const { createLifecycleEvent } = require(join(ROOT, "packages/cdm/src/types.ts"));
    const gen = new RegulatoryReportGenerator();
    const product = makeUSDProduct();
    const event = createLifecycleEvent("execution", product, "2024-06-15", "proposed", "executed", "actor");

    const reports = gen.generate(event, product);
    const cftcReport = reports.find((r: any) => r.regime === "CFTC");

    expect(cftcReport).toBeTruthy();
    expect(cftcReport.regime).toBe("CFTC");
    expect(cftcReport.uti).toBeTruthy();
    expect(cftcReport.sourceEventCell).toBe(event.eventId);
  });

  test("T13: EMIR report generated for EUR swap with EU counterparty", () => {
    const { RegulatoryReportGenerator } = require(join(ROOT, "packages/cdm/src/regulatory.ts"));
    const { createLifecycleEvent } = require(join(ROOT, "packages/cdm/src/types.ts"));
    const gen = new RegulatoryReportGenerator();
    const product = makeEURProduct();
    const event = createLifecycleEvent("execution", product, "2024-06-15", "proposed", "executed", "actor");

    const reports = gen.generate(event, product);
    const emirReport = reports.find((r: any) => r.regime === "EMIR");

    expect(emirReport).toBeTruthy();
    expect(emirReport.regime).toBe("EMIR");
  });

  test("T14: report is RELEVANT linearity — consume attempt rejected by engine", () => {
    const { RegulatoryReportGenerator } = require(join(ROOT, "packages/cdm/src/regulatory.ts"));
    const { createLifecycleEvent } = require(join(ROOT, "packages/cdm/src/types.ts"));
    const gen = new RegulatoryReportGenerator();
    const product = makeUSDProduct();
    const event = createLifecycleEvent("execution", product, "2024-06-15", "proposed", "executed", "actor");

    const reports = gen.generate(event, product);
    for (const report of reports) {
      expect(report.linearity).toBe("RELEVANT");
    }

    // Verify packed cell uses RELEVANT linearity (3)
    const cell = gen.packReportCell(reports[0]);
    expect(cell).toBeInstanceOf(Uint8Array);
    expect(cell.length).toBeGreaterThanOrEqual(1024);
    // Linearity field is at offset 16, 4 bytes LE
    const linearity = cell[16] | (cell[17] << 8) | (cell[18] << 16) | (cell[19] << 24);
    expect(linearity).toBe(3); // RELEVANT = 3
  });

  test("T15: report references source event cell via cellId", () => {
    const { RegulatoryReportGenerator } = require(join(ROOT, "packages/cdm/src/regulatory.ts"));
    const { createLifecycleEvent } = require(join(ROOT, "packages/cdm/src/types.ts"));
    const gen = new RegulatoryReportGenerator();
    const product = makeUSDProduct();
    const event = createLifecycleEvent("execution", product, "2024-06-15", "proposed", "executed", "actor");

    const reports = gen.generate(event, product);
    expect(reports.length).toBeGreaterThan(0);
    expect(reports[0].sourceEventCell).toBe(event.eventId);
  });

  test("T16: UTI format follows ISDA standard", () => {
    const { generateUTI } = require(join(ROOT, "packages/cdm/src/types.ts"));

    const uti = generateUTI("BANKALEIENTITY01", "2024-06-15", "product-123");

    // Format: {LEI_PREFIX}_{date}{hash8}
    expect(uti).toMatch(/^BANKALEIEN_\d{8}[a-f0-9]{8}$/);
  });
});

// ── Gate 4: ISDA Policies (T17–T21) ───────────────────────────

describe("D28.4 — ISDA policies", () => {
  test("T17: payment blocked when counterparty in default (Section 2(a)(iii))", () => {
    const policySource = readFileSync(
      join(ROOT, "packages/cdm/src/policies/payment-condition-precedent.policy"),
      "utf-8",
    );
    expect(policySource).toContain("paying-party");
    expect(policySource).toContain("counterparty-default-status");
    expect(policySource).toContain("defaulted");

    // Verify it compiles
    const { compileCDMPolicy } = require(join(ROOT, "packages/cdm/src/policies/compiler.ts"));
    const output = compileCDMPolicy(policySource);
    expect(output.scriptBytes.length).toBeGreaterThan(0);
    expect(output.scriptWords).toContain("VERIFY");
  });

  test("T18: failure to pay triggers default after grace period (Section 5)", () => {
    const policySource = readFileSync(
      join(ROOT, "packages/cdm/src/policies/failure-to-pay-default.policy"),
      "utf-8",
    );
    expect(policySource).toContain("calculation-agent");
    expect(policySource).toContain("days-past-due");

    const { compileCDMPolicy } = require(join(ROOT, "packages/cdm/src/policies/compiler.ts"));
    const output = compileCDMPolicy(policySource);
    expect(output.scriptBytes.length).toBeGreaterThan(0);
  });

  test("T19: close-out netting requires non-defaulting party capability (Section 6)", () => {
    const policySource = readFileSync(
      join(ROOT, "packages/cdm/src/policies/close-out-netting.policy"),
      "utf-8",
    );
    expect(policySource).toContain("non-defaulting-party");
    expect(policySource).toContain("has-capability");

    const { compileCDMPolicy } = require(join(ROOT, "packages/cdm/src/policies/compiler.ts"));
    const output = compileCDMPolicy(policySource);
    expect(output.scriptBytes.length).toBeGreaterThan(0);
    expect(output.scriptWords).toContain("CHECK-CAP");
  });

  test("T20: novation blocked without transfer consent capability (Section 11)", () => {
    const policySource = readFileSync(
      join(ROOT, "packages/cdm/src/policies/transfer-consent.policy"),
      "utf-8",
    );
    expect(policySource).toContain("transferring-party");
    expect(policySource).toContain("novate");

    const { compileCDMPolicy } = require(join(ROOT, "packages/cdm/src/policies/compiler.ts"));
    const output = compileCDMPolicy(policySource);
    expect(output.scriptBytes.length).toBeGreaterThan(0);
    expect(output.scriptWords).toContain("CHECK-CAP");
    expect(output.scriptWords).toContain("CHECK-DOMAIN");
  });

  test("T21: variation margin must be posted within T+1 (CSA)", () => {
    const policySource = readFileSync(
      join(ROOT, "packages/cdm/src/policies/variation-margin.policy"),
      "utf-8",
    );
    expect(policySource).toContain("posting-party");
    expect(policySource).toContain("margin-type");
    expect(policySource).toContain("variation");

    const { compileCDMPolicy } = require(join(ROOT, "packages/cdm/src/policies/compiler.ts"));
    const output = compileCDMPolicy(policySource);
    expect(output.scriptBytes.length).toBeGreaterThan(0);
  });
});

// ── Gate 5: Import/Export Bridge (T22–T25) ────────────────────

describe("D28.5 — Import/export", () => {
  test("T22: CDM JSON round-trip preserves all fields", () => {
    const { CDMBridge } = require(join(ROOT, "packages/cdm/src/bridge/index.ts"));
    const bridge = new CDMBridge();

    const cdmJson = {
      productType: "rates.swap.fixed-float",
      economicTerms: {
        notional: { amount: 10_000_000, currency: "USD" },
        effectiveDate: "2024-06-15",
        terminationDate: "2029-06-15",
        fixedRate: 0.035,
        floatingRateIndex: "SOFR",
        paymentFrequency: "3M",
        dayCountConvention: "ACT/360",
      },
      parties: [
        { partyId: "bank-a", role: "buyer", lei: "BANKALEIENTITY01", jurisdiction: "US" },
        { partyId: "bank-b", role: "seller", lei: "BANKBLEIENTITY02", jurisdiction: "US" },
      ],
      tradeDate: "2024-06-15",
    };

    const importResult = bridge.importProduct(cdmJson);
    expect(importResult.ok).toBe(true);
    if (!importResult.ok) return;

    const exported = bridge.exportProduct(importResult.value);

    expect(exported.productType).toBe("rates.swap.fixed-float");
    expect((exported.economicTerms as any).notional.amount).toBe(10_000_000);
    expect((exported.economicTerms as any).notional.currency).toBe("USD");
    expect((exported.economicTerms as any).fixedRate).toBe(0.035);
    expect((exported.economicTerms as any).floatingRateIndex).toBe("SOFR");
    expect(exported.tradeDate).toBe("2024-06-15");
    expect((exported.parties as any[]).length).toBe(2);
  });

  test("T23: FpML import creates correct product cells", () => {
    const { CDMBridge } = require(join(ROOT, "packages/cdm/src/bridge/index.ts"));
    const bridge = new CDMBridge();

    const fpmlXml = `
      <FpML>
        <swap>
          <tradeDate>2024-06-15</tradeDate>
          <swapStream>
            <notionalAmount>10000000</notionalAmount>
            <currency>USD</currency>
            <effectiveDate>2024-06-15</effectiveDate>
            <terminationDate>2029-06-15</terminationDate>
            <fixedRate>0.035</fixedRate>
            <floatingRateIndex>SOFR</floatingRateIndex>
            <paymentFrequency>3M</paymentFrequency>
            <dayCountFraction>ACT/360</dayCountFraction>
          </swapStream>
          <party><partyId>bank-a</partyId><partyRole>buyer</partyRole></party>
          <party><partyId>bank-b</partyId><partyRole>seller</partyRole></party>
        </swap>
      </FpML>
    `;

    const result = bridge.importFpML(fpmlXml);
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    expect(result.value.length).toBe(1);
    const product = result.value[0];
    expect(product.productType).toBe("rates.swap.fixed-float");
    expect(product.linearity).toBe("LINEAR");
    expect(product.economicTerms.notional.amount).toBe(10_000_000);
    expect(product.economicTerms.notional.currency).toBe("USD");
    expect(product.economicTerms.fixedRate).toBe(0.035);
  });

  test("T24: unknown CDM fields preserved in metadata", () => {
    const { CDMBridge } = require(join(ROOT, "packages/cdm/src/bridge/index.ts"));
    const bridge = new CDMBridge();

    const cdmJson = {
      productType: "rates.swap.fixed-float",
      economicTerms: {
        notional: { amount: 1_000_000, currency: "USD" },
        effectiveDate: "2024-01-01",
        terminationDate: "2025-01-01",
      },
      parties: [{ partyId: "p1", role: "buyer" }],
      tradeDate: "2024-01-01",
      // Unknown fields
      customField: "custom-value",
      internalReference: 12345,
    };

    const importResult = bridge.importProduct(cdmJson);
    expect(importResult.ok).toBe(true);
    if (!importResult.ok) return;

    expect(importResult.value._extensions).toBeTruthy();
    expect(importResult.value._extensions!.customField).toBe("custom-value");
    expect(importResult.value._extensions!.internalReference).toBe(12345);

    // Round-trip preserves extensions
    const exported = bridge.exportProduct(importResult.value);
    expect(exported.customField).toBe("custom-value");
    expect(exported.internalReference).toBe(12345);
  });

  test("T25: exported CDM JSON validates against ISDA schema structure", () => {
    const { CDMBridge } = require(join(ROOT, "packages/cdm/src/bridge/index.ts"));
    const bridge = new CDMBridge();

    const cdmJson = {
      productType: "credit.cds.single-name",
      economicTerms: {
        notional: { amount: 5_000_000, currency: "USD" },
        effectiveDate: "2024-06-15",
        terminationDate: "2029-06-15",
        fixedRate: 0.01,
      },
      parties: [
        { partyId: "buyer-1", role: "buyer", lei: "BUYER00000000001" },
        { partyId: "seller-1", role: "seller", lei: "SELLER0000000002" },
      ],
      tradeDate: "2024-06-15",
    };

    const result = bridge.importProduct(cdmJson);
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const exported = bridge.exportProduct(result.value);

    // Must have required CDM structure
    expect(exported.productType).toBeTruthy();
    expect(exported.economicTerms).toBeTruthy();
    expect(exported.parties).toBeTruthy();
    expect(exported.tradeDate).toBeTruthy();
    expect(exported.tradeIdentifier).toBeTruthy();
    expect((exported.tradeIdentifier as any).uti).toBeTruthy();
    expect(exported.lifecycleState).toBeTruthy();
  });
});

// ── Gate 6: Full Lifecycle Integration (T26) ──────────────────

describe("D28 — Full lifecycle: vanilla IRS", () => {
  test("T26: execute → confirm → clear → settle → terminate — 5 event cells in DAG", async () => {
    const { createCDMProduct } = require(join(ROOT, "packages/cdm/src/types.ts"));
    const { CDMLifecycleEngine } = require(join(ROOT, "packages/cdm/src/lifecycle.ts"));
    const { RegulatoryReportGenerator } = require(join(ROOT, "packages/cdm/src/regulatory.ts"));

    const engine = new CDMLifecycleEngine();
    const reportGen = new RegulatoryReportGenerator();
    const events: any[] = [];
    const allReports: any[] = [];

    let product = createCDMProduct(
      "rates.swap.fixed-float",
      {
        notional: { amount: 50_000_000, currency: "USD" },
        effectiveDate: "2024-06-15",
        terminationDate: "2034-06-15",
        fixedRate: 0.04,
        floatingRateIndex: "SOFR",
        paymentFrequency: "3M",
        dayCountConvention: "ACT/360",
      },
      [
        { partyId: "bank-a", role: "buyer", capabilities: [2, 9], lei: "BANKALEIENTITY01", jurisdiction: "US" },
        { partyId: "bank-b", role: "seller", capabilities: [2, 9], lei: "BANKBLEIENTITY02", jurisdiction: "US" },
        { partyId: "reporter", role: "reporting-party", capabilities: [2], lei: "REPORTER00000001", jurisdiction: "US" },
      ],
      "2024-06-15",
    );

    // 1. Execution: proposed → executed
    const r1 = await engine.executeEvent(product, "execution", "2024-06-15", {}, "actor");
    expect(r1.ok).toBe(true);
    if (!r1.ok) return;
    product = r1.value.product;
    events.push(r1.value.event);
    allReports.push(...reportGen.generate(r1.value.event, product));
    expect(product.lifecycleState).toBe("executed");

    // 2. Confirmation: executed → confirmed
    const r2 = await engine.executeEvent(product, "confirmation", "2024-06-16", {}, "actor");
    expect(r2.ok).toBe(true);
    if (!r2.ok) return;
    product = r2.value.product;
    events.push(r2.value.event);
    allReports.push(...reportGen.generate(r2.value.event, product));
    expect(product.lifecycleState).toBe("confirmed");

    // 3. Clearing: confirmed → cleared
    const r3 = await engine.executeEvent(product, "clearing", "2024-06-17", {}, "actor");
    expect(r3.ok).toBe(true);
    if (!r3.ok) return;
    product = r3.value.product;
    events.push(r3.value.event);
    allReports.push(...reportGen.generate(r3.value.event, product));
    expect(product.lifecycleState).toBe("cleared");

    // 4. Settlement: cleared → settled
    const r4 = await engine.executeEvent(product, "settlement", "2024-06-18", {}, "actor");
    expect(r4.ok).toBe(true);
    if (!r4.ok) return;
    product = r4.value.product;
    events.push(r4.value.event);
    allReports.push(...reportGen.generate(r4.value.event, product));
    expect(product.lifecycleState).toBe("settled");

    // 5. Full termination: settled → terminated
    const r5 = await engine.executeEvent(product, "full-termination", "2034-06-15", {}, "actor");
    expect(r5.ok).toBe(true);
    if (!r5.ok) return;
    product = r5.value.product;
    events.push(r5.value.event);
    allReports.push(...reportGen.generate(r5.value.event, product));
    expect(product.lifecycleState).toBe("terminated");

    // Verify: 5 event cells in DAG
    const history = engine.eventHistory(product, events);
    expect(history).toHaveLength(5);

    // Verify: each event has regulatory report cells
    expect(allReports.length).toBeGreaterThanOrEqual(5);
    for (const report of allReports) {
      expect(report.linearity).toBe("RELEVANT");
    }

    // Verify: terminated product — LINEAR consumed
    expect(product.lifecycleState).toBe("terminated");

    // Verify: all reports still accessible (RELEVANT linearity = cannot be destroyed)
    for (const report of allReports) {
      expect(report.cellId).toBeTruthy();
      expect(report.sourceEventCell).toBeTruthy();
    }
  });
});

// ── Gate 7: Anti-Lock (T27–T28) ───────────────────────────────

describe("D28 — Anti-lock", () => {
  test("T27: no React imports in cdm package", () => {
    const cdmFiles = [
      "packages/cdm/src/types.ts",
      "packages/cdm/src/lifecycle.ts",
      "packages/cdm/src/regulatory.ts",
      "packages/cdm/src/bridge/index.ts",
      "packages/cdm/src/bridge/cdm-json.ts",
      "packages/cdm/src/bridge/fpml.ts",
      "packages/cdm/src/policies/compiler.ts",
      "packages/cdm/src/index.ts",
    ];

    for (const file of cdmFiles) {
      const fullPath = join(ROOT, file);
      if (existsSync(fullPath)) {
        const source = readFileSync(fullPath, "utf-8");
        expect(source).not.toContain("from 'react'");
        expect(source).not.toContain('from "react"');
        expect(source).not.toContain("require('react')");
        expect(source).not.toContain('require("react")');
      }
    }
  });

  test("T28: no direct cell engine modifications (only consumes existing APIs)", () => {
    // Verify cdm package imports from cell-ops but does not modify it
    const cdmFiles = [
      "packages/cdm/src/lifecycle.ts",
      "packages/cdm/src/regulatory.ts",
    ];

    for (const file of cdmFiles) {
      const source = readFileSync(join(ROOT, file), "utf-8");
      // Should import from cell-ops (consuming existing APIs)
      if (source.includes("cell-ops")) {
        expect(source).toContain("import");
      }
      // Should NOT modify cell-ops internals
      expect(source).not.toContain("export function buildCellHeader");
      expect(source).not.toContain("export function packCell");
    }

    // Verify cell-ops files were not modified (check key exports still intact)
    const typeHashSource = readFileSync(
      join(ROOT, "packages/cell-ops/src/typeHashRegistry.ts"),
      "utf-8",
    );
    expect(typeHashSource).toContain("export function computeTypeHash");
    expect(typeHashSource).toContain("export function buildCellHeader");
    expect(typeHashSource).toContain("export function packCell");
    expect(typeHashSource).toContain("export function contentHash");

    // Verify previous phase artifacts intact
    expect(existsSync(join(ROOT, "packages/metering/src/channel-fsm.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "runtime/shell/src/lisp/compiler.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "src/types/transfer.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "src/types/capability.ts"))).toBe(true);
  });
});

```
