---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/types/transfer.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.400308+00:00
---

# src/types/transfer.js

```js
/**
 * Transfer Records: Chain-of-Custody for Identity Objects
 *
 * Transfer records are AFFINE semantic objects that track the movement
 * of identity objects between parents in the identity graph.
 */
import { SemanticType } from './semantic-objects.js';
/**
 * Create a transfer record.
 *
 * @param objectCertId Hex cert ID of object being transferred
 * @param fromParentCertId Hex cert ID of current owner
 * @param toParentCertId Hex cert ID of new owner
 * @param transferTxId Hex transaction ID
 * @param inputOutpoint Outpoint of previous owner (txid.vout)
 * @param outputOutpoint Outpoint of new owner (txid.vout)
 * @param metadata Optional transfer metadata
 * @returns A new TransferRecord
 */
export function createTransferRecord(objectCertId, fromParentCertId, toParentCertId, transferTxId, inputOutpoint, outputOutpoint, metadata = {}) {
    return {
        semanticType: SemanticType.AFFINE,
        resourceId: generateResourceId(),
        createdAt: Date.now(),
        schemaVersion: 1,
        objectCertId,
        fromParentCertId,
        toParentCertId,
        transferTxId,
        inputOutpoint,
        outputOutpoint,
        transferredAt: Date.now(),
        acknowledged: false,
        discarded: false,
        metadata: {
            capTransferOutpoint: metadata.capTransferOutpoint ?? null,
            edgeVerified: metadata.edgeVerified ?? false,
            previousChildIndex: metadata.previousChildIndex ?? 0,
            newChildIndex: metadata.newChildIndex ?? 0,
        },
    };
}
/**
 * Generate a unique resource ID (hex string).
 * @internal
 */
function generateResourceId() {
    // In production, use a proper UUID or crypto random
    return Math.random().toString(16).slice(2) + Date.now().toString(16);
}
//# sourceMappingURL=transfer.js.map
```
