---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/handlers/channel-metering/create-payment-channel.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.119345+00:00
---

# runtime/services/src/services/loom/handlers/channel-metering/create-payment-channel.ts

```ts
/**
 * Create a payment-channel object with Plexus-derived channel cert and
 * counterparty edge. Best-effort: falls back to a partially populated
 * payload if Plexus has not been initialized.
 */

import { type Atom } from '@semantos/state';

import { createObject } from '../../../../state/objectFactory';
import type { ObjectTypeDefinition } from '../../../../config/extensionConfig';
import type { ObjectPatch } from '../../../../types/loom';
import { dispatchTo } from '../../loom-atoms';
import type { LoomState } from '../../loom-types';
import type { PlexusPort } from '../../ports';

/** Domain flag used when deriving a channel cert from the active identity. */
const METERING_DOMAIN = 0x0a;

export interface CreatePaymentChannelArgs {
  typeDef: ObjectTypeDefinition;
  counterpartyCertId: string;
  fundingSatoshis: number;
  policyObjectId: string;
  meterUnit: string;
  hatId: string;
  hatCapabilities?: number[];
}

export async function createPaymentChannel(
  stateAtom: Atom<LoomState>,
  ports: { plexus: PlexusPort },
  args: CreatePaymentChannelArgs,
): Promise<string> {
  const obj = createObject(args.typeDef);

  if (args.hatId) {
    const creationPatch: ObjectPatch = {
      id: `patch-${Date.now()}-creation`,
      kind: 'action',
      timestamp: Date.now(),
      delta: {
        action: 'channel_opened',
        typeName: args.typeDef.name,
        counterpartyCertId: args.counterpartyCertId,
      },
      hatId: args.hatId,
      ...(args.hatCapabilities !== undefined ? { hatCapabilities: args.hatCapabilities } : {}),
    };
    obj.patches.push(creationPatch);
  }

  obj.payload.counterpartyCertId = args.counterpartyCertId;
  obj.payload.fundingSatoshis = args.fundingSatoshis;
  obj.payload.fundingDeadline = Date.now() + 86400000;
  obj.payload.policyObjectId = args.policyObjectId;
  obj.payload.meterUnit = args.meterUnit;
  obj.payload.status = 'prefunding';
  obj.payload.balanceTracking = {};
  obj.payload.currentTick = 0;
  obj.payload.cumulativeSatoshis = 0;
  obj.payload.settlementConfirmed = false;

  try {
    const currentIdentity = ports.plexus.getSnapshot().currentIdentity;
    if (currentIdentity?.certId) {
      const channelCert = await ports.plexus.deriveChild(
        currentIdentity.certId,
        'metering.channel',
        METERING_DOMAIN,
      );
      obj.payload.channelCertId = channelCert.certId;
      const edge = await ports.plexus.createEdge(channelCert.certId, args.counterpartyCertId);
      obj.payload.counterpartyEdgeId = edge.edgeId;
      obj.payload.sharedSecret = edge.sharedSecret;
    }
  } catch {
    // PlexusService not initialized — proceed without cert derivation.
  }

  dispatchTo(stateAtom, { type: 'ADD_OBJECT', object: obj, openAsCard: true });
  return obj.id;
}

```
