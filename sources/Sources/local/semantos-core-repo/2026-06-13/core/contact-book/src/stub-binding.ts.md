---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/contact-book/src/stub-binding.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.945497+00:00
---

# core/contact-book/src/stub-binding.ts

```ts
/**
 * In-memory stub implementation of ContactBook.
 *
 * Used by:
 *   - Test cases that need a deterministic ContactBook without StorageAdapter I/O
 *   - Demos that need a populated contacts surface without real identity infra
 *
 * Determinism contract:
 *   - All in-memory; no I/O
 *   - Clock is injectable so tests can pin timestamps
 *   - `identityPort` is NOT required — discovery and edge methods use an
 *     injectable `identityStub` or fall back to simple lookups in the local store
 *
 * Note on sharedSecret: per Plexus §2.5.5, the actual ECDH shared secret is
 * never stored. The stub's createEdge returns only edgeId + signingKeyIndex.
 * Callers that need the secret for messaging must re-derive it locally.
 */

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

// ── Stub identity surface ─────────────────────────────────────────────────────

/**
 * Minimal identity surface the stub needs for discovery + edges.
 * By default, discovery always fails gracefully (returns null).
 * Inject a real or fake implementation to test those paths.
 */
export interface StubIdentitySurface {
  /** Resolve a certId → {publicKey, email?, children?}. Throws on miss. */
  resolveIdentity(certId: string): {
    certId: string;
    publicKey: string;
    email?: string;
    children?: Array<{ certId: string; childIndex: number; resourceId: string }>;
    created: number;
    updated: number;
  };
  /**
   * Create an ECDH edge between two cert IDs.
   * Returns edgeId and signingKeyIndex only — per §2.5.5 the shared secret
   * is computed locally by the client and never surfaced to the contact-book layer.
   */
  createEdge(initiatorCertId: string, responderCertId: string): {
    edgeId: string;
    signingKeyIndex: number;
  };
  /** Register or resolve identity by email (used by discoverByEmail). */
  registerIdentity(email: string): { certId: string; publicKey: string };
}

// ── Stub options ──────────────────────────────────────────────────────────────

export interface StubContactBookOptions {
  /** Clock override; defaults to Date.now. */
  now?: () => number;
  /**
   * Optional identity surface for discovery / edge methods. If omitted,
   * `resolveContact()`, `discoverByEmail()`, and `connectTo()` throw `PORT_NOT_BOUND`.
   */
  identityStub?: StubIdentitySurface;
  /**
   * Pre-seed contacts. Each entry is added to the in-memory store at
   * construction time without I/O.
   */
  seed?: Array<Pick<Contact, 'certId' | 'publicKey' | 'displayName' | 'email' | 'source'>>;
}

// ── Store shape ───────────────────────────────────────────────────────────────

export interface StubContactStore {
  contacts: Map<string, Contact>;
  /** Keyed by `${responderCertId}:${edgeType}` to support multiple edge types. */
  edges: Map<string, EdgeRecord>;
  emailIndex: Map<string, string>; // email → certId
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function edgeKey(theirCertId: string, edgeType: EdgeType): string {
  return `${theirCertId}:${edgeType}`;
}

// ── Factory ───────────────────────────────────────────────────────────────────

/**
 * Create a fresh in-memory stub ContactBook. Each call returns a new isolated
 * instance — tests should create one per `describe` block.
 */
export function makeStubContactBook(opts: StubContactBookOptions = {}): {
  book: ContactBook;
  store: StubContactStore;
} {
  const now = opts.now ?? Date.now;
  const identity = opts.identityStub ?? null;

  const store: StubContactStore = {
    contacts: new Map(),
    edges: new Map(),
    emailIndex: new Map(),
  };

  // Pre-seed
  const ts = now();
  for (const seed of opts.seed ?? []) {
    const contact: Contact = {
      ...seed,
      source: seed.source ?? 'manual',
      addedAt: ts,
      updatedAt: ts,
    };
    store.contacts.set(seed.certId, contact);
    if (seed.email) store.emailIndex.set(seed.email.toLowerCase(), seed.certId);
  }

  // ── helpers ────────────────────────────────────────────────────────────

  function requireIdentity(): StubIdentitySurface {
    if (!identity) {
      throw new ContactBookError(
        'PORT_NOT_BOUND',
        'This stub was created without an identityStub. ' +
          'Pass opts.identityStub to enable discovery and edge methods.',
      );
    }
    return identity;
  }

  function putContact(contact: Contact): void {
    store.contacts.set(contact.certId, contact);
    if (contact.email) store.emailIndex.set(contact.email.toLowerCase(), contact.certId);
  }

  // ── ContactBook implementation ─────────────────────────────────────────

  const book: ContactBook = {
    async addContact(
      certId: string,
      displayName: string,
      addOpts: AddContactOptions = {},
    ): Promise<Contact> {
      let publicKey: string;
      let email: string | undefined = addOpts.email;

      if (addOpts.resolveFromDag) {
        const ip = requireIdentity();
        const r = ip.resolveIdentity(certId);
        publicKey = r.publicKey;
        email = email ?? r.email;
        const existing = store.contacts.get(certId);
        if (existing) {
          const updated: Contact = { ...existing, displayName, email, updatedAt: now() };
          putContact(updated);
          return updated;
        }
      } else {
        if (!addOpts.publicKey) {
          throw new ContactBookError(
            'MISSING_PUBLIC_KEY',
            `addContact: opts.publicKey is required when resolveFromDag is false.`,
          );
        }
        publicKey = addOpts.publicKey;
        const existing = store.contacts.get(certId);
        if (existing) {
          const updated: Contact = {
            ...existing,
            displayName,
            email: email ?? existing.email,
            updatedAt: now(),
          };
          putContact(updated);
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
      putContact(contact);
      return contact;
    },

    getContact(certId: string): Contact | null {
      return store.contacts.get(certId) ?? null;
    },

    listContacts(): Contact[] {
      return [...store.contacts.values()].sort((a, b) =>
        a.displayName.localeCompare(b.displayName, undefined, { sensitivity: 'base' }),
      );
    },

    updateContact(certId: string, patch: ContactPatch): Contact {
      const existing = store.contacts.get(certId);
      if (!existing) {
        throw new ContactBookError('CONTACT_NOT_FOUND', `No contact with certId ${certId}`);
      }
      const updated: Contact = { ...existing, ...patch, updatedAt: now() };
      putContact(updated);
      return updated;
    },

    removeContact(certId: string): boolean {
      const existing = store.contacts.get(certId);
      if (!existing) return false;
      store.contacts.delete(certId);
      if (existing.email) store.emailIndex.delete(existing.email.toLowerCase());
      return true;
    },

    search(query: string): Contact[] {
      const q = query.toLowerCase();
      return [...store.contacts.values()].filter(
        (c) =>
          c.displayName.toLowerCase().includes(q) ||
          (c.email?.toLowerCase().includes(q) ?? false),
      );
    },

    async resolveContact(certId: string): Promise<Contact> {
      const ip = requireIdentity();
      let resolution;
      try {
        resolution = ip.resolveIdentity(certId);
      } catch (e: unknown) {
        const err = e as { code?: string };
        if (err.code === 'CERT_NOT_FOUND') {
          throw new ContactBookError('CERT_NOT_FOUND', `Cert ${certId} not found`);
        }
        throw e;
      }

      const existing = store.contacts.get(certId);
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
      putContact(contact);
      return contact;
    },

    async discoverByEmail(email: string): Promise<Contact | null> {
      // 1. Local index
      const certId = store.emailIndex.get(email.toLowerCase());
      if (certId) return store.contacts.get(certId) ?? null;

      // 2. Local contact scan
      for (const c of store.contacts.values()) {
        if (c.email?.toLowerCase() === email.toLowerCase()) return c;
      }

      // 3. Identity stub fallback
      if (!identity) return null;
      try {
        const reg = identity.registerIdentity(email);
        return book.resolveContact(reg.certId);
      } catch {
        return null;
      }
    },

    async connectTo(
      myCertId: string,
      theirCertId: string,
      opts: ConnectOptions = {},
    ): Promise<EdgeRecord> {
      const resolvedEdgeType = opts.edgeType ?? 'MESSAGING';
      const resolvedPolicy = opts.recoveryPolicy ?? 'NONE';
      const key = edgeKey(theirCertId, resolvedEdgeType);

      const contact = store.contacts.get(theirCertId);
      if (!contact) {
        throw new ContactBookError(
          'CONTACT_NOT_FOUND',
          `connectTo: ${theirCertId} is not in the local contact book.`,
        );
      }

      // Idempotent: return existing active edge of same type
      const existing = store.edges.get(key);
      if (existing && !existing.revokedAt) return existing;

      const ip = requireIdentity();
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
      store.edges.set(key, edge);

      // Update contact with primary (MESSAGING) edge reference
      if (resolvedEdgeType === 'MESSAGING') {
        putContact({ ...contact, edgeId, updatedAt: now() });
      }
      return edge;
    },

    async revokeEdge(
      _myCertId: string,
      theirCertId: string,
      edgeType: EdgeType = 'MESSAGING',
    ): Promise<void> {
      const contact = store.contacts.get(theirCertId);
      if (!contact) {
        throw new ContactBookError('CONTACT_NOT_FOUND', `No contact with certId ${theirCertId}`);
      }

      const key = edgeKey(theirCertId, edgeType);
      const edge = store.edges.get(key);
      if (!edge) {
        throw new ContactBookError(
          'EDGE_NOT_FOUND',
          `No ${edgeType} edge to ${theirCertId}`,
        );
      }
      if (edge.revokedAt) {
        throw new ContactBookError(
          'EDGE_ALREADY_REVOKED',
          `${edgeType} edge to ${theirCertId} was already revoked at ${edge.revokedAt}`,
        );
      }

      // Soft delete — retain record for cryptographic audit trail (§1.1.8)
      store.edges.set(key, { ...edge, revokedAt: now() });

      // Clear primary edge reference from contact if this was MESSAGING
      if (edgeType === 'MESSAGING' && contact.edgeId === edge.edgeId) {
        putContact({ ...contact, edgeId: undefined, updatedAt: now() });
      }
    },

    isConnected(theirCertId: string, edgeType: EdgeType = 'MESSAGING'): boolean {
      const edge = store.edges.get(edgeKey(theirCertId, edgeType));
      return edge !== undefined && !edge.revokedAt;
    },

    getEdge(theirCertId: string, edgeType: EdgeType = 'MESSAGING'): EdgeRecord | null {
      return store.edges.get(edgeKey(theirCertId, edgeType)) ?? null;
    },

    listEdgesTo(theirCertId: string): EdgeRecord[] {
      const results: EdgeRecord[] = [];
      for (const [key, edge] of store.edges) {
        if (key.startsWith(`${theirCertId}:`)) results.push(edge);
      }
      return results;
    },
  };

  return { book, store };
}

// ── Test helpers ──────────────────────────────────────────────────────────────

/**
 * Seed a contact directly into a stub store, bypassing all validation.
 */
export function seedStubContact(
  store: StubContactStore,
  contact: Pick<Contact, 'certId' | 'publicKey' | 'displayName'> & Partial<Contact>,
  ts = Date.now(),
): void {
  const full: Contact = {
    source: 'manual',
    addedAt: ts,
    updatedAt: ts,
    ...contact,
  };
  store.contacts.set(full.certId, full);
  if (full.email) store.emailIndex.set(full.email.toLowerCase(), full.certId);
}

/**
 * Seed an edge directly into a stub store.
 */
export function seedStubEdge(store: StubContactStore, edge: EdgeRecord): void {
  store.edges.set(`${edge.responderCertId}:${edge.edgeType}`, edge);
  // Update primary edge reference on contact if MESSAGING
  if (edge.edgeType === 'MESSAGING') {
    const contact = store.contacts.get(edge.responderCertId);
    if (contact) {
      store.contacts.set(edge.responderCertId, {
        ...contact,
        edgeId: edge.edgeId,
      });
    }
  }
}

```
