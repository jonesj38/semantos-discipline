---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/fsm/__tests__/fixtures.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.798084+00:00
---

# archive/apps-poker-agent/src/payment-channel/fsm/__tests__/fixtures.ts

```ts
/**
 * Test fixtures for the payment-channel FSM.
 */

import type {
  ChannelArtifacts,
  ChannelStateValue,
  RoleScopedKeyId,
  SpvProof,
} from '../types';
import { initialChannelState } from '../types';

export const validArtifacts: ChannelArtifacts = {
  envelopeHex: 'deadbeef'.repeat(8),
  simpleRawTx: 'cafebabe'.repeat(8),
  envelopeHash: 'aa'.repeat(32),
  simpleHash: 'bb'.repeat(32),
  txid: 'cc'.repeat(32),
  lockingScriptHex: '5221' + '02' + 'ab'.repeat(32) + '21' + '02' + 'cd'.repeat(32) + '52ae',
  vout: 0,
};

export const validSpv: SpvProof = {
  bumpHash: '11'.repeat(32),
  blockHash: '22'.repeat(32),
  confirmations: 6,
};

export const consumerKeyIds: RoleScopedKeyId[] = [
  { role: 'consumer', keyId: 'consumer-root:org-1:1700000000:abc123' },
  { role: 'consumer', keyId: 'consumer-channel:org-1:1700000001:def456' },
];

export function freshState(role: 'consumer' | 'provider' = 'consumer'): ChannelStateValue {
  return initialChannelState('chan-1', role);
}

/** Drive the channel through fund + SPV + flow-ready in one helper. */
export function fundedAndReady(): ChannelStateValue {
  return {
    ...freshState(),
    state: 'FLOW_READY',
    artifacts: validArtifacts,
    spvProof: validSpv,
    keyIds: consumerKeyIds,
    isNativeMultisig: true,
  };
}

```
