---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/contact-book/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.944627+00:00
---

# core/contact-book/src/index.ts

```ts
/**
 * @semantos/contact-book
 *
 * Contacts book for Semantos — maps human-readable identities (name/email)
 * to BRC-52 cert IDs. Backed by StorageAdapter for persistence, with
 * DAG discovery via identityPort and ECDH edge establishment.
 *
 * Quick start (production):
 *
 *   import { contactBookPort, makeContactStore } from '@semantos/contact-book';
 *   import { MemoryAdapter } from '@semantos/protocol-types';
 *
 *   // 1. Bind at boot
 *   contactBookPort.bind(makeContactStore({ storage: new MemoryAdapter() }));
 *
 *   // 2. Use anywhere
 *   const book = contactBookPort.get();
 *   await book.addContact(aliceCertId, 'Alice', { publicKey: alicePubKey });
 *   await book.connectTo(myCertId, aliceCertId);
 *
 * Quick start (tests/demos):
 *
 *   import { makeStubContactBook } from '@semantos/contact-book/stub';
 *
 *   const { book } = makeStubContactBook({ identityStub: myStub });
 *
 * See docs/prd/PHASE-38-CONTACTS-PKI.md for the full design.
 */

// ── Types ────────────────────────────────────────────────────────────────────
export type {
  Contact,
  ContactPatch,
  EdgeRecord,
  ContactDiscoveryResult,
  AddContactOptions,
  ContactBook,
  ContactBookErrorCode,
} from './types.js';
export { ContactBookError } from './types.js';

// ── Port singleton ───────────────────────────────────────────────────────────
export { contactBookPort } from './ports.js';

// ── Production implementation ─────────────────────────────────────────────────
export { makeContactStore } from './contact-store.js';
export type { ContactStoreOptions } from './contact-store.js';

// ── Stub (also exported from /stub subpath in package.json) ──────────────────
export { makeStubContactBook, seedStubContact, seedStubEdge } from './stub-binding.js';
export type {
  StubContactBookOptions,
  StubContactStore,
  StubIdentitySurface,
} from './stub-binding.js';

```
