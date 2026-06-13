---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/piggybank/provision-dryrun.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.385424+00:00
---

# scripts/piggybank/provision-dryrun.ts

```ts
#!/usr/bin/env bun
/**
 * Milestone 1: provisioning dry-run.
 *
 * Spawns a mock ESP32 (TCP server) and runs the parent-side provisioner
 * against it end-to-end. Proves:
 *
 *   1. Plexus identity tree for a kid + device cert is well-formed.
 *   2. BRC-42 child key derivation on both sides produces identical
 *      public keys.
 *   3. ECDH + AES-256-GCM over the provisioning channel round-trip the
 *      device cert + privkey safely.
 *   4. The DeviceProfile that lands in "NVS" is shaped exactly as the
 *      TypeScript types require.
 *
 * Usage:
 *   bun run scripts/piggybank/provision-dryrun.ts [--kid <name>] [--email <addr>]
 *
 * No hardware, no WiFi, no BSV. Exits 0 on success, prints the provisioned
 * profile, and asserts a second unwrap-with-PIN round-trip.
 */

import { connect } from 'node:net';
import { VendorSDK } from '@plexus/vendor-sdk';
import { FAMILY_SYNC } from '@semantos/piggybank';
import { runProvisioner } from './provision-parent.js';
import { startMockDevice } from './mock-device.js';
import { unwrapPrivateKeyWithPin } from './pin-wrap.js';

// ── CLI ──

function arg(name: string, fallback: string): string {
  const i = process.argv.indexOf(name);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const kidName = arg('--kid', 'Mia');
const kidEmail = arg('--email', `${kidName.toLowerCase()}@family.local`);
const parentEmail = arg('--parent-email', 'parent@family.local');
const testPin = arg('--pin', '1234');
const salt = 'plexus-local-v1';
const pbkdf2Iterations = 1_000; // low for dry-run speed

// ── Run ──

async function main() {
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('  BitPiggy Provisioning Dry-Run (Milestone 1)');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`  Kid:    ${kidName} <${kidEmail}>`);
  console.log(`  Parent: <${parentEmail}>`);
  console.log('');

  // ── Identity setup (what the iPad/PWA would do on first run) ──
  const sdk = new VendorSDK({ dbPath: ':memory:', salt, pbkdf2Iterations });
  const parent = sdk.registerIdentity(parentEmail);
  const kid = sdk.registerIdentity(kidEmail);
  // Parent derives a FAMILY_SYNC child they'll use to sign outbound sync
  // payloads. Not used in this milestone but exercised so we know the
  // flag plumbing works.
  const parentFamilySync = sdk.deriveChild(parent.certId, 'family', FAMILY_SYNC);

  console.log('Identity tree:');
  console.log(`  parent root              → ${parent.certId.slice(0, 16)}…`);
  console.log(`  parent/family/FAMILY_SYNC → ${parentFamilySync.certId.slice(0, 16)}…`);
  console.log(`  kid root                 → ${kid.certId.slice(0, 16)}…`);
  console.log('');

  // ── Spin up mock device ──
  const device = await startMockDevice({ testPin });
  console.log(`Mock device listening on 127.0.0.1:${device.port}`);

  // ── Parent opens a "serial" socket to the device ──
  const socket = connect({ host: '127.0.0.1', port: device.port });
  await new Promise<void>((res, rej) => {
    socket.once('connect', () => res());
    socket.once('error', rej);
  });
  console.log('Parent connected to mock device\n');

  const [parentResult, deviceStored] = await Promise.all([
    runProvisioner({
      socket,
      sdk,
      kidEmail,
      kidCertId: kid.certId,
      parentCertId: parent.certId,
      kidName,
      salt,
      pbkdf2Iterations,
      firmwareVersionExpected: '0.1.0-dryrun',
    }),
    device.onProvisioned,
  ]);

  await device.close();

  // ── Cross-check both sides agreed on the device cert ──
  if (parentResult.deviceCertId !== deviceStored.deviceCertId) {
    throw new Error(
      `certId mismatch: parent=${parentResult.deviceCertId} ` +
        `vs device=${deviceStored.deviceCertId}`,
    );
  }
  if (parentResult.devicePublicKey !== deviceStored.publicKey) {
    throw new Error(
      `pubkey mismatch: parent=${parentResult.devicePublicKey} ` +
        `vs device=${deviceStored.publicKey}`,
    );
  }

  // ── Unwrap the device-side PIN-encrypted privkey and compare to what
  //    the parent derived. This is the single most important invariant:
  //    the private key the firmware will use must equal the key the
  //    parent derived from email + salt + invoice number.
  const unwrapped = unwrapPrivateKeyWithPin(deviceStored, testPin);
  if (unwrapped !== parentResult.devicePrivateKeyHex) {
    throw new Error('PIN-unwrapped device privkey does NOT match parent derivation');
  }

  // ── Report ──
  console.log('✓ Provisioning succeeded\n');
  console.log('DeviceProfile on device (as would be written to NVS):');
  console.log(`  deviceCertId         ${deviceStored.deviceCertId}`);
  console.log(`  publicKey            ${deviceStored.publicKey}`);
  console.log(`  kidName              ${deviceStored.kidName}`);
  console.log(`  parentCertId         ${deviceStored.parentCertId}`);
  console.log(`  chipId               ${deviceStored.chipId}`);
  console.log(`  firmwareVersion      ${deviceStored.firmwareVersion}`);
  console.log(`  encryptedPrivateKey  ${deviceStored.encryptedPrivateKey.slice(0, 24)}…`);
  console.log(`  pinSalt              ${deviceStored.pinSalt}`);
  console.log(`  pinNonce             ${deviceStored.pinNonce}`);
  console.log(`  pinAuthTag           ${deviceStored.pinAuthTag}`);
  console.log('');
  console.log(`Unwrapped privkey (PIN=${testPin}) matches parent-derived key ✓`);
  console.log('');
  console.log('Next step: milestone 2 — flash one XIAO-C6 with firmware that');
  console.log('reproduces the mock device half of this handshake over USB CDC.');

  sdk.close();
  process.exit(0);
}

main().catch(err => {
  console.error('\n✗ Dry-run failed:', err instanceof Error ? err.message : err);
  if (err instanceof Error && err.stack) console.error(err.stack);
  process.exit(1);
});

```
