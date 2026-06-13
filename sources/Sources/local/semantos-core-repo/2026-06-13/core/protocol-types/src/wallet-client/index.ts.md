---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.871613+00:00
---

# core/protocol-types/src/wallet-client/index.ts

```ts
/**
 * Wallet-client barrel — re-exports the public class plus selected
 * helpers for testing and composition.
 */

export { WalletClient } from './wallet-client-facade';
export { WalletClientError } from './wallet-error';
export {
  httpTransportPort,
  defaultHttpTransport,
  getTransport,
  type HttpTransport,
  type HttpTransportContext,
} from './wallet-http-transport';
export { tryPaths } from './wallet-path-resolver';
export { throwIfError, toWalletClientError } from './wallet-error-handler';
export {
  buildCreateAction,
  buildCreateSignature,
  buildGetHeight,
  buildGetNetwork,
  buildGetPublicKey,
  buildInternalizeAction,
  buildIsAuthenticated,
  buildListOutputs,
  buildSignAction,
} from './wallet-request-builder';
export {
  parseCreateAction,
  parseCreateSignature,
  parseGetHeight,
  parseGetNetwork,
  parseGetPublicKey,
  parseInternalizeAction,
  parseIsAuthenticated,
  parseListOutputs,
  parseSignAction,
} from './wallet-response-parser';
export type {
  CreateActionInput,
  CreateActionRequest,
  CreateActionResult,
  HttpMethod,
  InternalizeActionRequest,
  InternalizeOutput,
  RequestSpec,
  WalletClientConfig,
  WalletError,
  WalletInput,
  WalletOutput,
  WalletOutputEntry,
} from './types';

```
