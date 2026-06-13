---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/piggybank/mock-device.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.385168+00:00
---

# scripts/piggybank/mock-device.ts

```ts
/**
 * Mock ESP32 device for the provisioning dry-run.
 *
 * Behaviour is intentionally the minimum needed to pass the
 * device-side half of the HELLO → CHALLENGE → RESPONSE → PROVISION →
 * ACK handshake defined in `apps/piggybank/src/device.ts`. It exercises
 * real secp256k1 ECDH and AES-256-GCM so the wire output is
 * byte-compatible with what the C firmware will produce.
 *
 * After a successful provision it writes the resulting DeviceProfile
 * (with PIN-wrapped private key, using a hard-coded test PIN "1234") to
 * a JSON file so downstream tests can inspect it.
 */

import { createServer, type Server, type Socket } from 'node:net';
import { randomBytes } from 'node:crypto';
import PrivateKey from '@bsv/sdk/primitives/PrivateKey';
import PublicKey from '@bsv/sdk/primitives/PublicKey';
import { SHA256 } from '@bsv/sdk/primitives/Hash';
import { computeSharedSecret, compressedPubKeyHex } from '@plexus/vendor-sdk';
import {
  ProvisioningStep,
  type ProvisioningAck,
  type ProvisioningChallenge,
  type ProvisioningHello,
  type ProvisioningMessage,
  type ProvisioningPayload,
  type ProvisioningResponse,
} from '../../apps/piggybank/src/device.js';
import { open } from './aesgcm.js';
import { wrapPrivateKeyWithPin, type PinWrap } from './pin-wrap.js';
import { onFramedMessage, sendFramed } from './wire.js';

/** What the device writes into its fake NVS after a successful provision. */
export interface MockStoredProfile extends PinWrap {
  deviceCertId: string;
  publicKey: string;
  kidName: string;
  parentCertId: string;
  provisionedAt: number;
  chipId: string;
  firmwareVersion: string;
}

export interface MockDeviceOptions {
  /** Firmware version string sent in HELLO. Defaults to "0.1.0-dryrun". */
  firmwareVersion?: string;
  /** PIN used to wrap the private key post-provision. Defaults to "1234". */
  testPin?: string;
  /** Port to listen on. 0 picks a free port (default). */
  port?: number;
}

export interface MockDeviceHandle {
  port: number;
  close: () => Promise<void>;
  /** Resolves after the ACK is sent. Rejects on NACK / socket error. */
  onProvisioned: Promise<MockStoredProfile>;
}

export function startMockDevice(
  options: MockDeviceOptions = {},
): Promise<MockDeviceHandle> {
  const firmwareVersion = options.firmwareVersion ?? '0.1.0-dryrun';
  const testPin = options.testPin ?? '1234';
  const port = options.port ?? 0;

  const chipId = randomBytes(8).toString('hex');

  // Ephemeral provisioning key — fresh per connection.
  const deviceEphemeralPriv = PrivateKey.fromRandom();
  const deviceEphemeralPub = deviceEphemeralPriv.toPublicKey();

  return new Promise((resolve, reject) => {
    let server: Server;
    let resolveProvisioned!: (value: MockStoredProfile) => void;
    let rejectProvisioned!: (err: Error) => void;
    const onProvisioned = new Promise<MockStoredProfile>((res, rej) => {
      resolveProvisioned = res;
      rejectProvisioned = rej;
    });

    const onConnection = (socket: Socket) => {
      let sharedSecret: string | null = null;

      // Device starts by saying HELLO.
      const hello: ProvisioningHello = {
        step: ProvisioningStep.HELLO,
        chipId,
        firmwareVersion,
        hasExistingIdentity: false,
      };
      sendFramed(socket, hello);

      onFramedMessage(
        socket,
        msg => {
          try {
            switch (msg.step) {
              case ProvisioningStep.CHALLENGE: {
                const challenge = msg as ProvisioningChallenge;
                const hostPub = PublicKey.fromString(challenge.hostEphemeralPubKey);
                sharedSecret = computeSharedSecret(deviceEphemeralPriv, hostPub);

                // Sign the nonce hash with the device's ephemeral privkey.
                const nonceHashBytes = new SHA256()
                  .update(challenge.nonce, 'hex')
                  .digest();
                const sig = deviceEphemeralPriv.sign(nonceHashBytes);

                const resp: ProvisioningResponse = {
                  step: ProvisioningStep.RESPONSE,
                  deviceEphemeralPubKey: compressedPubKeyHex(deviceEphemeralPub),
                  signedNonce: sig.toDER('hex') as string,
                };
                sendFramed(socket, resp);
                return;
              }

              case ProvisioningStep.PROVISION: {
                if (!sharedSecret) {
                  throw new Error('PROVISION received before CHALLENGE');
                }
                const payload = msg as ProvisioningPayload;
                const json = open(sharedSecret, {
                  ciphertext: payload.encryptedPayload,
                  nonce: payload.nonce,
                  authTag: payload.authTag,
                });
                const inner = JSON.parse(json) as {
                  certId: string;
                  publicKey: string;
                  privateKeyHex: string;
                  kidName: string;
                  parentCertId: string;
                };

                // Wrap the long-lived privkey with the test PIN, exactly as
                // the firmware will on first boot.
                const wrap = wrapPrivateKeyWithPin(inner.privateKeyHex, testPin);

                const stored: MockStoredProfile = {
                  ...wrap,
                  deviceCertId: inner.certId,
                  publicKey: inner.publicKey,
                  kidName: inner.kidName,
                  parentCertId: inner.parentCertId,
                  provisionedAt: Date.now(),
                  chipId,
                  firmwareVersion,
                };

                const ack: ProvisioningAck = {
                  step: ProvisioningStep.ACK,
                  deviceCertId: inner.certId,
                  publicKey: inner.publicKey,
                };
                sendFramed(socket, ack);
                socket.end();
                resolveProvisioned(stored);
                return;
              }

              case ProvisioningStep.NACK: {
                rejectProvisioned(
                  new Error(`Host NACK: ${(msg as { reason: string }).reason}`),
                );
                return;
              }

              default:
                throw new Error(`Mock device got unexpected step: ${msg.step}`);
            }
          } catch (err) {
            const reason = err instanceof Error ? err.message : String(err);
            sendFramed(socket, { step: ProvisioningStep.NACK, reason });
            socket.end();
            rejectProvisioned(new Error(reason));
          }
        },
        err => rejectProvisioned(new Error(`Mock socket error: ${err.message}`)),
      );
    };

    server = createServer(onConnection);
    server.on('error', err => reject(err));
    server.listen(port, '127.0.0.1', () => {
      const addr = server.address();
      if (!addr || typeof addr === 'string') {
        reject(new Error('Could not resolve mock device port'));
        return;
      }
      resolve({
        port: addr.port,
        close: () =>
          new Promise<void>(res => {
            server.close(() => res());
          }),
        onProvisioned,
      });
    });
  });
}

```
