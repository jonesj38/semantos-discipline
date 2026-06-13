---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/piggybank/provision-parent.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.384398+00:00
---

# scripts/piggybank/provision-parent.ts

```ts
/**
 * Parent-side provisioner.
 *
 * Runs the HELLO → CHALLENGE → RESPONSE → PROVISION → ACK handshake
 * defined in `apps/piggybank/src/device.ts` over a framed TCP socket
 * (standing in for USB CDC serial in the real system).
 *
 * Keys are drawn from the workspace's @plexus/vendor-sdk, so the
 * provisioned DeviceProfile is produced from the same BRC-42 derivation
 * chain the production system will use.
 */

import type { Socket } from 'node:net';
import { randomBytes } from 'node:crypto';
import PrivateKey from '@bsv/sdk/primitives/PrivateKey';
import PublicKey from '@bsv/sdk/primitives/PublicKey';
import Signature from '@bsv/sdk/primitives/Signature';
import BigNumber from '@bsv/sdk/primitives/BigNumber';
import { SHA256 } from '@bsv/sdk/primitives/Hash';
import { VendorSDK } from '@plexus/vendor-sdk';
import {
  deriveRootKey,
  deriveChildKey,
  computeSharedSecret,
  compressedPubKeyHex,
} from '@plexus/vendor-sdk';
import { PIGGYBANK } from '@semantos/piggybank';
import {
  ProvisioningStep,
  type ProvisioningAck,
  type ProvisioningChallenge,
  type ProvisioningHello,
  type ProvisioningMessage,
  type ProvisioningNack,
  type ProvisioningPayload,
  type ProvisioningResponse,
} from '../../apps/piggybank/src/device.js';
import { seal } from './aesgcm.js';
import { onFramedMessage, sendFramed } from './wire.js';

export interface ProvisionerConfig {
  /** Connected TCP socket standing in for USB serial. */
  socket: Socket;
  /** VendorSDK instance owning the parent + kid identities. */
  sdk: VendorSDK;
  /** Kid's email (already registered via sdk.registerIdentity). */
  kidEmail: string;
  /** Kid's Plexus root certId. */
  kidCertId: string;
  /** Parent's certId (certifier on sync messages). */
  parentCertId: string;
  /** Human-readable kid name written into DeviceProfile. */
  kidName: string;
  /** PBKDF2 salt — must match the VendorSDK instance's config. */
  salt: string;
  /** PBKDF2 iterations — must match the VendorSDK instance's config. */
  pbkdf2Iterations: number;
  /** Firmware version announced back to the device in the ACK. */
  firmwareVersionExpected: string;
}

export interface ProvisionResult {
  /** DeviceProfile as it will be stored in ESP32 NVS (without PIN wrap yet). */
  deviceCertId: string;
  devicePublicKey: string;
  devicePrivateKeyHex: string;    // to be PIN-wrapped on device
  kidName: string;
  parentCertId: string;
  provisionedAt: number;
  firmwareVersion: string;
  chipId: string;
}

/** Drive the provisioning handshake from the parent side. Resolves on ACK. */
export async function runProvisioner(cfg: ProvisionerConfig): Promise<ProvisionResult> {
  // 1. Derive the device's long-lived Plexus child key under the kid root.
  const deviceChild = cfg.sdk.deriveChild(cfg.kidCertId, 'device', PIGGYBANK);
  const kidRootKey = deriveRootKey(cfg.kidEmail, cfg.salt, cfg.pbkdf2Iterations);
  const invoiceNumber = `device:${PIGGYBANK}:${deviceChild.childIndex}`;
  const devicePrivKey = deriveChildKey(kidRootKey, invoiceNumber);
  const devicePubKey = devicePrivKey.toPublicKey();
  const devicePubKeyHex = compressedPubKeyHex(devicePubKey);
  if (devicePubKeyHex !== deviceChild.publicKey) {
    throw new Error(
      `Device pubkey mismatch: locally derived ${devicePubKeyHex} ` +
        `vs SDK cert ${deviceChild.publicKey}. Check salt/iterations.`,
    );
  }

  // 2. Freshly generate an ephemeral provisioning key (host side).
  const hostEphemeralPrivKey = PrivateKey.fromRandom();
  const hostEphemeralPubKey = hostEphemeralPrivKey.toPublicKey();
  const nonce = randomBytes(32).toString('hex');

  // 3. Wait for HELLO, then drive the rest of the handshake.
  return new Promise<ProvisionResult>((resolve, reject) => {
    let deviceChipId: string | null = null;
    let deviceEphemeralPubKey: PublicKey | null = null;
    let sharedSecret: string | null = null;

    const fail = (reason: string): void => {
      const nack: ProvisioningNack = { step: ProvisioningStep.NACK, reason };
      try {
        sendFramed(cfg.socket, nack);
      } catch {/* best effort */}
      cfg.socket.end();
      reject(new Error(reason));
    };

    onFramedMessage(
      cfg.socket,
      (msg: ProvisioningMessage) => {
        try {
          switch (msg.step) {
            case ProvisioningStep.HELLO: {
              const hello = msg as ProvisioningHello;
              deviceChipId = hello.chipId;
              const challenge: ProvisioningChallenge = {
                step: ProvisioningStep.CHALLENGE,
                nonce,
                hostEphemeralPubKey: compressedPubKeyHex(hostEphemeralPubKey),
              };
              sendFramed(cfg.socket, challenge);
              return;
            }

            case ProvisioningStep.RESPONSE: {
              const resp = msg as ProvisioningResponse;
              deviceEphemeralPubKey = PublicKey.fromString(resp.deviceEphemeralPubKey);

              // Verify the device's ECDSA signature over the nonce with its
              // ephemeral key. Proves the device controls the ephemeral
              // privkey and prevents MITM.
              const nonceHashBytes = new SHA256().update(nonce, 'hex').digest();
              const sig = Signature.fromDER(resp.signedNonce, 'hex');
              const ok = sig.verify(nonceHashBytes, deviceEphemeralPubKey);
              if (!ok) {
                fail('Device ephemeral signature invalid');
                return;
              }

              sharedSecret = computeSharedSecret(
                hostEphemeralPrivKey,
                deviceEphemeralPubKey,
              );

              // Encrypt the provisioning payload.
              const inner = JSON.stringify({
                certId: deviceChild.certId,
                publicKey: deviceChild.publicKey,
                privateKeyHex: devicePrivKey.toString(),
                kidName: cfg.kidName,
                parentCertId: cfg.parentCertId,
              });
              const sealed = seal(sharedSecret, inner);

              const payload: ProvisioningPayload = {
                step: ProvisioningStep.PROVISION,
                encryptedPayload: sealed.ciphertext,
                nonce: sealed.nonce,
                authTag: sealed.authTag,
              };
              sendFramed(cfg.socket, payload);
              return;
            }

            case ProvisioningStep.ACK: {
              const ack = msg as ProvisioningAck;
              if (ack.deviceCertId !== deviceChild.certId) {
                fail(
                  `Device ACK'd wrong certId: expected ${deviceChild.certId}, ` +
                    `got ${ack.deviceCertId}`,
                );
                return;
              }
              cfg.socket.end();
              resolve({
                deviceCertId: deviceChild.certId,
                devicePublicKey: deviceChild.publicKey,
                devicePrivateKeyHex: devicePrivKey.toString(),
                kidName: cfg.kidName,
                parentCertId: cfg.parentCertId,
                provisionedAt: Date.now(),
                firmwareVersion: cfg.firmwareVersionExpected,
                chipId: deviceChipId ?? '',
              });
              return;
            }

            case ProvisioningStep.NACK: {
              const nack = msg as ProvisioningNack;
              fail(`Device NACK: ${nack.reason}`);
              return;
            }

            default:
              fail(`Unexpected provisioning step: ${msg.step}`);
              return;
          }
        } catch (err) {
          fail(err instanceof Error ? err.message : String(err));
        }
      },
      err => fail(`Socket error: ${err.message}`),
    );
  });
}

```
