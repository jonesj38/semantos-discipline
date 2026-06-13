---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/demo.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.493027+00:00
---

# packages/cdm/cdm/demo.ts

```ts
#!/usr/bin/env bun
/**
 * Phase 28 — ISDA CDM Integration Demo
 *
 * Demonstrates the full spectrum of Semantos CDM capabilities:
 *
 *   1. Product creation — vanilla IRS as a LINEAR cell
 *   2. Full lifecycle — execute → confirm → clear → settle → terminate
 *   3. Regulatory reporting — CFTC + EMIR reports as RELEVANT cells
 *   4. Novation — Phase 17 transfer of counterparty
 *   5. Partial termination — AFFINE notional reduction
 *   6. Close-out netting — portfolio-level net obligation
 *   7. ISDA policy compilation — Lisp → capability cells
 *   8. CDM JSON round-trip — with unknown field preservation
 *   9. FpML import/export — XML ↔ CDMProduct
 *  10. Multi-product portfolio — IRS, CDS, FX forward
 *
 * Run: bun run packages/cdm/demo.ts
 */

import {
  createCDMProduct,
  computeCDMTypeHash,
  generateUTI,
  CDMLifecycleEngine,
  RegulatoryReportGenerator,
  CDMBridge,
  compileCDMPolicy,
  loadAllPolicies,
  POLICY_NAMES,
  type CDMProduct,
  type CDMLifecycleEvent,
  type CDMPartyRole,
} from './src/index';

// ── Helpers ──────────────────────────────────────────────────

const HR = '─'.repeat(72);
const SECTION = (n: number, title: string) =>
  console.log(`\n${'═'.repeat(72)}\n  ${n}. ${title}\n${'═'.repeat(72)}`);

const OK = '  ✓';
const FAIL = '  ✗';

function assert(condition: boolean, msg: string) {
  if (condition) console.log(`${OK} ${msg}`);
  else {
    console.log(`${FAIL} ${msg}`);
    process.exit(1);
  }
}

function printProduct(p: CDMProduct) {
  console.log(`    cellId:    ${p.cellId}`);
  console.log(`    type:      ${p.productType}`);
  console.log(`    linearity: ${p.linearity}`);
  console.log(`    state:     ${p.lifecycleState}`);
  console.log(`    notional:  ${p.economicTerms.notional.amount.toLocaleString()} ${p.economicTerms.notional.currency}`);
  console.log(`    UTI:       ${p.uti}`);
  console.log(`    typeHash:  ${p.typeHashHex.slice(0, 16)}…`);
}

function printEvent(e: CDMLifecycleEvent) {
  console.log(`    ${e.before} → ${e.after}  [${e.eventType}]  ${e.effectiveDate}`);
}

// ── Instantiate engines ──────────────────────────────────────

const engine = new CDMLifecycleEngine();
const reporter = new RegulatoryReportGenerator();
const bridge = new CDMBridge();
const allEvents: CDMLifecycleEvent[] = [];

console.log(`\n${'█'.repeat(72)}`);
console.log(`  Semantos Phase 28 — ISDA CDM Integration Demo`);
console.log(`${'█'.repeat(72)}`);

// ══════════════════════════════════════════════════════════════
//  1. Product Creation — Vanilla IRS
// ══════════════════════════════════════════════════════════════

SECTION(1, 'Product Creation — Vanilla IRS as LINEAR Cell');

const acmeBank: CDMPartyRole = {
  partyId: 'ACME-BANK',
  role: 'buyer',
  capabilities: [0x0001, 0x0002],
  lei: 'ACME00000000000001',
  jurisdiction: 'US',
  hatCertId: 'cert-acme-001',
};

const globalCorp: CDMPartyRole = {
  partyId: 'GLOBAL-CORP',
  role: 'seller',
  capabilities: [0x0001],
  lei: 'GLOB00000000000002',
  jurisdiction: 'EU',
  hatCertId: 'cert-glob-001',
};

let irs = createCDMProduct(
  'rates.swap.fixed-float',
  {
    notional: { amount: 50_000_000, currency: 'USD' },
    effectiveDate: '2026-04-01',
    terminationDate: '2031-04-01',
    fixedRate: 0.0325,
    floatingRateIndex: 'USD-SOFR-OIS',
    paymentFrequency: '6M',
    dayCountConvention: 'ACT/360',
    businessDayConvention: 'MODFOLLOWING',
  },
  [acmeBank, globalCorp],
  '2026-03-31',
  ['reporting.cftc', 'hedging.interest-rate'],
);

console.log('\n  Created $50M USD fixed-float IRS:');
printProduct(irs);

assert(irs.linearity === 'LINEAR', 'Product linearity is LINEAR');
assert(irs.lifecycleState === 'proposed', 'Initial state is proposed');
assert(irs.typeHashHex.length === 64, 'Type hash is SHA-256 (64 hex chars)');
assert(irs.uti.includes('ACME000000'), 'UTI contains LEI prefix');

// Verify type hash is deterministic
const hash2 = computeCDMTypeHash('rates.swap.fixed-float');
assert(irs.typeHashHex === hash2, 'Type hash is deterministic');

// ══════════════════════════════════════════════════════════════
//  2. Full Lifecycle — Execute → Confirm → Clear → Settle → Terminate
// ══════════════════════════════════════════════════════════════

SECTION(2, 'Full Lifecycle — 5 State Transitions');

const transitions: Array<{
  event: Parameters<typeof engine.executeEvent>[1];
  date: string;
  desc: string;
}> = [
  { event: 'execution',    date: '2026-03-31', desc: 'Trade executed on SEF' },
  { event: 'confirmation', date: '2026-04-01', desc: 'Electronic confirmation matched' },
  { event: 'clearing',     date: '2026-04-02', desc: 'Cleared via LCH SwapClear' },
  { event: 'settlement',   date: '2026-04-03', desc: 'Initial margin settled' },
  { event: 'full-termination', date: '2031-04-01', desc: 'Maturity reached — trade consumed' },
];

for (const { event, date, desc } of transitions) {
  const validBefore = engine.getValidEvents(irs.lifecycleState);
  const result = engine.executeEvent(irs, event, date, {}, 'cert-acme-001');

  if (!result.ok) {
    console.log(`${FAIL} ${desc}: ${result.error}`);
    process.exit(1);
  }

  const prev = irs.lifecycleState;
  irs = result.value.product;
  allEvents.push(result.value.event);

  console.log(`\n  ${prev} → ${irs.lifecycleState}  [${event}]`);
  console.log(`    ${desc}`);
  console.log(`    Cell size: ${result.value.cell.length} bytes`);
  console.log(`    Valid events were: [${validBefore.join(', ')}]`);

  assert(result.value.cell.length === 1024, `Cell is exactly 1024 bytes`);
}

assert(irs.lifecycleState === 'terminated', 'Final state is terminated');
assert(allEvents.length === 5, '5 events in DAG');

// Verify invalid transition is rejected
const badResult = engine.executeEvent(irs, 'execution', '2031-05-01', {}, 'cert-acme-001');
assert(!badResult.ok, 'Cannot execute on terminated product (rejected)');
console.log(`    Error: "${(badResult as { ok: false; error: string }).error.slice(0, 60)}…"`);

// Verify event history
const history = engine.eventHistory(irs, allEvents);
assert(history.length === 5, 'Event history contains 5 events');
console.log('\n  Event DAG (ordered):');
for (const e of history) printEvent(e);

// ══════════════════════════════════════════════════════════════
//  3. Regulatory Reporting — CFTC + EMIR as RELEVANT Cells
// ══════════════════════════════════════════════════════════════

SECTION(3, 'Regulatory Reporting — RELEVANT Cells');

// Create a fresh product for reporting (terminated one can't generate events)
let irsForReporting = createCDMProduct(
  'rates.swap.fixed-float',
  {
    notional: { amount: 75_000_000, currency: 'USD' },
    effectiveDate: '2026-04-01',
    terminationDate: '2031-04-01',
    fixedRate: 0.035,
    floatingRateIndex: 'USD-SOFR-OIS',
    paymentFrequency: '3M',
    dayCountConvention: 'ACT/360',
  },
  [acmeBank, globalCorp],
  '2026-03-31',
  ['reporting.cftc', 'reporting.emir'],
);

// Execute to generate an event for reporting
const execResult = engine.executeEvent(irsForReporting, 'execution', '2026-03-31', {}, 'cert-acme-001');
assert(execResult.ok, 'Execution event for reporting product');
irsForReporting = (execResult as { ok: true; value: { product: CDMProduct; event: CDMLifecycleEvent } }).value.product;
const execEvent = (execResult as { ok: true; value: { event: CDMLifecycleEvent } }).value.event;

// Determine applicable regimes
const regimes = reporter.applicableRegimes(irsForReporting);
console.log(`\n  Applicable regimes: [${regimes.join(', ')}]`);
assert(regimes.includes('CFTC'), 'CFTC applies (USD + US party)');
assert(regimes.includes('EMIR'), 'EMIR applies (EU counterparty)');

// Generate reports
const reports = reporter.generate(execEvent, irsForReporting);
console.log(`  Generated ${reports.length} regulatory reports:\n`);

for (const report of reports) {
  console.log(`    Regime:     ${report.regime}`);
  console.log(`    Linearity:  ${report.linearity}`);
  console.log(`    UTI:        ${report.uti}`);
  console.log(`    Source:     ${report.sourceEventCell}`);
  console.log(`    Taxonomy:   ${report.productTaxonomy}`);
  assert(report.linearity === 'RELEVANT', `${report.regime} report is RELEVANT (immutable)`);

  // Pack as cell
  const cellBytes = reporter.packReportCell(report);
  console.log(`    Cell size:  ${cellBytes.length} bytes`);
  assert(cellBytes.length === 1024, `${report.regime} report cell is 1024 bytes`);

  // Format for submission
  const formatted = reporter.format(report, report.regime);
  console.log(`    Format:     ${(formatted as { reportFormat?: string }).reportFormat}`);
  console.log('');
}

// ══════════════════════════════════════════════════════════════
//  4. Novation — Phase 17 Transfer
// ══════════════════════════════════════════════════════════════

SECTION(4, 'Novation — Counterparty Transfer via Phase 17');

let novProduct = createCDMProduct(
  'rates.swap.fixed-float',
  {
    notional: { amount: 25_000_000, currency: 'EUR' },
    effectiveDate: '2026-04-15',
    terminationDate: '2029-04-15',
    fixedRate: 0.028,
    floatingRateIndex: 'EUR-ESTR',
    paymentFrequency: '6M',
    dayCountConvention: '30/360',
  },
  [acmeBank, globalCorp],
  '2026-03-31',
);

// Execute first (can't novate from proposed)
const novExec = engine.executeEvent(novProduct, 'execution', '2026-03-31', {}, 'cert-acme-001');
assert(novExec.ok, 'Execute product before novation');
novProduct = (novExec as { ok: true; value: { product: CDMProduct } }).value.product;

const newCounterparty: CDMPartyRole = {
  partyId: 'SUMMIT-CAPITAL',
  role: 'seller',
  capabilities: [0x0001],
  lei: 'SUMM00000000000003',
  jurisdiction: 'SG',
  hatCertId: 'cert-summ-001',
};

console.log(`\n  Before novation:`);
console.log(`    Seller: ${novProduct.parties.find(p => p.role === 'seller')?.partyId}`);
console.log(`    State:  ${novProduct.lifecycleState}`);

const novResult = engine.novate(novProduct, globalCorp, newCounterparty, 'cert-acme-001');

if (novResult.ok) {
  novProduct = novResult.value.product;
  const tr = novResult.value.transferRecord;

  console.log(`\n  After novation:`);
  console.log(`    Seller: ${novProduct.parties.find(p => p.role === 'seller')?.partyId}`);
  console.log(`    State:  ${novProduct.lifecycleState}`);
  console.log(`\n  Phase 17 TransferRecord:`);
  console.log(`    resourceId:      ${tr.resourceId}`);
  console.log(`    objectCertId:    ${tr.objectCertId}`);
  console.log(`    fromParentCert:  ${tr.fromParentCertId}`);
  console.log(`    toParentCert:    ${tr.toParentCertId}`);
  console.log(`    transferTxId:    ${tr.transferTxId}`);

  assert(novProduct.lifecycleState === 'novated', 'Product is novated');
  assert(tr.fromParentCertId === 'cert-glob-001', 'Transfer from old party');
  assert(tr.toParentCertId === 'cert-summ-001', 'Transfer to new party');
} else {
  console.log(`${FAIL} Novation failed: ${novResult.error}`);
  process.exit(1);
}

// ══════════════════════════════════════════════════════════════
//  5. Partial Termination — AFFINE Notional Reduction
// ══════════════════════════════════════════════════════════════

SECTION(5, 'Partial Termination — AFFINE Notional Reduction');

let partialProduct = createCDMProduct(
  'credit.cds.single-name',
  {
    notional: { amount: 10_000_000, currency: 'USD' },
    effectiveDate: '2026-04-01',
    terminationDate: '2031-04-01',
    fixedRate: 0.01,
  },
  [acmeBank, globalCorp],
  '2026-03-31',
);

// Execute → Confirm to reach a state that supports partial termination
const ptExec = engine.executeEvent(partialProduct, 'execution', '2026-03-31', {}, 'cert-acme-001');
partialProduct = (ptExec as { ok: true; value: { product: CDMProduct } }).value.product;
const ptConf = engine.executeEvent(partialProduct, 'confirmation', '2026-04-01', {}, 'cert-acme-001');
partialProduct = (ptConf as { ok: true; value: { product: CDMProduct } }).value.product;

console.log(`\n  Before partial termination:`);
console.log(`    Notional: ${partialProduct.economicTerms.notional.amount.toLocaleString()} USD`);
console.log(`    State:    ${partialProduct.lifecycleState}`);

const ptResult = engine.partialTerminate(partialProduct, 3_000_000, 'cert-acme-001');

if (ptResult.ok) {
  partialProduct = ptResult.value.product;
  console.log(`\n  After partial termination (reduced by $3M):`);
  console.log(`    Notional: ${partialProduct.economicTerms.notional.amount.toLocaleString()} USD`);
  console.log(`    State:    ${partialProduct.lifecycleState}`);

  assert(partialProduct.economicTerms.notional.amount === 7_000_000, 'Notional reduced to $7M');
  assert(partialProduct.lifecycleState === 'partially-terminated', 'State is partially-terminated');
}

// Second partial termination (AFFINE allows multiple reductions)
const ptResult2 = engine.partialTerminate(partialProduct, 2_000_000, 'cert-acme-001');
if (ptResult2.ok) {
  partialProduct = ptResult2.value.product;
  console.log(`\n  Second reduction (−$2M):`);
  console.log(`    Notional: ${partialProduct.economicTerms.notional.amount.toLocaleString()} USD`);
  assert(partialProduct.economicTerms.notional.amount === 5_000_000, 'Notional reduced to $5M');
}

// Attempt over-termination
const overTermResult = engine.partialTerminate(partialProduct, 5_000_000, 'cert-acme-001');
assert(!overTermResult.ok, 'Cannot partially terminate entire notional (use full termination)');
console.log(`    Guard: "${(overTermResult as { ok: false; error: string }).error.slice(0, 60)}…"`);

// ══════════════════════════════════════════════════════════════
//  6. Close-Out Netting — Portfolio Net Obligation
// ══════════════════════════════════════════════════════════════

SECTION(6, 'Close-Out Netting — Portfolio Net Obligation');

const defaultedParty: CDMPartyRole = {
  partyId: 'DEFAULTER-INC',
  role: 'buyer',
  capabilities: [],
  lei: 'DFLT00000000000004',
  jurisdiction: 'US',
};

const nonDefaulter: CDMPartyRole = {
  partyId: 'SOLVENT-BANK',
  role: 'seller',
  capabilities: [0x0001],
  lei: 'SOLV00000000000005',
  jurisdiction: 'US',
};

// Create 3 products, drive them to defaulted state
const netProducts: CDMProduct[] = [];
const notionals = [20_000_000, 15_000_000, 8_000_000];

for (const notional of notionals) {
  let p = createCDMProduct(
    'rates.swap.fixed-float',
    {
      notional: { amount: notional, currency: 'USD' },
      effectiveDate: '2026-04-01',
      terminationDate: '2031-04-01',
      fixedRate: 0.03,
      floatingRateIndex: 'USD-SOFR-OIS',
      paymentFrequency: '3M',
      dayCountConvention: 'ACT/360',
    },
    [defaultedParty, nonDefaulter],
    '2026-03-31',
  );

  // Drive to executed → confirmed → defaulted
  const r1 = engine.executeEvent(p, 'execution', '2026-03-31', {}, 'cert-solv-001');
  p = (r1 as { ok: true; value: { product: CDMProduct } }).value.product;
  const r2 = engine.executeEvent(p, 'confirmation', '2026-04-01', {}, 'cert-solv-001');
  p = (r2 as { ok: true; value: { product: CDMProduct } }).value.product;
  const r3 = engine.executeEvent(p, 'default', '2026-04-10', {}, 'cert-solv-001');
  p = (r3 as { ok: true; value: { product: CDMProduct } }).value.product;

  netProducts.push(p);
}

console.log(`\n  Portfolio of ${netProducts.length} defaulted trades:`);
for (const p of netProducts) {
  console.log(`    ${p.cellId.slice(0, 12)}…  ${p.economicTerms.notional.amount.toLocaleString()} USD  [${p.lifecycleState}]`);
}

const netResult = engine.closeOutNet(netProducts, defaultedParty, 'cert-solv-001');

if (netResult.ok) {
  const { netAmount, currency, events, products } = netResult.value;
  console.log(`\n  Close-out netting result:`);
  console.log(`    Net amount: ${netAmount.toLocaleString()} ${currency}`);
  console.log(`    Events:     ${events.length} close-out-netting events`);
  console.log(`    Products:   all ${products.length} transitioned to close-out`);

  assert(netAmount === 43_000_000, 'Net amount is sum of notionals (buyer signed +)');
  assert(products.every(p => p.lifecycleState === 'close-out'), 'All products in close-out state');
}

// Verify close-out state portfolio is rejected (already netted)
const badNet = engine.closeOutNet(
  [netResult.value.products[0]],
  defaultedParty,
  'cert-solv-001',
);
assert(!badNet.ok, 'Cannot re-net already closed-out portfolio');
console.log(`    Guard: "${(badNet as { ok: false; error: string }).error.slice(0, 60)}…"`);

// ══════════════════════════════════════════════════════════════
//  7. ISDA Policy Compilation — Lisp → Capability Cells
// ══════════════════════════════════════════════════════════════

SECTION(7, 'ISDA Policy Compilation — Lisp → Capability Cells');

console.log(`\n  Compiling ${POLICY_NAMES.length} ISDA Master Agreement policies:\n`);

const policies = loadAllPolicies();
assert(policies.size === 5, 'All 5 ISDA policies compiled');

for (const [name, output] of policies) {
  console.log(`    ${name}`);
  console.log(`      opcodes: ${output.scriptBytes.length} bytes`);
  console.log(`      type:    ${output.scriptType ?? 'policy'}`);
  assert(output.scriptBytes.length > 0, `${name} produces non-empty bytecode`);
}

// Compile a custom inline policy (numeric/string literals only in constraints)
const customPolicy = `(policy
  :subject clearing-member
  :action submit-margin
  :constraint (and
    (>= margin-amount 1000000)
    (< time-since-call 86400)
    (has-capability 1))
  :linearity LINEAR)`;

const customOutput = compileCDMPolicy(customPolicy);
console.log(`\n  Custom margin policy compiled:`);
console.log(`    opcodes: ${customOutput.scriptBytes.length} bytes`);
assert(customOutput.scriptBytes.length > 0, 'Custom policy compiles');

// ══════════════════════════════════════════════════════════════
//  8. CDM JSON Round-Trip
// ══════════════════════════════════════════════════════════════

SECTION(8, 'CDM JSON Round-Trip with Extension Preservation');

const cdmJson: Record<string, unknown> = {
  productType: 'credit.cds.single-name',
  economicTerms: {
    notional: { amount: 5_000_000, currency: 'EUR' },
    effectiveDate: '2026-06-01',
    terminationDate: '2031-06-01',
    fixedRate: 0.01,
  },
  parties: [
    { partyId: 'ALPHA-FUND', role: 'buyer', lei: 'ALPH00000000000006', jurisdiction: 'DE' },
    { partyId: 'BETA-BANK', role: 'seller', lei: 'BETA00000000000007', jurisdiction: 'US' },
  ],
  tradeDate: '2026-05-30',
  regulatoryObligations: ['reporting.emir', 'reporting.cftc'],
  // Unknown extension fields (proprietary)
  internalTradeId: 'ALPHA-2026-CDS-0042',
  clearingBroker: 'JPMC',
  customRiskBucket: 'IG-5Y',
};

console.log('\n  Input CDM JSON:');
console.log(`    productType:     ${cdmJson.productType}`);
console.log(`    internalTradeId: ${cdmJson.internalTradeId}  (extension)`);
console.log(`    clearingBroker:  ${cdmJson.clearingBroker}  (extension)`);
console.log(`    customRiskBucket:${cdmJson.customRiskBucket}  (extension)`);

const importResult = bridge.importProduct(cdmJson);
assert(importResult.ok, 'CDM JSON import succeeds');

if (importResult.ok) {
  const product = importResult.value;
  console.log('\n  Imported product:');
  printProduct(product);
  console.log(`    _extensions: ${JSON.stringify(product._extensions)}`);

  assert(product._extensions?.internalTradeId === 'ALPHA-2026-CDS-0042', 'Extension field preserved: internalTradeId');
  assert(product._extensions?.clearingBroker === 'JPMC', 'Extension field preserved: clearingBroker');
  assert(product._extensions?.customRiskBucket === 'IG-5Y', 'Extension field preserved: customRiskBucket');

  // Export back to JSON
  const exported = bridge.exportProduct(product);
  console.log('\n  Re-exported CDM JSON:');
  console.log(`    productType:     ${exported.productType}`);
  console.log(`    internalTradeId: ${exported.internalTradeId}  (round-tripped)`);
  console.log(`    clearingBroker:  ${exported.clearingBroker}  (round-tripped)`);

  assert(exported.productType === cdmJson.productType, 'productType round-trips');
  assert(exported.internalTradeId === cdmJson.internalTradeId, 'Extension round-trips: internalTradeId');
  assert(exported.clearingBroker === cdmJson.clearingBroker, 'Extension round-trips: clearingBroker');

  // Verify economic terms
  const et = exported.economicTerms as { notional: { amount: number } };
  assert(et.notional.amount === 5_000_000, 'Notional round-trips');
}

// ══════════════════════════════════════════════════════════════
//  9. FpML Import/Export
// ══════════════════════════════════════════════════════════════

SECTION(9, 'FpML Import/Export — XML ↔ CDMProduct');

const fpmlIRS = `<?xml version="1.0" encoding="UTF-8"?>
<FpML xmlns="http://www.fpml.org/FpML-5/confirmation" version="5-12">
  <swap>
    <tradeDate>2026-04-15</tradeDate>
    <swapStream>
      <notionalAmount>100000000</notionalAmount>
      <currency>USD</currency>
      <effectiveDate>2026-04-17</effectiveDate>
      <terminationDate>2036-04-17</terminationDate>
      <fixedRate>0.04</fixedRate>
      <floatingRateIndex>USD-SOFR-OIS</floatingRateIndex>
      <paymentFrequency>3M</paymentFrequency>
      <dayCountFraction>ACT/360</dayCountFraction>
    </swapStream>
    <party><partyId>DEALER-A</partyId><partyRole>buyer</partyRole></party>
    <party><partyId>DEALER-B</partyId><partyRole>seller</partyRole></party>
  </swap>
