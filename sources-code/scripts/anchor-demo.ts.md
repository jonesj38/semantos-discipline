---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/anchor-demo.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.318224+00:00
---

# scripts/anchor-demo.ts

```ts
#!/usr/bin/env bun
/**
 * anchor-demo.ts — Live on-chain transactions via metanet-desktop / bsv-desktop.
 *
 * Usage:
 *   bun run scripts/anchor-demo.ts                          # OP_RETURN anchor (receipt)
 *   bun run scripts/anchor-demo.ts --token                  # BRC-48 CellToken (linear object!)
 *   bun run scripts/anchor-demo.ts --token --transition     # Create + state transition (v1 → v2)
 *   bun run scripts/anchor-demo.ts --batch 5                # batch-anchor 5 hashes
 *   bun run scripts/anchor-demo.ts --scheduler              # AnchorScheduler batch cycle
 *   bun run scripts/anchor-demo.ts --stub                   # dry-run (no wallet)
 *   bun run scripts/anchor-demo.ts --port 2121              # bsv-desktop
 *
 * Prerequisites:
 *   - metanet-desktop (or bsv-desktop) running and authenticated
 *   - Wallet has funded UTXOs
 */

import { MemoryAdapter } from '../packages/protocol-types/src/adapters/memory-adapter';
import { CellStore } from '../packages/protocol-types/src/cell-store';
import { CellToken } from '../packages/protocol-types/src/cell-token';
import { deserializeCellHeader } from '../packages/protocol-types/src/cell-header';
import { Linearity } from '../packages/protocol-types/src/constants';
import { BsvAnchorAdapter } from '../packages/protocol-types/src/adapters/bsv-anchor-adapter';
import { StubAnchorAdapter } from '../packages/protocol-types/src/adapters/stub-anchor-adapter';
import { AnchorScheduler } from '../packages/protocol-types/src/anchor-scheduler';
import { WalletClient } from '../packages/protocol-types/src/wallet-client';
import { TransitionValidator } from '../packages/protocol-types/src/transition-validator';
import type { AnchorAdapter, AnchorProof } from '../packages/protocol-types/src/anchor';
import { createHash } from 'crypto';

// ── BEEF helper ──

/**
 * Fetch raw transaction hex from WhatsOnChain and construct BEEF (BRC-62).
 * Uses @bsv/sdk's Beef class to produce a valid BEEF envelope.
 */
async function fetchAndBuildBEEF(txid: string): Promise<string> {
  const { Transaction, Beef } = await import('@bsv/sdk');

  // 1. Fetch raw tx hex from WhatsOnChain
  const wocUrl = `https://api.whatsonchain.com/v1/bsv/main/tx/${txid}/hex`;
  log('BEEF', `Fetching raw tx from WoC: ${txid.slice(0, 16)}...`);

  const res = await fetch(wocUrl, { signal: AbortSignal.timeout(15_000) });
  if (!res.ok) {
    throw new Error(`WoC returned ${res.status} for ${txid}`);
  }
  const rawTxHex = (await res.text()).trim();
  log('BEEF', `Got raw tx: ${rawTxHex.length / 2} bytes`);

  // 2. Parse into a Transaction object
  const tx = Transaction.fromHex(rawTxHex);

  // 3. Build BEEF envelope containing this tx
  const beef = new Beef();
  beef.mergeTransaction(tx);

  const beefHex = beef.toHex();
  log('BEEF', `Constructed BEEF: ${beefHex.length / 2} bytes`);
  return beefHex;
}

// ── CLI args ──

const args = process.argv.slice(2);
const portFlag = args.indexOf('--port');
const port = portFlag !== -1 ? parseInt(args[portFlag + 1], 10) : 3321;
const batchFlag = args.indexOf('--batch');
const batchSize = batchFlag !== -1 ? parseInt(args[batchFlag + 1], 10) : 0;
const useStub = args.includes('--stub');
const useScheduler = args.includes('--scheduler');
const useToken = args.includes('--token');
const useTransition = args.includes('--transition');

