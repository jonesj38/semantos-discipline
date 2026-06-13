---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/contact-book/src/contact-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.945206+00:00
---

# core/contact-book/src/contact-store.ts

```ts
/**
 * ContactStore — StorageAdapter-backed implementation of ContactBook.
 *
 * Storage layout under `prefix` (default `'contacts/'`):
 *
 *   {prefix}records/{certId}                     — JSON Contact
 *   {prefix}index/email/{email}                  — plain-text certId
 *   {prefix}index/edges/{certId}:{edgeType}      — JSON EdgeRecord
 *
 * Edge key format encodes edgeType so a single contact can hold multiple
 * typed edges (MESSAGING, DATA_ACCESS, etc.) per Plexus §1.1.7 uniqueness.
 *
 * Per §2.5.5: EdgeRecord stores signingKeyIndex only — never sharedSecret.
 * Per §1.1.8: edges are soft-deleted (revokedAt), never hard-deleted.
 *
 * Spec: docs/prd/PHASE-38-CONTACTS-PKI.md, Plexus Client Requirements v2.1
 */

import type { StorageAdapter } from '@semantos/protocol-types';
import { identityPort } from '@semantos/identity-ports';

import type {
  AddContactOptions,
  ConnectOptions,
  Contact,
  ContactBook,
  ContactPatch,
  EdgeRecord,
  EdgeType,
} from './types.js';
import { ContactBookError } from './types.js';

// ── Storage keys ──────────────────────────────────────────────────────────────

function recordKey(prefix: string, certId: string): string {
  return `${prefix}records/${certId}`;
}

function emailIndexKey(prefix: string, email: string): string {
  return `${prefix}index/email/${email.toLowerCase()}`;
}

function edgeStorageKey(prefix: string, theirCertId: string, edgeType: EdgeType): string {
  return `${prefix}index/edges/${theirCertId}:${edgeType}`;
}

function edgeCacheKey(theirCertId: string, edgeType: EdgeType): string {
  return `${theirCertId}:${edgeType}`;
}

// ── Serialisation helpers ─────────────────────────────────────────────────────

const enc = new TextEncoder();
const dec = new TextDecoder();

function toBytes(obj: unknown): Uint8Array {
  return enc.encode(JSON.stringify(obj));
}

function fromBytes<T>(data: Uint8Array): T {
  return JSON.parse(dec.decode(data)) as T;
}

// ── ContactStore options ──────────────────────────────────────────────────────

export interface ContactStoreOptions {
  storage: StorageAdapter;
  prefix?: string;
  now?: () => number;
}

// ── Implementation ────────────────────────────────────────────────────────────

export function makeContactStore(opts: ContactStoreOptions): ContactBook {
  const { storage, now = Date.now } = opts;
  const prefix = opts.prefix ?? 'contacts/';

  let cache: Map<string, Contact> | null = null;
  /** Keyed by `${theirCertId}:${edgeType}` */
  let cacheEdges: Map<string, EdgeRecord> | null = null;

  // ── Cache management ────────────────────────────────────────────────────

  async function ensureLoaded(): Promise<void> {
    if (cache !== null) return;
    cache = new Map();
    cacheEdges = new Map();

    const recordKeys = await storage.list(`${prefix}records/`);
    for (const rel of recordKeys) {
      const data = await storage.read(`${prefix}records/${rel}`);
      if (data) {
        const contact = fromBytes<Contact>(data);
        cache.set(contact.certId, contact);
      }
    }

    const edgeKeys = await storage.list(`${prefix}index/edges/`);
    for (const rel of edgeKeys) {
      const data = await storage.read(`${prefix}index/edges/${rel}`);
      if (data) {
        const edge = fromBytes<EdgeRecord>(data);
        cacheEdges.set(edgeCacheKey(edge.responderCertId, edge.edgeType), edge);
      }
    }
  }

  async function persistContact(contact: Contact): Promise<void> {
    await storage.write(recordKey(prefix, contact.certId), toBytes(contact));
    if (contact.email) {
      await storage.write(emailIndexKey(prefix, contact.email), enc.encode(contact.certId));
    }
    if (cache === null) cache = new Map();
    cache.set(contact.certId, contact);
  }

  async function persistEdge(edge: EdgeRecord): Promise<void> {
    await storage.write(
      edgeStorageKey(prefix, edge.responderCertId, edge.edgeType),
      toBytes(edge),
    );
    if (cacheEdges === null) cacheEdges = new Map();
    cacheEdges.set(edgeCacheKey(edge.responderCertId, edge.edgeType), edge);
  }

  // ── ContactBook implementation ──────────────────────────────────────────

  return {
    async addContact(
      certId: string,
      displayName: string,
      addOpts: AddContactOptions = {},
    ): Promise<Contact> {
      await ensureLoaded();

      let publicKey: string;
      let email: string | undefined = addOpts.email;

      if (addOpts.resolveFromDag) {
        const ip = identityPort.get();
        const resolution = ip.resolveIdentity(certId);
        publicKey = resolution.publicKey;
        if (!email && resolution.email) email = resolution.email;
        const existing = cache!.get(certId);
        if (existing) {
          const updated: Contact = {
            ...existing,
            displayName,
            email: email ?? existing.email,
            publicKey: resolution.publicKey,
            children: resolution.children,
            updatedAt: now(),
          };
          await persistContact(updated);
          return updated;
        }
      } else {
        if (!addOpts.publicKey) {
          throw new ContactBookError(
            'MISSING_PUBLIC_KEY',
            `addContact: publicKey is required when resolveFromDag is false.`,
          );
        }
        publicKey = addOpts.publicKey;
        const existing = cache!.get(certId);
        if (existing) {
          const updated: Contact = {
            ...existing,
            displayName,
            email: email ?? existing.email,
            updatedAt: now(),
          };
          await persistContact(updated);
          return updated;
        }
      }

      const contact: Contact = {
        certId,
        publicKey,
        displayName,
        email,
        nodeType: addOpts.nodeType,
        source: addOpts.source ?? 'manual',
        addedAt: now(),
        updatedAt: now(),
      };
      await persistContact(contact);
      return contact;
    },

    getContact(certId: string): Contact | null {
      return cache?.get(certId) ?? null;
    },

    listContacts(): Contact[] {
      if (!cache) return [];
      return [...cache.values()].sort((a, b) =>
        a.displayName.localeCompare(b.displayName, undefined, { sensitivity: 'base' }),
      );
    },

    updateContact(certId: string, patch: ContactPatch): Contact {
      if (!cache) throw new ContactBookError('CONTACT_NOT_FOUND', `updateContact: cache not loaded`);
      const existing = cache.get(certId);
      if (!existing) {
        throw new ContactBookError('CONTACT_NOT_FOUND', `No contact with certId ${certId}`);
      }
      const updated: Contact = { ...existing, ...patch, updatedAt: now() };
      persistContact(updated).catch(() => {});
      cache.set(certId, updated);
      return updated;
    },

    removeContact(certId: string): boolean {
      if (!cache) return false;
      const existing = cache.get(certId);
      if (!existing) return false;
      cache.delete(certId);
      storage.delete(recordKey(prefix, certId)).catch(() => {});
      if (existing.email) {
        storage.delete(emailIndexKey(prefix, existing.email)).catch(() => {});
      }
      return true;
    },

    search(query: string): Contact[] {
      if (!cache) return [];
      const q = query.toLowerCase();
      return [...cache.values()].filter(
        (c) =>
          c.displayName.toLowerCase().includes(q) ||
          (c.email?.toLowerCase().includes(q) ?? false),
      );
    },

    async resolveContact(certId: string): Promise<Contact> {
      let ip;
      try {
        ip = identityPort.get();
      } catch {
        throw new ContactBookError(
          'PORT_NOT_BOUND',
          'resolveContact requires identityPort to be bound.',
        );
      }

      let resolution;
      try {
        resolution = ip.resolveIdentity(certId);
      } catch (e: unknown) {
        const err = e as { code?: string; message?: string };
        if (err.code === 'CERT_NOT_FOUND') {
          throw new ContactBookError('CERT_NOT_FOUND', `Cert ${certId} not found in the DAG`);
        }
        throw e;
      }

      await ensureLoaded();
      const existing = cache!.get(certId);
      const displayName = existing?.displayName ?? resolution.email ?? certId.slice(0, 12);

      const contact: Contact = {
        certId,
        publicKey: resolution.publicKey,
        displayName,
        email: resolution.email,
        children: resolution.children,
        edgeId: existing?.edgeId,
        source: 'discovered',
        addedAt: existing?.addedAt ?? now(),
        updatedAt: now(),
      };
      await persistContact(contact);
      return contact;
    },

    async discoverByEmail(email: string): Promise<Contact | null> {
      await ensureLoaded();

      const idxData = await storage.read(emailIndexKey(prefix, email));
      if (idxData) {
        const certId = dec.decode(idxData);
        const local = cache!.get(certId);
        if (local) return local;
        return this.resolveContact(certId);
      }

      if (cache) {
        for (const c of cache.values()) {
          if (c.email?.toLowerCase() === email.toLowerCase()) return c;
        }
      }

      let ip;
      try {
        ip = identityPort.get();
      } catch {
        return null;
      }

      try {
        const reg = ip.registerIdentity(email);
        return this.resolveContact(reg.certId);
      } catch {
        return null;
      }
    },

    async connectTo(
      myCertId: string,
      theirCertId: string,
      opts: ConnectOptions = {},
    ): Promise<EdgeRecord> {
      await ensureLoaded();

      const resolvedEdgeType = opts.edgeType ?? 'MESSAGING';
      const resolvedPolicy = opts.recoveryPolicy ?? 'NONE';
      const cacheKey = edgeCacheKey(theirCertId, resolvedEdgeType);

      const contact = cache!.get(theirCertId);
      if (!contact) {
        throw new ContactBookError(
          'CONTACT_NOT_FOUND',
          `connectTo: ${theirCertId} is not in the local contact book.`,
        );
      }

      // Idempotent: return existing active edge of the same type
      const existingEdge = cacheEdges?.get(cacheKey);
      if (existingEdge && !existingEdge.revokedAt) return existingEdge;

      let ip;
      try {
        ip = identityPort.get();
      } catch {
        throw new ContactBookError('PORT_NOT_BOUND', 'connectTo requires identityPort to be bound.');
      }

      const { edgeId, signingKeyIndex } = ip.createEdge(myCertId, theirCertId);

      const edge: EdgeRecord = {
        edgeId,
        initiatorCertId: myCertId,
        responderCertId: theirCertId,
        edgeType: resolvedEdgeType,
        signingKeyIndex,
        recoveryPolicy: resolvedPolicy,
        backupRecipe: opts.backupRecipe,
        appId: opts.appId,
        createdAt: now(),
      };
      await persistEdge(edge);

      // Update primary edge reference on contact for MESSAGING edges
      if (resolvedEdgeType === 'MESSAGING') {
        const updatedContact: Contact = { ...contact, edgeId, updatedAt: now() };
        await persistContact(updatedContact);
      }

      return edge;
    },

    async revokeEdge(
      _myCertId: string,
      theirCertId: string,
      edgeType: EdgeType = 'MESSAGING',
    ): Promise<void> {
      await ensureLoaded();

      const contact = cache!.get(theirCertId);
      if (!contact) {
        throw new ContactBookError('CONTACT_NOT_FOUND', `No contact with certId ${theirCertId}`);
      }

      const cacheKey = edgeCacheKey(theirCertId, edgeType);
      const edge = cacheEdges?.get(cacheKey);
      if (!edge) {
        throw new ContactBookError('EDGE_NOT_FOUND', `No ${edgeType} edge to ${theirCertId}`);
      }
      if (edge.revokedAt) {
        throw new ContactBookError(
          'EDGE_ALREADY_REVOKED',
          `${edgeType} edge to ${theirCertId} was already revoked at ${edge.revokedAt}`,
        );
      }

      // Soft delete — retain record for cryptographic audit trail (§1.1.8)
      const revoked: EdgeRecord = { ...edge, revokedAt: now() };
      await persistEdge(revoked);

      // Clear primary edge reference from contact if this was the MESSAGING edge
      if (edgeType === 'MESSAGING' && contact.edgeId === edge.edgeId) {
        await persistContact({ ...contact, edgeId: undefined, updatedAt: now() });
      }
    },

    isConnected(theirCertId: string, edgeType: EdgeType = 'MESSAGING'): boolean {
      const edge = cacheEdges?.get(edgeCacheKey(theirCertId, edgeType));
      return edge !== undefined && !edge.revokedAt;
    },

    getEdge(theirCertId: string, edgeType: EdgeType = 'MESSAGING'): EdgeRecord | null {
      return cacheEdges?.get(edgeCacheKey(theirCertId, edgeType)) ?? null;
    },

    listEdgesTo(theirCertId: string): EdgeRecord[] {
      if (!cacheEdges) return [];
      const results: EdgeRecord[] = [];
      for (const [key, edge] of cacheEdges) {
        if (key.startsWith(`${theirCertId}:`)) results.push(edge);
      }
      return results;
    },
  };
}

```
