---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/demo-kernel.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.493617+00:00
---

# packages/cdm/cdm/demo-kernel.ts

```ts
#!/usr/bin/env bun
/**
 * CDM Kernel-Path Demo — Phase 29.5
 *
 * Demonstrates the full kernel-enforced lifecycle path:
 * 1. Lisp policy source
 * 2. Compiled script words / bytecode
 * 3. 2-PDA evaluation via PolicyRuntime
 * 4. Host calls that fired
 * 5. Anchor tx envelope (dev mode)
 * 6. Resulting product state
 *
 * Usage: bun run packages/cdm/demo-kernel.ts
 */

import { loadCellEngine } from '../cell-engine/bindings/bun/loader';
import { HostFunctionRegistry } from '../cell-engine/bindings/host-functions';
import { registerBuiltinHostFunctions } from '../cell-engine/bindings/builtin-host-functions';
import { PolicyRuntime } from '../policy-runtime/src/runtime';
import { DevModeAnchorEmitter } from '../policy-runtime/src/anchor-emitter';
import { CDMLifecycleEngine } from './src/lifecycle';
import { createCDMProduct } from './src/types';
import { registerCDMHostFunctions } from './src/policies/host-functions';
import { loadAndCompilePolicy, POLICY_NAMES } from './src/policies/compiler';
import { readFileSync } from 'fs';
import { join } from 'path';

async function main() {
  console.log('=== CDM Kernel-Path Demo (Phase 29.5) ===\n');

  // ── Step 1: Show policy sources ──
  console.log('── ISDA Policy Sources ──\n');
  for (const name of POLICY_NAMES) {
    const policyPath = join(import.meta.dir, 'src', 'policies', `${name}.policy`);
    try {
      const source = readFileSync(policyPath, 'utf-8').trim();
      console.log(`  ${name}:`);
      console.log(`    ${source.split('\n').join('\n    ')}\n`);
    } catch {
      console.log(`  ${name}: (file not found)\n`);
    }
  }

  // ── Step 2: Compile policies and show bytecode ──
  console.log('── Compiled Policy Bytecode ──\n');
  for (const name of POLICY_NAMES) {
    try {
      const compiled = loadAndCompilePolicy(name);
      const hexBytes = Array.from(compiled.scriptBytes)
        .map(b => b.toString(16).padStart(2, '0'))
        .join(' ');
      console.log(`  ${name}:`);
      console.log(`    scriptWords: ${compiled.scriptWords}`);
      console.log(`    scriptBytes: ${hexBytes}`);
      console.log(`    byteLength:  ${compiled.scriptBytes.length}\n`);
    } catch (err) {
      console.log(`  ${name}: compilation error — ${err}\n`);
    }
  }

  // ── Step 3: Set up kernel runtime ──
  console.log('── Setting up Kernel Runtime ──\n');
  const registry = new HostFunctionRegistry();
  registerBuiltinHostFunctions(registry);
  registerCDMHostFunctions(registry);
  console.log(`  Registered host functions: ${registry.list().join(', ')}`);

  let engine;
  try {
    engine = await loadCellEngine({ profile: 'embedded', hostRegistry: registry });
    console.log('  CellEngine loaded (embedded profile)');
  } catch (err) {
    console.log(`  CellEngine load failed: ${err}`);
    console.log('  (This is expected if WASM binary is not built — run zig build first)');
    console.log('\n  Continuing with anchor-only demo...\n');
    engine = null;
  }

  const anchorEmitter = new DevModeAnchorEmitter();
  const runtime = engine ? new PolicyRuntime(engine, registry) : undefined;

  // ── Step 4: Create a product and run lifecycle events ──
  console.log('\n── CDM Lifecycle with Kernel Enforcement ──\n');

  const lifecycleEngine = new CDMLifecycleEngine({
    runtime,
    anchorEmitter,
  });

  const product = createCDMProduct(
    'rates.swap.fixed-float',
    {
      notional: { amount: 10_000_000, currency: 'USD' },
      effectiveDate: '2024-06-15',
      terminationDate: '2029-06-15',
      fixedRate: 0.035,
      floatingRateIndex: 'SOFR',
      paymentFrequency: '3M',
      dayCountConvention: 'ACT/360',
    },
    [
      { partyId: 'bank-a', role: 'buyer' as const, capabilities: [2, 9], lei: 'BANKALEIENTITY01' },
      { partyId: 'bank-b', role: 'seller' as const, capabilities: [2, 9], lei: 'BANKBLEIENTITY02' },
    ],
    '2024-06-15',
  );

  console.log(`  Product: ${product.productType} (${product.lifecycleState})`);
  console.log(`  Notional: ${product.economicTerms.notional.amount} ${product.economicTerms.notional.currency}`);

  // Execute trade
  const execResult = await lifecycleEngine.executeEvent(
    product, 'execution', '2024-06-15', {}, 'trader-a',
  );

  if (execResult.ok) {
    const { product: updatedProduct, event, cell, policyResults, anchorTxId } = execResult.value;
    console.log(`\n  Event: execution → ${updatedProduct.lifecycleState}`);
    console.log(`  Cell size: ${cell.length} bytes`);
    console.log(`  Event ID: ${event.eventId}`);

    if (policyResults && policyResults.length > 0) {
      for (const pr of policyResults) {
        console.log(`  Policy result: ok=${pr.ok}, gas=${pr.gas}`);
        if (pr.hostCalls.length > 0) {
          console.log(`  Host calls:`);
          for (const hc of pr.hostCalls) {
            console.log(`    - ${hc.name} → ${hc.result}`);
          }
        }
      }
    } else {
      console.log('  Policy results: (no kernel runtime — TS-only mode)');
    }

    if (anchorTxId) {
      console.log(`  Anchor txid: ${anchorTxId}`);
    }
  } else {
    console.log(`  REJECTED: ${execResult.error}`);
  }

  console.log('\n=== Demo complete ===');
}

main().catch(console.error);

```