const baseUrl = `http://localhost:${port}`;

// ── Helpers ──

function sha256(data: Uint8Array): string {
  return createHash('sha256').update(data).digest('hex');
}

function log(label: string, value: unknown) {
  console.log(`\x1b[36m[${label}]\x1b[0m`, typeof value === 'string' ? value : JSON.stringify(value, null, 2));
}

// ── Main ──

async function main() {
  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('  Semantos Anchor Demo');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // 1. Create a CellStore with some real data
  const storage = new MemoryAdapter();
  const cellStore = new CellStore(storage);

  log('STEP 1', 'Creating cells in CellStore...');

  const jobData = new TextEncoder().encode(JSON.stringify({
    type: 'job',
    title: 'Fix leaking tap in kitchen',
    status: 'open',
    created: new Date().toISOString(),
    location: { suburb: 'Paddington', state: 'QLD' },
  }));

  const cellRef = await cellStore.put('objects/create/job/demo-1', jobData);
  log('Cell created', {
    key: cellRef.key,
    version: cellRef.version,
    contentHash: cellRef.contentHash,
    cellHash: cellRef.cellHash,
  });

  // 2. Read the raw cell bytes and compute state hash
  const rawCell = await storage.read('objects/create/job/demo-1');
  if (!rawCell) throw new Error('Failed to read cell from storage');

  const stateHash = sha256(rawCell);
  log('STEP 2', `State hash: ${stateHash}`);

  // 3. Set up the adapter
  let adapter: AnchorAdapter;

  if (useStub) {
    log('MODE', 'Stub (no wallet, deterministic proofs)');
    adapter = new StubAnchorAdapter({ debugLogging: true });
  } else {
    log('MODE', `Live → ${baseUrl}`);

    // Check wallet connectivity first
    const walletConfig = {
      baseUrl,
      // Long timeout: metanet-desktop shows permission dialogs the user must approve.
      // First call to createAction can take 30+ seconds while user clicks through.
      timeout: 120_000,
      originator: 'semantos-anchor-demo',
      origin: 'http://localhost',
    };
    const wallet = new WalletClient(walletConfig);
    log('STEP 3', 'Checking wallet connectivity...');

    try {
      const auth = await wallet.isAuthenticated();
      log('Wallet', auth ? 'Authenticated ✓' : 'Not authenticated — will try anyway');
    } catch (err: any) {
      log('Wallet', `Connection failed: ${err.message}`);
      log('HINT', `Is metanet-desktop running on port ${port}? Try --stub for dry run.`);
      process.exit(1);
    }

    // Probe wallet capabilities
    try {
      const network = await wallet.getNetwork();
      log('Network', network);
    } catch (err: any) {
      log('Network probe', `(skipped: ${err.message})`);
    }

    try {
      const height = await wallet.getHeight();
      log('Chain height', height);
    } catch (err: any) {
      log('Height probe', `(skipped: ${err.message})`);
    }

    adapter = new BsvAnchorAdapter(
      { mode: 'bsv', network: 'mainnet', debugLogging: true },
      { ...walletConfig, timeout: 120_000 },
    );

    log('READY', 'About to call createAction — approve any permission dialogs in metanet-desktop.');
  }

  // 4. Dispatch mode
  if (useToken && !useStub) {
    // ── CellToken mode: BRC-48 PushDrop linear object on-chain ──
    await runCellTokenMode(rawCell, cellRef, stateHash, baseUrl, useTransition);

  } else if (batchSize > 0) {
    // ── Batch mode ──
    log('STEP 4', `Batch anchoring ${batchSize} hashes...`);

    const items = [];
    for (let i = 0; i < batchSize; i++) {
      const data = new TextEncoder().encode(`batch-item-${i}-${Date.now()}`);
      const ref = await cellStore.put(`objects/create/job/batch-${i}`, data);
      const raw = await storage.read(`objects/create/job/batch-${i}`);
      items.push({
        stateHash: sha256(raw!),
        metadata: { typeHint: 'job', tags: [`batch-${i}`] },
      });
    }

    const proofs = await adapter.batchAnchor(items);
    log('BATCH RESULT', `${proofs.length} proofs created`);

    for (const proof of proofs) {
      printProof(proof);
    }

    // Verify each proof
    log('STEP 5', 'Verifying batch proofs...');
    for (const proof of proofs) {
      const result = await adapter.verify(proof);
      log('Verify', `${proof.stateHash.slice(0, 16)}... → valid=${result.valid}`);
    }

  } else if (useScheduler) {
    // ── Scheduler mode ──
    log('STEP 4', 'Running AnchorScheduler (single cycle)...');

    const scheduler = new AnchorScheduler(adapter, storage);

    // Enqueue a few hashes
    scheduler.enqueueWithPath('objects/create/job/demo-1', stateHash);

    const extra1 = sha256(new TextEncoder().encode('extra-state-1'));
    const extra2 = sha256(new TextEncoder().encode('extra-state-2'));
    scheduler.enqueue(extra1);
    scheduler.enqueue(extra2);

    // Trigger immediate anchor
    await scheduler.anchor();

    const state = await scheduler.getState();
    log('Scheduler state', state);

    // Check stored proofs
    const proofKeys = await storage.list('proofs/');
    log('Stored proofs', `${proofKeys.length} proof files`);
    for (const k of proofKeys) {
      const raw = await storage.read('proofs/' + k);
      if (raw) {
        const proof = JSON.parse(new TextDecoder().decode(raw));
        printProof(proof);
      }
    }

  } else {
    // ── Single anchor mode ──
    log('STEP 4', `Anchoring state hash: ${stateHash.slice(0, 32)}...`);

    const proof = await adapter.anchor(stateHash, {
      typeHint: 'job',
      tags: ['demo', 'kitchen-tap'],
    });

    printProof(proof);

    // 5. Verify
    log('STEP 5', 'Verifying proof...');
    const result = await adapter.verify(proof);
    log('Verify result', result);

    // 6. Check getLatestAnchor
    const latest = await adapter.getLatestAnchor(stateHash);
    log('STEP 6', latest ? `getLatestAnchor → txid=${latest.txid}` : 'No anchor found');
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('  Done!');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
}

function printProof(proof: AnchorProof) {
  log('AnchorProof', {
    stateHash: proof.stateHash.slice(0, 32) + '...',
    txid: proof.txid,
    vout: proof.vout,
    blockHeight: proof.blockHeight,
    timestamp: new Date(proof.timestamp).toISOString(),
    bcaAddress: proof.bcaAddress ?? '(none)',
    interval: proof.interval,
    merkleProof: proof.merkleProof ? `${proof.merkleProof.slice(0, 40)}...` : '(none)',
  });
}

// ── CellToken Mode ──────────────────────────────────────────────────

// Protocol derivation params for CellToken keys — must be consistent between lock and unlock.
const CELLTOKEN_PROTOCOL: [number, string] = [2, 'semantos celltoken'];
const CELLTOKEN_COUNTERPARTY = 'self';

async function runCellTokenMode(
  rawCell: Uint8Array,
  cellRef: { key: string; version: number; contentHash: string; cellHash: string },
  stateHash: string,
  baseUrl: string,
  doTransition: boolean,
) {
  const { PublicKey, Hash, Signature, TransactionSignature, Transaction } = await import('@bsv/sdk');

  const walletConfig = {
    baseUrl,
    timeout: 120_000,
    originator: 'semantos-celltoken-demo',
    origin: 'http://localhost',
  };
  const wallet = new WalletClient(walletConfig);

  // The keyID ties the derived key to this specific CellToken's semantic path.
  const keyID = cellRef.key;

  // 1. Get a PROTOCOL-DERIVED public key for the PushDrop lock.
  //    NOT the identity key — we need a derived key so we can later call
  //    createSignature() with matching params to produce the unlocking sig.
  //    (See SDK PushDrop.lock() / PushDrop.unlock() for the canonical pattern.)
  log('TOKEN STEP 1', 'Getting protocol-derived key for CellToken...');
  const pubKeyHex = await wallet.getPublicKey({
    protocolID: CELLTOKEN_PROTOCOL,
    keyID,
    counterparty: CELLTOKEN_COUNTERPARTY,
  });
  const ownerPubKey = PublicKey.fromString(pubKeyHex);
  log('Owner key', `${pubKeyHex.slice(0, 20)}... (derived: protocol=${CELLTOKEN_PROTOCOL[1]}, keyID=${keyID})`);

  // 2. Build the BRC-48 PushDrop locking script
  log('TOKEN STEP 2', 'Building BRC-48 PushDrop locking script...');

  const contentHash = hexToBytes(cellRef.contentHash);
  const lockingScript = CellToken.createOutputScript(
    rawCell,
    cellRef.key,  // semantic path: "objects/create/job/demo-1"
    contentHash,
    ownerPubKey,
  );

  // Serialize locking script to hex for createAction
  const scriptHex = lockingScript.toHex();

  // Parse the cell header to show what's going on-chain
  const header = deserializeCellHeader(rawCell);
  const linearityLabel = header.linearity === Linearity.LINEAR ? 'LINEAR (must spend exactly once)'
    : header.linearity === Linearity.AFFINE ? 'AFFINE (spend or discard)'
    : 'RELEVANT (always valid)';

  log('Cell on-chain', {
    semanticPath: cellRef.key,
    linearity: linearityLabel,
    version: header.version,
    cellCount: header.cellCount,
    totalSize: header.totalSize,
    scriptSize: `${scriptHex.length / 2} bytes`,
  });

  // 3. Create the CellToken via wallet's createAction
  log('TOKEN STEP 3', 'Creating CellToken via createAction — approve in wallet...');

  const result = await wallet.createAction({
    description: 'Semantos CellToken',
    labels: ['semantos-celltoken', 'linear-object'],
    outputs: [{
      lockingScript: scriptHex,
      satoshis: 1,
      outputDescription: `CellToken: ${cellRef.key}`,
      basket: 'semantos-celltokens',
      tags: ['celltoken', 'linear', cellRef.key],
    }],
  });

  log('TOKEN CREATED ✓', {
    txid: result.txid,
    type: 'BRC-48 PushDrop CellToken',
    owner: pubKeyHex.slice(0, 20) + '...',
    semanticPath: cellRef.key,
    linearity: linearityLabel,
    spendable: true,
    note: 'This is a LIVE LINEAR OBJECT on BSV mainnet. It must be spent to transition state.',
  });

  log('WhatsOnChain', `https://whatsonchain.com/tx/${result.txid}`);

  if (doTransition) {
    // ── State transition: v1 → v2 ──
    console.log('\n  ── State Transition: v1 → v2 ──\n');

    // 4a. Get BEEF for the v1 tx
    //
    // The BRC-100 createAction response includes `tx` (AtomicBEEF / BRC-95)
    // which is the SPV-ready envelope. We need it to:
    //   (a) internalizeAction so the wallet tracks the CellToken UTXO
    //   (b) pass as inputBEEF when spending the UTXO in the transition
    //
    // Primary: use result.tx (BEEF from wallet response)
    // Fallback: fetch raw tx from WoC and construct BEEF (should not be needed)

    log('TRANSITION 1', 'Getting BEEF for v1 CellToken...');
    log('V1 response keys', Object.keys(result));

    // The wallet returns BEEF in the `tx` field (AtomicBEEF / BRC-95).
    // CRITICAL: keep it as number[] — the wallet expects number[] or Uint8Array,
    // NOT a hex string. The error "ReaderUint8Array.makeReader: bin must be
    // Uint8Array or number[]" means we must pass the raw array through JSON.
    let beef: number[] | string | undefined;

    if (result.tx) {
      if (Array.isArray(result.tx)) {
        beef = result.tx;  // Keep as number[] — pass straight through
        log('BEEF', `From wallet response (tx field): ${result.tx.length} bytes (number[])`);
      } else if (typeof result.tx === 'string') {
        beef = result.tx;  // Hex string — some wallets may return this
        log('BEEF', `From wallet response (tx field): ${result.tx.length / 2} bytes (hex)`);
      }
    }

    if (!beef) {
      log('BEEF ERROR', 'Wallet returned no tx field — cannot proceed with state transition.');
      log('V1 UTXO', `${result.txid} — on-chain but no BEEF to reference it.`);
      return;
    }

    // NOTE: internalizeAction is NOT needed for self-created txs.
    // The wallet already knows about them (status: "sending").
    // It only applies to txs received from external parties.

    // 4b. Build v2 cell with updated state
    log('TRANSITION 2', 'Building v2 cell (status: open → in_progress)...');

    const v2Storage = new MemoryAdapter();
    const v2CellStore = new CellStore(v2Storage);

    const v2Data = new TextEncoder().encode(JSON.stringify({
      type: 'job',
      title: 'Fix leaking tap in kitchen',
      status: 'in_progress',
      assignee: 'Dave the Plumber',
      updated: new Date().toISOString(),
      created: new Date(Date.now() - 60_000).toISOString(),
      location: { suburb: 'Paddington', state: 'QLD' },
    }));

    const v2Ref = await v2CellStore.put('objects/create/job/demo-1', v2Data, {
      linearity: 1, // LINEAR
    });

    const v2RawCell = await v2Storage.read('objects/create/job/demo-1');
    if (!v2RawCell) throw new Error('Failed to read v2 cell');

    // CellStore packs version=1 by default. For a valid state transition,
    // v2 must have a strictly higher version than v1 (monotonicity).
    // In production this would be derived from the UTXO chain depth.
    const v1Header_ = deserializeCellHeader(rawCell);
    const v2Dv = new DataView(v2RawCell.buffer, v2RawCell.byteOffset, v2RawCell.byteLength);
    v2Dv.setUint32(20, v1Header_.version + 1, true);  // offset 20 = version

    const v2ContentHash = hexToBytes(v2Ref.contentHash);
    const v2LockingScript = CellToken.createOutputScript(
      v2RawCell,
      'objects/create/job/demo-1',
      v2ContentHash,
      ownerPubKey,
    );
    const v2ScriptHex = v2LockingScript.toHex();

    const v2Header = deserializeCellHeader(v2RawCell);
    log('V2 cell', {
      version: v2Header.version,
      totalSize: v2Header.totalSize,
      status: 'in_progress',
      scriptSize: `${v2ScriptHex.length / 2} bytes`,
    });

    // 4b′. ── 2PDA VALIDATION GATE ──
    //
    // Before touching the wallet, run the transition through the 2PDA
    // linearity engine. This validates:
    //   - Both cells have valid magic bytes
    //   - Linearity is preserved (v1.linearity === v2.linearity)
    //   - Type-hash continuity (can't morph type during transition)
    //   - Owner-ID continuity
    //   - Version monotonicity (v2.version > v1.version)
    //   - PushDrop script structural validity
    //   - Linearity enforcement rules (LINEAR → no DUP, no DROP)
    //
    // If validation fails, we abort BEFORE the on-chain tx is created.

    log('2PDA GATE', 'Loading CellEngine WASM for transition validation...');

    const { loadCellEngine } = await import('../packages/cell-engine/bindings/bun/loader');
    const cellEngine = await loadCellEngine({ profile: 'full' });

    const validator = new TransitionValidator(cellEngine, { debug: true });

    log('2PDA GATE', 'Validating v1 → v2 transition through linearity engine...');
    const validation = validator.validate({
      v1CellBytes: rawCell,
      v2CellBytes: v2RawCell,
      semanticPath: 'objects/create/job/demo-1',
      v1ContentHash: contentHash,
      v2ContentHash: v2ContentHash,
      ownerPubKey,
    });

    if (!validation.valid) {
      log('2PDA REJECTED ✗', validation.reason!);
      log('ABORT', 'State transition blocked by linearity engine — no on-chain tx created.');
      return;
    }

    log('2PDA APPROVED ✓', {
      linearity: validation.v1Linearity === Linearity.LINEAR ? 'LINEAR' : `type=${validation.v1Linearity}`,
      typeClassification: validation.typeClassification,
      typeHashContinuity: validation.typeHashContinuity,
      scriptOps: validation.opcodeCount,
    });

    // 4c. Find the v1 CellToken UTXO via listOutputs
    log('TRANSITION 3', 'Finding v1 CellToken UTXO in wallet...');

    let v1Outpoint: string | null = null;
    let v1Satoshis: number | undefined;
    let v1LockingScript: string | undefined;

    try {
      const outputs = await wallet.listOutputs('semantos-celltokens', ['celltoken'], 'locking scripts');
      log('Basket outputs', `Found ${outputs.length} CellToken(s) in basket`);

      for (const out of outputs) {
        log('  Output', {
          outpoint: out.outpoint,
          satoshis: out.satoshis,
          spendable: out.spendable,
          hasScript: !!out.lockingScript,
        });
        if (out.outpoint?.includes(result.txid)) {
          v1Outpoint = out.outpoint;
          v1Satoshis = out.satoshis;
          v1LockingScript = out.lockingScript;
        }
      }
    } catch (err: any) {
      log('listOutputs', `(${err.message}) — will construct outpoint from txid`);
    }

    // Fallback: find the CellToken vout by parsing the BEEF and matching our locking script
    if (!v1Outpoint) {
      log('Outpoint', 'Wallet basket empty — scanning BEEF for CellToken output...');

      try {
        const { Transaction } = await import('@bsv/sdk');
        const beefBytes = Array.isArray(beef) ? beef : [...Buffer.from(beef as string, 'hex')];
        const v1Tx = Transaction.fromAtomicBEEF(beefBytes);

        for (let i = 0; i < v1Tx.outputs.length; i++) {
          const out = v1Tx.outputs[i];
          const outScriptHex = out.lockingScript?.toHex();
          if (outScriptHex === scriptHex) {
            v1Outpoint = `${result.txid}.${i}`;
            v1Satoshis = Number(out.satoshis);
            v1LockingScript = outScriptHex;
            log('Outpoint', `Found CellToken at vout ${i}: ${v1Outpoint}`);
            break;
          }
        }

        // If script match failed, try 1-sat heuristic
        if (!v1Outpoint) {
          for (let i = 0; i < v1Tx.outputs.length; i++) {
            if (Number(v1Tx.outputs[i].satoshis) === 1) {
              v1Outpoint = `${result.txid}.${i}`;
              v1Satoshis = 1;
              v1LockingScript = v1Tx.outputs[i].lockingScript?.toHex();
              log('Outpoint', `Found 1-sat output at vout ${i} (heuristic): ${v1Outpoint}`);
              break;
            }
          }
        }
      } catch (err: any) {
        log('Outpoint', `BEEF parse failed: ${err.message}`);
      }

      // Last resort: guess vout 0
      if (!v1Outpoint) {
        v1Outpoint = `${result.txid}.0`;
        v1Satoshis = 1;
        v1LockingScript = scriptHex;
        log('Outpoint', `Fallback to vout 0: ${v1Outpoint} (may be wrong!)`);
      }
    } else {
      log('Outpoint', `Found in basket: ${v1Outpoint}`);
    }

    // 4d. State transition: spend v1, create v2 in one atomic tx
    //
    // The wallet can't auto-sign PushDrop inputs (it only recognizes P2PKH).
    // So createAction returns signableTransaction (deferred signing). We then:
    //   1. Parse the tx from signableTransaction
    //   2. Compute the sighash preimage for our PushDrop input
    //   3. Call createSignature (BRC-100) to sign with the derived key
    //   4. Build the unlocking script (just a DER signature)
    //   5. Call signAction to finalize + broadcast
    //
    // This follows the same pattern as @bsv/sdk's PushDrop.unlock().

    log('TRANSITION 4', 'Creating state transition tx — approve in wallet...');
    log('Input format', 'Array-style + inputBEEF (deferred signing for PushDrop)');

    try {
      const transitionResult = await wallet.createAction({
        description: 'CellToken transition',
        labels: ['semantos-celltoken', 'state-transition'],
        inputBEEF: beef,
        inputs: [{
          outpoint: v1Outpoint,
          inputDescription: 'Spend CellToken v1 (open)',
          unlockingScriptLength: 73,
          sourceSatoshis: v1Satoshis,
          sourceLockingScript: v1LockingScript,
        }],
        outputs: [{
          lockingScript: v2ScriptHex,
          satoshis: 1,
          outputDescription: 'CellToken v2: objects/create/job/demo-1',
          basket: 'semantos-celltokens',
          tags: ['celltoken', 'linear', 'v2', 'objects/create/job/demo-1'],
        }],
      });

      log('createAction response keys', Object.keys(transitionResult));

      // ── Phase 1 complete. Check if wallet signed directly or deferred. ──

      if (transitionResult.txid && !transitionResult.signableTransaction) {
        // Wallet signed and broadcast directly — unlikely for PushDrop but handle it
        log('STATE TRANSITION COMPLETE ✓ (direct sign)', {
          v1Txid: result.txid.slice(0, 24) + '...',
          v2Txid: transitionResult.txid,
          transition: 'open → in_progress',
        });
        log('WhatsOnChain v2', `https://whatsonchain.com/tx/${transitionResult.txid}`);

      } else if (transitionResult.signableTransaction) {
        // ── Deferred signing flow: wallet can't auto-sign PushDrop ──
        log('TRANSITION 5', 'Wallet returned signableTransaction — signing PushDrop input...');

        const signable = transitionResult.signableTransaction;
        const reference = typeof signable === 'string' ? signable : (signable as any).reference;
        const signableTxBeef = typeof signable === 'string' ? undefined : (signable as any).tx;

        log('Signable ref', typeof reference === 'string' ? reference.slice(0, 40) + '...' : typeof reference);

        // Parse the transaction from the signableTransaction BEEF
        // so we can compute the sighash for our input.
        let txToSign: InstanceType<typeof Transaction> | undefined;

        if (signableTxBeef) {
          const beefBytes = Array.isArray(signableTxBeef) ? signableTxBeef : [...Buffer.from(signableTxBeef, 'hex')];
          txToSign = Transaction.fromAtomicBEEF(beefBytes);
        } else if (transitionResult.tx) {
          const beefBytes = Array.isArray(transitionResult.tx)
            ? transitionResult.tx
            : [...Buffer.from(transitionResult.tx as string, 'hex')];
          txToSign = Transaction.fromAtomicBEEF(beefBytes);
        }

        if (!txToSign) {
          log('SIGN ERROR', 'No tx data in signableTransaction or response — cannot compute sighash.');
          return;
        }

        // Find which input index is our PushDrop (the one we're signing)
        // It should be the input whose sourceTXID matches our v1 txid.
        let ourInputIndex = -1;
        for (let i = 0; i < txToSign.inputs.length; i++) {
          const inp = txToSign.inputs[i];
          if (inp.sourceTXID === result.txid || inp.sourceTransaction?.id('hex') === result.txid) {
            ourInputIndex = i;
            break;
          }
        }
        if (ourInputIndex === -1) {
          // Default: assume it's the last foreign input (index 0 if only one)
          ourInputIndex = 0;
          log('Input index', `Could not match by txid, defaulting to ${ourInputIndex}`);
        } else {
          log('Input index', `Found PushDrop input at index ${ourInputIndex}`);
        }

        // Compute sighash preimage (SIGHASH_ALL | SIGHASH_FORKID = 0x41)
        const signatureScope = TransactionSignature.SIGHASH_FORKID | TransactionSignature.SIGHASH_ALL;

        // Ensure the input has sourceTransaction linked (AtomicBEEF should do this,
        // but if not, manually link the v1 tx from our BEEF).
        const inp = txToSign.inputs[ourInputIndex];
        if (!inp.sourceTransaction) {
          log('Linking', 'Manually linking v1 source transaction to input...');
          const beefBytes = Array.isArray(beef) ? beef : [...Buffer.from(beef as string, 'hex')];
          inp.sourceTransaction = Transaction.fromAtomicBEEF(beefBytes);
          const [, voutStr] = v1Outpoint.split('.');
          inp.sourceOutputIndex = parseInt(voutStr, 10);
        }

        const preimage = txToSign.preimage(ourInputIndex, signatureScope);
        const preimageHash = Hash.sha256(preimage);

        log('Sighash', `preimage=${preimage.length} bytes, hash=${Buffer.from(preimageHash).toString('hex').slice(0, 32)}...`);

        // Ask the wallet to sign using the same derived key params
        // (matching the getPublicKey call used to create the PushDrop lock)
        log('TRANSITION 6', 'Calling createSignature for PushDrop unlock...');

        const { signature: bareSignature } = await wallet.createSignature({
          protocolID: CELLTOKEN_PROTOCOL,
          keyID,
          counterparty: CELLTOKEN_COUNTERPARTY,
          data: [...preimageHash],
        });

        log('Signature', `${bareSignature.length} bytes (DER)`);

        // Build the unlocking script: DER signature + sighash flag
        const sig = Signature.fromDER(bareSignature);
        const txSig = new TransactionSignature(sig.r, sig.s, signatureScope);
        const sigForScript = txSig.toChecksigFormat();
        const unlockingScriptHex = Buffer.from(new Uint8Array([sigForScript.length, ...sigForScript])).toString('hex');

        log('Unlocking script', `${unlockingScriptHex.length / 2} bytes`);

        // ── Phase 2: signAction to finalize and broadcast ──
        log('TRANSITION 7', 'Calling signAction to finalize + broadcast...');

        const finalResult = await wallet.signAction({
          reference,
          spends: {
            [ourInputIndex]: {
              unlockingScript: unlockingScriptHex,
            },
          },
        });

        let v2Txid = finalResult.txid;
        if (!v2Txid && finalResult.tx) {
          const beefBytes = Array.isArray(finalResult.tx)
            ? finalResult.tx
            : [...Buffer.from(finalResult.tx as string, 'hex')];
          const v2Tx = Transaction.fromAtomicBEEF(beefBytes);
          v2Txid = v2Tx.id('hex');
        }

        log('STATE TRANSITION COMPLETE ✓', {
          v1Txid: result.txid.slice(0, 24) + '...',
          v2Txid: v2Txid ?? '(broadcast pending)',
          transition: 'open → in_progress',
          atomic: 'v1 consumed + v2 created in same tx',
          linearityEnforced: 'v1 UTXO can never be spent again',
        });

        if (v2Txid) {
          log('WhatsOnChain v2', `https://whatsonchain.com/tx/${v2Txid}`);
        }

      } else {
        log('UNEXPECTED', 'Wallet returned neither txid nor signableTransaction');
        log('Response', transitionResult);
      }

    } catch (err: any) {
      log('TRANSITION ERROR', err.message);
      if (err.code) log('Error code', err.code);
      log('V1 UTXO', v1Outpoint);
      log('HINT', 'Check wallet logs for details.');
    }
  }
}

// ── Hex helpers ──

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

// ── Entry ──

main().catch(err => {
  console.error('\x1b[31mFatal:\x1b[0m', err.message);
  process.exit(1);
});

```
