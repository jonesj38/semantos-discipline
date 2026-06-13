---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.473649+00:00
---

# cartridges/oddjobz/brain/src/index.ts

```ts
/**
 * @semantos/oddjobz — trades/services vertical extension.
 *
 * Phase O2 deliverable: the eight canonical cell types
 * (`oddjobz.{job,quote,visit,invoice,customer,site,estimate,message}.v1`)
 * with stable type-hashes, deterministic packing, and conformance
 * vectors. Consumers: D-O3 (cap mints), D-O4 (state machines), D-O5p
 * (helm + pairing), D-O5m (mobile shell).
 *
 * Phase O3 deliverable: the six canonical oddjobz capabilities
 * (`cap.oddjobz.{write_customer,quote,dispatch,invoice,close,
 * public_chat_serve}`) with stable domain flags and the on-chain
 * cell-mint shape — see `./capabilities.ts`. The extension manifest
 * the Semantos Brain first-boot hook reads lives at `./manifest.ts`.
 *
 * Phase O1 deliverable: the canonical `TradesLexicon` re-export at
 * `./lexicon.ts` — sourced from `@semantos/semantos-sir` (Lean spec at
 * `proofs/lean/Semantos/Lexicons/Trades.lean`).
 */

export * from './cell-types/index.js';
export { TradesLexicon, type TradesCategory } from './lexicon.js';
export {
  ODDJOBZ_CAPABILITIES,
  ODDJOBZ_CAP_NAMES,
  ODDJOBZ_CAP_TYPE_HASH,
  ODDJOBZ_CAP_TYPE_HASH_HEX,
  OPERATOR_ROOT_CAPS,
  NODE_SERVICE_CAPS,
  capabilityByName,
  capabilityByDomainFlag,
  capWriteCustomer,
  capQuote,
  capDispatch,
  capInvoice,
  capClose,
  capPublicChatServe,
  mintCapabilityCell,
  decodeCapabilityCell,
  readDomainFlag,
  readContextTag,
  opCheckDomainFlag,
  encodeRecoveryPayload,
  decodeRecoveryPayload,
  bytesToHex,
  hexToBytes,
  CELL_SIZE as CAP_CELL_SIZE,
  HEADER_SIZE as CAP_HEADER_SIZE,
  PAYLOAD_SIZE as CAP_PAYLOAD_SIZE,
  type OddjobzCapability,
  type OddjobzCapName,
  type CapHolder,
  type DecodedCapabilityCell,
  type RecoveredCapSet,
} from './capabilities.js';
export {
  oddjobzManifest,
  manifestToWire,
  type ExtensionManifest,
} from './manifest.js';

/* D-O4 — state machines (Job/Quote/Visit/Invoice FSMs + kernel-gate stub). */
export * from './state-machines/index.js';

/* D-O6b — public chat v1.0: persistence, lead extraction, ratification queue. */
export {
  buildVisitorMessageCell,
  buildAiMessageCell,
  type ChatPersistenceInput,
  type ChatPersistedTurn,
} from './chat-persistence.js';
export {
  extractLead,
  buildLeadExtractionPrompt,
  type LeadExtractInput,
  type LeadExtractResult,
  type LlmCompleteFn,
} from './lead-extract.js';
export {
  RatificationQueue,
  type QueueEntry,
  type RatifyInput,
  type RatifyResult,
} from './ratification-queue.js';

/* D-O7 — OJT salvage: prompts (system/extraction/pdf) + conversation
 * (state-manager, hat-scoping, accumulated state, analyzer, bridge). */
export * from './prompts/index.js';
export * from './conversation/index.js';

```
