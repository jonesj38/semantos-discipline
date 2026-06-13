---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-vendor-sdk/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.018187+00:00
---

# core/plexus-vendor-sdk/src/index.ts

```ts
/**
 * @plexus/vendor-sdk — client-side DAG management with real BRC-42 crypto.
 *
 * Local stand-in package until Dusk Inc ships the real @plexus/vendor-sdk.
 */

export { VendorSDK, type VendorSDKConfig } from './VendorSDK';
export { PlexusStore } from './store';
export {
  deriveRootKey,
  deriveChildKey,
  deriveSegment,
  deriveScalar,
  deriveSegmentPub,
  deriveScalarPub,
  deriveDomainSegment,
  deriveDomainSegmentPub,
  KDF_VERSION_DOMAIN,
  deriveNodeKey,
  DEFAULT_KDF_VERSION,
  type KdfVersion,
  computeCertId,
  computeSharedSecret,
  compressedPubKeyHex,
  sha256hex,
  buildRootPreimage,
  buildChildPreimage,
} from './crypto';

```