</FpML>`;

console.log('\n  Importing FpML vanilla IRS ($100M, 10Y, 4% fixed vs SOFR):');

const fpmlResult = bridge.importFpML(fpmlIRS);
assert(fpmlResult.ok, 'FpML import succeeds');

if (fpmlResult.ok) {
  const products = fpmlResult.value;
  assert(products.length === 1, 'One product imported');
  const p = products[0];
  console.log('');
  printProduct(p);

  assert(p.productType === 'rates.swap.fixed-float', 'Detected as fixed-float swap');
  assert(p.economicTerms.notional.amount === 100_000_000, 'Notional is $100M');
  assert(p.economicTerms.fixedRate === 0.04, 'Fixed rate is 4%');
  assert(p.economicTerms.floatingRateIndex === 'USD-SOFR-OIS', 'Floating index is SOFR');

  // Export back to FpML
  const exportedXml = bridge.exportFpML(products);
  console.log('\n  Re-exported FpML XML (excerpt):');
  const lines = exportedXml.split('\n');
  for (const line of lines.slice(0, 12)) console.log(`    ${line}`);
  console.log('    …');

  assert(exportedXml.includes('<swap>'), 'FpML export contains <swap>');
  assert(exportedXml.includes('100000000'), 'FpML export preserves notional');
  assert(exportedXml.includes('USD-SOFR-OIS'), 'FpML export preserves floating index');
}

// FpML CDS
const fpmlCDS = `<FpML>
  <creditDefaultSwap>
    <tradeDate>2026-04-20</tradeDate>
    <notionalAmount>20000000</notionalAmount>
    <currency>EUR</currency>
    <effectiveDate>2026-04-22</effectiveDate>
    <scheduledTerminationDate>2031-04-22</scheduledTerminationDate>
    <fixedRate>0.0075</fixedRate>
    <entityName>Acme Corp</entityName>
    <party><partyId>PROT-BUYER</partyId><partyRole>buyer</partyRole></party>
    <party><partyId>PROT-SELLER</partyId><partyRole>seller</partyRole></party>
  </creditDefaultSwap>
