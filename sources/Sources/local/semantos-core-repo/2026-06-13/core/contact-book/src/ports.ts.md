---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/contact-book/src/ports.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.945772+00:00
---

# core/contact-book/src/ports.ts

```ts
/**
 * ContactBook port singleton.
 *
 * Follows the same pattern as identity-ports/src/ports.ts:
 *   - `contactBookPort` is a package-scoped singleton
 *   - Call `.bind(impl)` once at boot
 *   - Call `.get()` everywhere else
 *   - Call `.unbind()` between test cases
 *
 * The `contactBookPort` depends on `identityPort` being bound (from
 * `@semantos/identity-ports`) for DAG discovery and edge establishment.
 * Apps should bind `identityPort` before calling any discovery or
 * edge-establishment methods on the contact book.
 *
 * Usage:
 *
 *   import { contactBookPort } from '@semantos/contact-book';
 *   import { makeContactStore } from '@semantos/contact-book';
 *   import { MemoryAdapter } from '@semantos/protocol-types';
 *
 *   contactBookPort.bind(makeContactStore({ storage: new MemoryAdapter() }));
 *
 *   // Then in app code:
 *   const book = contactBookPort.get();
 *   await book.addContact(certId, 'Alice');
 */

import { port, type Port } from '@semantos/state';
import type { ContactBook } from './types.js';

export const contactBookPort: Port<ContactBook> = port<ContactBook>('ContactBookPort');

```
