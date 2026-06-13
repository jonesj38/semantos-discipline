---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/wallet-diag.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.316283+00:00
---

# scripts/wallet-diag.ts

```ts
#!/usr/bin/env bun
/**
 * wallet-diag.ts — Diagnose wallet UTXO availability.
 *
 * Checks why 4.8M sats can't fund a 263-sat transaction.
 *
 * Usage: bun run scripts/wallet-diag.ts [--port 3321]
 */

import { WalletClient } from '../packages/protocol-types/src/wallet-client';

const args = process.argv.slice(2);
const portFlag = args.indexOf('--port');
const port = portFlag !== -1 ? parseInt(args[portFlag + 1], 10) : 3321;
const baseUrl = `http://localhost:${port}`;

function log(label: string, value: unknown) {
  console.log(`\x1b[36m[${label}]\x1b[0m`, typeof value === 'string' ? value : JSON.stringify(value, null, 2));
}

async function main() {
  console.log('\n━━━ Wallet Diagnostic ━━━\n');

  const wallet = new WalletClient({
    baseUrl,
    timeout: 30_000,
    originator: 'semantos-diagnostic',
    origin: 'http://localhost',
  });

  // 1. Basic connectivity
  try {
    const auth = await wallet.isAuthenticated();
    log('Auth', auth);
    const network = await wallet.getNetwork();
    const height = await wallet.getHeight();
    log('Network', `${network}, height ${height}`);
  } catch (err: any) {
    log('ERROR', err.message);
    process.exit(1);
  }

  // 2. Check identity key
  try {
    const idKey = await wallet.getPublicKey({ identityKey: true });
    log('Identity key', idKey);
  } catch (err: any) {
    log('Identity key error', err.message);
  }

  // 3. List outputs from default basket
  for (const basket of ['default', 'semantos-celltokens', 'general']) {
    try {
      const outputs = await wallet.listOutputs(basket, [], 'locking scripts');
      log(`Basket "${basket}"`, `${outputs.length} outputs`);
      let totalSats = 0;
      for (const out of outputs.slice(0, 5)) {
        totalSats += out.satoshis;
        log(`  UTXO`, {
          outpoint: out.outpoint,
          satoshis: out.satoshis,
          spendable: out.spendable,
          scriptLen: out.lockingScript?.length ? out.lockingScript.length / 2 : 0,
          tags: out.tags,
        });
      }
      if (outputs.length > 5) {
        for (const out of outputs.slice(5)) totalSats += out.satoshis;
        log(`  ...`, `${outputs.length - 5} more outputs`);
      }
      log(`  Total`, `${totalSats} sats in ${outputs.length} UTXOs`);
    } catch (err: any) {
      log(`Basket "${basket}" error`, err.message);
    }
  }

  // 4. Try a minimal OP_RETURN tx (cheapest possible)
  log('TEST', 'Attempting minimal OP_RETURN tx (0-sat output)...');
  try {
    const opReturnScript = '006a' + '04' + Buffer.from('test').toString('hex'); // OP_FALSE OP_RETURN "test"
    const result = await wallet.createAction({
      description: 'Wallet diagnostic',
      labels: ['diagnostic'],
      outputs: [{
        lockingScript: opReturnScript,
        satoshis: 0,
        outputDescription: 'Diagnostic OP_RETURN',
      }],
    });
    log('OP_RETURN SUCCESS', { txid: result.txid });
  } catch (err: any) {
    log('OP_RETURN FAILED', err.message);
  }

  // 5. Try a 1-sat P2PKH tx (simplest non-OP_RETURN)
  log('TEST', 'Attempting 1-sat P2PKH tx...');
  try {
    const idKey = await wallet.getPublicKey({ identityKey: true });
    // Build a simple P2PKH script: OP_DUP OP_HASH160 <hash> OP_EQUALVERIFY OP_CHECKSIG
    const { SHA256, RIPEMD160, PublicKey } = await import('@bsv/sdk');
    const pubKey = PublicKey.fromString(idKey);
    const pubKeyBytes = pubKey.encode(true) as number[];
    const sha = new SHA256().update(pubKeyBytes).digest();
    const hash160 = new RIPEMD160().update(sha).digest();
    const hash160Hex = Buffer.from(hash160).toString('hex');
    const p2pkh = `76a914${hash160Hex}88ac`;

    const result = await wallet.createAction({
      description: 'Wallet diag P2PKH',
      labels: ['diagnostic'],
      outputs: [{
        lockingScript: p2pkh,
        satoshis: 1,
        outputDescription: 'Diagnostic P2PKH',
      }],
    });
    log('P2PKH SUCCESS', { txid: result.txid });
  } catch (err: any) {
    log('P2PKH FAILED', err.message);
  }

  // 6. Try different originators
  for (const originator of ['semantos-anchor-demo', 'semantos-celltoken-demo', 'semantos-poker-match']) {
    try {
      const w = new WalletClient({ baseUrl, timeout: 15_000, originator, origin: 'http://localhost' });
      const opReturnScript = '006a' + '04' + Buffer.from('diag').toString('hex');
      const result = await w.createAction({
        description: 'Originator test',
        labels: ['diagnostic'],
        outputs: [{
          lockingScript: opReturnScript,
          satoshis: 0,
          outputDescription: 'Diagnostic OP_RETURN',
        }],
      });
      log(`Originator "${originator}"`, `SUCCESS txid=${result.txid}`);
    } catch (err: any) {
      log(`Originator "${originator}"`, `FAILED: ${err.message.slice(0, 100)}`);
    }
  }

  console.log('\n━━━ Done ━━━\n');
}

main().catch(err => {
  console.error('Fatal:', err.message);
  process.exit(1);
});

```