</FpML>`;

const cdsResult = bridge.importFpML(fpmlCDS);
assert(cdsResult.ok, 'FpML CDS import succeeds');
if (cdsResult.ok) {
  const cds = cdsResult.value[0];
  console.log(`\n  Imported FpML CDS: ${cds.productType}  €${cds.economicTerms.notional.amount.toLocaleString()}`);
  assert(cds.productType === 'credit.cds.single-name', 'CDS product type correct');
}

// FpML FX Forward
const fpmlFX = `<FpML>
  <fxSingleLeg>
    <tradeDate>2026-05-01</tradeDate>
    <amount>50000000</amount>
    <currency>GBP</currency>
    <valueDate>2026-08-01</valueDate>
    <party><partyId>FX-DESK</partyId><partyRole>buyer</partyRole></party>
    <party><partyId>FX-COUNTER</partyId><partyRole>seller</partyRole></party>
  </fxSingleLeg>
</FpML>`;

const fxResult = bridge.importFpML(fpmlFX);
assert(fxResult.ok, 'FpML FX forward import succeeds');
if (fxResult.ok) {
  const fx = fxResult.value[0];
  console.log(`  Imported FpML FX:  ${fx.productType}  £${fx.economicTerms.notional.amount.toLocaleString()}`);
  assert(fx.productType === 'fx.forward.deliverable', 'FX product type correct');
}

// ══════════════════════════════════════════════════════════════
//  10. Multi-Product Portfolio Summary
// ══════════════════════════════════════════════════════════════

SECTION(10, 'Multi-Product Portfolio Summary');

const portfolio = [
  createCDMProduct('rates.swap.fixed-float', {
    notional: { amount: 50_000_000, currency: 'USD' },
    effectiveDate: '2026-04-01', terminationDate: '2031-04-01',
    fixedRate: 0.0325, floatingRateIndex: 'USD-SOFR-OIS',
    paymentFrequency: '6M', dayCountConvention: 'ACT/360',
  }, [acmeBank, globalCorp], '2026-03-31'),

  createCDMProduct('credit.cds.single-name', {
    notional: { amount: 10_000_000, currency: 'EUR' },
    effectiveDate: '2026-04-15', terminationDate: '2031-04-15',
    fixedRate: 0.01,
  }, [
    { ...acmeBank, role: 'buyer' as const, jurisdiction: 'DE' },
    { ...globalCorp, role: 'seller' as const },
  ], '2026-04-10'),

  createCDMProduct('fx.forward.deliverable', {
    notional: { amount: 25_000_000, currency: 'JPY' },
    effectiveDate: '2026-05-01', terminationDate: '2026-08-01',
  }, [
    { ...acmeBank, role: 'buyer' as const, jurisdiction: 'JP' },
    { ...globalCorp, role: 'seller' as const },
  ], '2026-04-28'),

  createCDMProduct('equity.option.vanilla.european', {
    notional: { amount: 5_000_000, currency: 'AUD' },
    effectiveDate: '2026-06-01', terminationDate: '2027-06-01',
  }, [
    { ...acmeBank, role: 'buyer' as const, jurisdiction: 'AU' },
    { ...globalCorp, role: 'seller' as const },
  ], '2026-05-15'),
];

console.log(`\n  Portfolio: ${portfolio.length} products\n`);
console.log('  ┌─────────────────────────────────────┬────────────────────┬──────────┬──────────────┐');
console.log('  │ Product Type                        │ Notional           │ Currency │ Regimes      │');
console.log('  ├─────────────────────────────────────┼────────────────────┼──────────┼──────────────┤');

for (const p of portfolio) {
  const regimes = reporter.applicableRegimes(p);
  const type = p.productType.padEnd(37);
  const notional = p.economicTerms.notional.amount.toLocaleString().padStart(18);
  const curr = p.economicTerms.notional.currency.padEnd(8);
  const reg = regimes.join(', ').padEnd(12);
  console.log(`  │ ${type} │ ${notional} │ ${curr} │ ${reg} │`);
}

console.log('  └─────────────────────────────────────┴────────────────────┴──────────┴──────────────┘');

// Aggregate stats
const totalNotionalUSD = portfolio
  .filter(p => p.economicTerms.notional.currency === 'USD')
  .reduce((sum, p) => sum + p.economicTerms.notional.amount, 0);

const allRegimes = new Set(portfolio.flatMap(p => reporter.applicableRegimes(p)));
console.log(`\n  Total USD notional: $${totalNotionalUSD.toLocaleString()}`);
console.log(`  Unique regimes:    [${[...allRegimes].join(', ')}]`);
console.log(`  All linearity:     ${portfolio.every(p => p.linearity === 'LINEAR') ? 'LINEAR' : 'MIXED'}`);

// ══════════════════════════════════════════════════════════════
//  Summary
// ══════════════════════════════════════════════════════════════

console.log(`\n${'█'.repeat(72)}`);
console.log('  Demo Complete — All Assertions Passed');
console.log(`${'█'.repeat(72)}`);
console.log(`
  Demonstrated:
    • Product creation with 3-axis taxonomy (WHAT / HOW / WHY)
    • Full 5-step lifecycle with 1024-byte cell creation at each step
    • CFTC + EMIR regulatory reports as RELEVANT (immutable) cells
    • Novation via Phase 17 TransferRecord
    • AFFINE partial termination with iterated notional reduction
    • Close-out netting across defaulted portfolio
    • 5 ISDA policies compiled from Lisp to capability cell bytecode
    • CDM JSON round-trip with unknown field preservation
    • FpML import/export for IRS, CDS, and FX forwards
    • Multi-product portfolio with 4 asset classes and 5 regimes
`);

```
