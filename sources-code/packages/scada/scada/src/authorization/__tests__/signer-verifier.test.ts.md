---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/__tests__/signer-verifier.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.476478+00:00
---

# packages/scada/scada/src/authorization/__tests__/signer-verifier.test.ts

```ts
/**
 * Unit tests — signer-verifier.
 */

import { afterEach, describe, expect, test } from 'bun:test';

import { signerPort, type Signer } from '@semantos/protocol-types/ports';

import type { SCADACapabilityToken } from '../../types';
import { verifyCapabilitySignature } from '../signer-verifier';

function token(): SCADACapabilityToken {
  return {
    tokenId: 'tkn-1',
    operatorId: 'op-1',
    role: 'senior-operator',
    capabilities: [1, 2, 3, 4],
    shiftStart: '2030-01-01T00:00:00.000Z',
    shiftEnd: '2030-12-31T23:59:59.000Z',
    grantedBy: 'plant-manager-1',
    consumed: false,
    cellBytes: new Uint8Array(32),
  };
}

afterEach(() => {
  signerPort.unbind();
});

describe('verifyCapabilitySignature', () => {
  test('permit-default when no signer bound and not strict', async () => {
    const result = await verifyCapabilitySignature(token());
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.via).toBe('permit-default');
  });

  test('rejects when strict + no signer', async () => {
    const result = await verifyCapabilitySignature(token(), { strict: true });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe('NO_SIGNER_BOUND');
  });

  test('passes via signer-port when signer derives a key', async () => {
    const signer: Signer = {
      sign: async () => ({ hex: 'aa' }),
      derivePublicKey: async () => '02'.padEnd(66, '0'),
    };
    signerPort.bind(signer);
    const result = await verifyCapabilitySignature(token());
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.via).toBe('signer-port');
  });

  test('rejects on signer error', async () => {
    const signer: Signer = {
      sign: async () => ({ hex: 'aa' }),
      derivePublicKey: async () => {
        throw new Error('no key for granter');
      },
    };
    const result = await verifyCapabilitySignature(token(), { signer });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe('INVALID_SIGNATURE');
      expect(result.detail).toContain('no key for granter');
    }
  });
});

```
