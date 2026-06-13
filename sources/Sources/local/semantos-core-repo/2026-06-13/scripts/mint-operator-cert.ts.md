---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/mint-operator-cert.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.324729+00:00
---

# scripts/mint-operator-cert.ts

```ts
#!/usr/bin/env bun
/**
 * mint-operator-cert.ts — MVP stopgap operator-cert generator.
 *
 * ⚠️  STOPGAP. Not the final identity primitive. This exists so that:
 *
 *   1. The VPS bootstrap flow (docs/prds/apps/VPS-BOOTSTRAP.md §7.4) has a
 *      concrete `/etc/semantos/admin.cert` to write and reference.
 *   2. Both OJT and BRAP identity adapters, running in `local` or `stub` mode,
 *      can read the file and derive the SAME `certId` — satisfying the
 *      "both bots compute the same certId" acceptance criterion.
 *
 * Replace with real phone-based cert issuance when that PRD lands. Until then,
 * this self-attests a secp256k1 keypair to an owner phone number and writes a
 * readable JSON envelope. CertId convention mirrors `license.ts`:
 *   certId = "sha256:" + sha256(canonicalCborBytes).hex()
 *
 * Usage:
 *   bun run scripts/mint-operator-cert.ts \
 *     --out /etc/semantos/admin.cert \
 *     --owner-phone '+61400000000'
 *
 * Optional flags:
 *   --force          overwrite an existing file at --out
 *   --stdout         print the JSON envelope to stdout instead of writing
 *   --label <text>   human-readable label baked into the cert meta
 */

import { PrivateKey, Hash } from '@bsv/sdk';
import { Encoder } from 'cbor-x';
import { writeFileSync, existsSync, chmodSync } from 'node:fs';

// ── Arg parsing ────────────────────────────────────────────────────────────

interface Args {
  out: string;
  ownerPhone: string;
  label: string;
  force: boolean;
  stdout: boolean;
}

function parseArgs(argv: string[]): Args {
  const args: Partial<Args> = {
    out: '/etc/semantos/admin.cert',
    label: 'operator',
    force: false,
    stdout: false,
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case '--out': args.out = argv[++i]; break;
      case '--owner-phone': args.ownerPhone = argv[++i]; break;
      case '--label': args.label = argv[++i]; break;
      case '--force': args.force = true; break;
      case '--stdout': args.stdout = true; break;
      case '-h':
      case '--help':
        printUsageAndExit(0);
        break;
      default:
        console.error(`Unknown flag: ${a}`);
        printUsageAndExit(1);
    }
  }
  if (!args.ownerPhone) {
    console.error('--owner-phone is required (e.g. "+61400000000")');
    printUsageAndExit(1);
  }
  return args as Args;
}

function printUsageAndExit(code: number): never {
  console.error([
    'mint-operator-cert — MVP stopgap operator-cert generator',
    '',
    'Usage: bun run scripts/mint-operator-cert.ts --owner-phone <E.164> [options]',
    '',
    '  --out <path>        Output path (default: /etc/semantos/admin.cert)',
    '  --owner-phone <p>   E.164 phone number, required (e.g. "+61400000000")',
    '  --label <text>      Human-readable label (default: "operator")',
    '  --force             Overwrite an existing file at --out',
    '  --stdout            Print envelope to stdout instead of writing',
  ].join('\n'));
  process.exit(code);
}

// ── Cert construction ──────────────────────────────────────────────────────

const encoder = new Encoder({ useRecords: false });

interface OperatorCertEnvelope {
  $stopgap: string;
  version: 1;
  certId: string;          // "sha256:..." hex
  label: string;
  ownerPhone: string;      // E.164
  pubkey: string;          // 33-byte compressed secp256k1, hex
  privkey: string;         // 32-byte hex — present because this is a stopgap
                           // self-attested cert. Remove once we have a real
                           // issuance flow and keep privkey out of the cert.
  createdAt: number;       // unix seconds
  selfSig: string;         // DER-encoded ECDSA signature, hex
}

function mint(args: Args): OperatorCertEnvelope {
  const priv = PrivateKey.fromRandom();
  const pub = priv.toPublicKey();
  const pubHex = pub.toString();             // compressed, 66 chars
  const privHex = priv.toString();           // 64-char hex wallet key
  const createdAt = Math.floor(Date.now() / 1000);

  // Canonical CBOR body for signing/hashing: fixed-order tuple.
  const body = [pubHex, args.ownerPhone, createdAt, args.label];
  const bodyBytes = encoder.encode(body);

  // Self-sign the body. BSV SDK returns a Signature object; DER-encode it.
  const sigObj = priv.sign(Array.from(bodyBytes));
  const selfSigHex = Buffer.from(sigObj.toDER()).toString('hex');

  // certId = sha256 over (body || selfSig) — full envelope hash.
  const fullTuple = [...body, selfSigHex];
  const fullBytes = encoder.encode(fullTuple);
  const digestBytes = Hash.sha256(Array.from(fullBytes));
  const certId = 'sha256:' + Buffer.from(digestBytes).toString('hex');

  return {
    $stopgap: 'MVP operator cert — replace with real phone-based issuance when that PRD lands.',
    version: 1,
    certId,
    label: args.label,
    ownerPhone: args.ownerPhone,
    pubkey: pubHex,
    privkey: privHex,
    createdAt,
    selfSig: selfSigHex,
  };
}

// ── Main ───────────────────────────────────────────────────────────────────

const args = parseArgs(process.argv);
const envelope = mint(args);
const serialized = JSON.stringify(envelope, null, 2) + '\n';

if (args.stdout) {
  process.stdout.write(serialized);
} else {
  if (existsSync(args.out) && !args.force) {
    console.error(`Refusing to overwrite existing file: ${args.out}`);
    console.error('Pass --force to overwrite, or pick a different --out path.');
    process.exit(2);
  }
  writeFileSync(args.out, serialized, { mode: 0o600 });
  chmodSync(args.out, 0o600);
  console.error(`Wrote operator cert to ${args.out} (mode 0600)`);
}

console.error(`certId: ${envelope.certId}`);
console.error(`pubkey: ${envelope.pubkey}`);
console.error(`owner:  ${envelope.ownerPhone}`);

```
