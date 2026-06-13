---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/contact-book/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.944904+00:00
---

# core/contact-book/src/types.ts

```ts
/**
 * Contact book types for Semantos.
 *
 * A Contact is a person or entity whose BRC-52 certId you know. The contacts
 * book maps human-readable identifiers (name, email) to cryptographic
 * identifiers (certId, publicKey) and tracks connection state (edgeId,
 * signingKeyIndex).
 *
 * Design invariants (sourced from Plexus Client Requirements v2.1 and
 * Technical Requirements v1.3):
 *   - `certId` is the stable primary key — SHA-256 of the cert preimage, immutable.
 *   - Per §2.5.5: only counterparty certId + signingKeyIndex are stored for edges.
 *     The ECDH shared secret is NEVER stored, not even a hash of it. The client
 *     re-derives it locally from the signingKeyIndex when needed.
 *   - Per §1.1.8: edges are soft-deleted (revokedAt timestamp) for audit trail.
 *   - Per §1.1.7: uniqueness is on (certId, appId, counterpartyCert, edgeType).
 *     A contact may have multiple edges of different types.
 *
 * Spec source: docs/prd/PHASE-38-CONTACTS-PKI.md
 *              Plexus Client Requirements v2.1
 *              Plexus Technical Requirements v1.3
 */

// ── Edge taxonomy ─────────────────────────────────────────────────────────────

/**
 * Functional purpose of an edge between two DAG nodes.
 * Per Plexus Technical Requirements v1.3 §12 (Edge Domain) and visualiser schema.
 *
 * Uniqueness constraint (§1.1.7): (certId, appId, counterpartyCert, edgeType)
 * must remain strictly unique — different edge types establish distinct
 * relationships between the same two parties.
 */
export type EdgeType =
  | 'MESSAGING'
  | 'DATA_ACCESS'
  | 'ROLE_ASSIGNMENT'
  | 'AUTHORITY'
  | 'TRANSFER'
  | 'ATTESTATION'
  | 'CUSTOM';

/**
 * Edge recovery policy declared at creation time. Immutable after creation.
 * Per Plexus Client Requirements v2.1 §1.1 and Technical Requirements v1.3 §12.
 */
export type EdgeRecoveryPolicy =
  | 'NONE'             // Ephemeral — no backup recipe generated
  | 'BACKUP_ON_CREATE' // BRC-69 recipe stored atomically at edge creation
  | 'BACKUP_ON_CONFIRM'// Recipe stored on a subsequent /edge/enroll call
  | 'PARENT_MANAGED';  // Parent node in the DAG manages backup/rotation

// ── Node taxonomy ─────────────────────────────────────────────────────────────

/**
 * Structural node type in the Plexus DAG hierarchy.
 * Per Plexus Technical Requirements v1.3 §19 (Tenant Node Record).
 */
export type NodeType =
  | 'PLATFORM'
  | 'ORGANIZATION'
  | 'SUB_ORG'
  | 'INDIVIDUAL'
  | 'DEVICE'
  | 'ZONE'
  | 'OBJECT';

/**
 * How this contact's node is enrolled in Plexus disaster recovery.
 * Per Plexus Technical Requirements v1.3 §19 (recoveryVia enum).
 */
export type RecoveryVia =
  | 'PLEXUS_CHALLENGES'
  | 'PARENT_MANAGED'
  | 'SELF_MANAGED'
  | 'NONE';

// ── Core contact record ───────────────────────────────────────────────────────

/**
 * A stored contact — a person/entity whose BRC-52 identity we know.
 *
 * `certId` is the stable, immutable key. All other fields are mutable.
 *
 * Note: `sharedSecretHash` intentionally absent. Per Plexus spec §2.5.5,
 * the ECDH shared secret value is never stored at any layer. Use
 * `EdgeRecord.signingKeyIndex` to re-derive it locally when needed.
 */
export interface Contact {
  // ── Cryptographic identity ──────────────────────────────────────────────
  /** BRC-52 cert_id — SHA-256 of the canonical cert preimage. Primary key. */
  certId: string;
  /** 33-byte compressed secp256k1 public key, hex-encoded. */
  publicKey: string;

  // ── Human-readable fields ───────────────────────────────────────────────
  /** Display name the local user gives this contact. Free text, mutable. */
  displayName: string;
  /**
   * Email address, if known. For root certs this comes from
   * `identityPort.resolveIdentity().email`. May be absent for child certs.
   */
  email?: string;

  // ── Structural context (from DAG resolution) ─────────────────────────────
  /** Node type in the Plexus DAG hierarchy. */
  nodeType?: NodeType;
  /** Parent cert_id in the identity DAG. Null for root certs. */
  parentCertId?: string | null;
  /**
   * Direct children of this cert in the DAG, if resolved.
   * Only populated when `source === 'discovered'` and a full subtree was
   * fetched via `identityPort.querySubtree()`.
   */
  children?: ReadonlyArray<{
    readonly certId: string;
    readonly childIndex: number;
    readonly resourceId: string;
  }>;

  // ── Recovery context ─────────────────────────────────────────────────────
  /**
   * How this contact participates in Plexus disaster recovery.
   * Per §19 (Tenant Node Record): recoveryVia enum.
   */
  recoveryVia?: RecoveryVia;

  // ── Connection state ────────────────────────────────────────────────────
  /**
   * Primary (MESSAGING) edge ID if `connectTo()` has been called.
   * For non-MESSAGING edges or multiple edges, use `getEdge(certId, edgeType)`.
   */
  edgeId?: string;

  // ── Provenance ──────────────────────────────────────────────────────────
  /**
   * How this contact was added:
   *   'manual'     — user typed in the certId / details directly
   *   'discovered' — resolved from the DAG via `resolveContact()` or `discoverByEmail()`
   *   'imported'   — loaded from an external file or QR code
   */
  source: 'manual' | 'discovered' | 'imported';

  /** Unix ms when the contact was first added. */
  addedAt: number;
  /** Unix ms when the contact record was last modified. */
  updatedAt: number;
}

// ── Edge record ───────────────────────────────────────────────────────────────

/**
 * A cryptographic relationship (edge) between the local identity and a contact.
 *
 * Per Plexus spec §2.5.5: stores ONLY the counterparty certId and the signing
 * key index (BKDS invoiceNumber). The ECDH shared secret is never stored —
 * the client re-derives it locally using signingKeyIndex when needed.
 *
 * Per §1.1.8: edges are soft-deleted (revokedAt) to preserve the cryptographic
 * audit trail. The record is never hard-deleted.
 *
 * Uniqueness (§1.1.7): (initiatorCertId, appId, responderCertId, edgeType).
 */
export interface EdgeRecord {
  /** The ECDH edge ID returned by `identityPort.createEdge()`. */
  edgeId: string;
  /** The local cert that initiated the edge. */
  initiatorCertId: string;
  /** The contact's cert that responded. */
  responderCertId: string;
  /** Functional purpose of this edge. Part of the uniqueness tuple. */
  edgeType: EdgeType;
  /**
   * BKDS signing key index (invoiceNumber) used to derive the ECDH key.
   * Per §2.5.5: this is the only derivation parameter stored for edge
   * reconstruction. The client uses it to locally re-derive the shared
   * secret without exposing it to any server.
   */
  signingKeyIndex: number;
  /** Recovery policy declared at creation. Immutable after creation. */
  recoveryPolicy: EdgeRecoveryPolicy;
  /**
   * BRC-69 key linkage revelation recipe for disaster recovery.
   * Present only when recoveryPolicy is BACKUP_ON_CREATE (atomically stored)
   * or after the subsequent /edge/enroll call for BACKUP_ON_CONFIRM edges.
   */
  backupRecipe?: string;
  /**
   * Application context. Part of the uniqueness tuple per §1.1.7.
   * Allows the same two parties to hold multiple typed edges per app.
   */
  appId?: string;
  /**
   * Soft-delete timestamp (Unix ms). Per §1.1.8: edges are never hard-deleted.
   * Set by `revokeEdge()`. The record is retained for the cryptographic audit trail.
   */
  revokedAt?: number;
  /** Unix ms when the edge was established. */
  createdAt: number;
}

// ── Discovery result ──────────────────────────────────────────────────────────

/**
 * Result of resolving a certId from the DAG, before saving as a Contact.
 */
export interface ContactDiscoveryResult {
  certId: string;
  publicKey: string;
  email?: string;
  children?: ReadonlyArray<{
    readonly certId: string;
    readonly childIndex: number;
    readonly resourceId: string;
  }>;
  verified: boolean;
}

// ── Mutation helpers ──────────────────────────────────────────────────────────

/** Fields that can be patched on an existing Contact via `updateContact()`. */
export type ContactPatch = Partial<Pick<Contact, 'displayName' | 'email' | 'nodeType' | 'recoveryVia'>>;

/** Options for `addContact()`. */
export interface AddContactOptions {
  email?: string;
  source?: Contact['source'];
  nodeType?: NodeType;
  /**
   * If true, fetch cert details from the DAG via `identityPort`.
   * When false, `publicKey` must be supplied.
   */
  resolveFromDag?: boolean;
  publicKey?: string;
}

/** Options for `connectTo()`. */
export interface ConnectOptions {
  /**
   * Functional purpose of the edge. Defaults to 'MESSAGING' (the primary
   * peer-to-peer communication channel per Plexus spec).
   */
  edgeType?: EdgeType;
  /**
   * Recovery policy. Defaults to 'NONE' (ephemeral — safest default since
   * it generates no backup recipe and carries no Plexus dependency).
   */
  recoveryPolicy?: EdgeRecoveryPolicy;
  /**
   * BRC-69 key linkage recipe to store. Required when recoveryPolicy is
   * BACKUP_ON_CREATE. The caller (Vendor SDK) computes this client-side
   * before passing it here.
   */
  backupRecipe?: string;
  /** Application context for the edge uniqueness tuple. */
  appId?: string;
}

// ── ContactBook interface ─────────────────────────────────────────────────────

/**
 * ContactBook — the full contacts surface.
 *
 * Implementations:
 *   - `ContactStore` — StorageAdapter-backed, production
 *   - `StubContactBook` — in-memory, for tests and demos
 */
export interface ContactBook {
  // ── Local CRUD ────────────────────────────────────────────────────────

  /**
   * Add a contact by certId. Idempotent: if the certId already exists,
   * updates the display name only.
   *
   * @throws `CERT_NOT_FOUND` if `resolveFromDag` is true but the cert is not in the DAG.
   * @throws `MISSING_PUBLIC_KEY` if `resolveFromDag` is false and no `publicKey` is provided.
   */
  addContact(certId: string, displayName: string, opts?: AddContactOptions): Promise<Contact>;

  /** Get a contact by certId. Returns null if not found locally. */
  getContact(certId: string): Contact | null;

  /** List all locally stored contacts, ordered by `displayName` ascending. */
  listContacts(): Contact[];

  /**
   * Apply a patch to an existing contact. Returns the updated contact.
   * @throws `CONTACT_NOT_FOUND` if certId is not in the local book.
   */
  updateContact(certId: string, patch: ContactPatch): Contact;

  /**
   * Remove a contact from the local book. Does not revoke edges — use
   * `revokeEdge()` first if the relationship should be auditably closed.
   * Returns true if the contact existed.
   */
  removeContact(certId: string): boolean;

  /** Search contacts by display name or email (case-insensitive substring match). */
  search(query: string): Contact[];

  // ── DAG discovery ─────────────────────────────────────────────────────

  /**
   * Fetch a contact's cert details from the DAG, save locally, and return
   * the updated contact. Requires `identityPort` to be bound.
   *
   * @throws `PORT_NOT_BOUND` if identityPort is not bound.
   * @throws `CERT_NOT_FOUND` if the DAG does not know this certId.
   */
  resolveContact(certId: string): Promise<Contact>;

  /**
   * Discover a root identity by email. Checks local index first, falls back
   * to the DAG if identityPort is bound. Returns null if not found.
   */
  discoverByEmail(email: string): Promise<Contact | null>;

  // ── Edge establishment ────────────────────────────────────────────────

  /**
   * Establish an ECDH edge between the local cert (`myCertId`) and a
   * contact (`theirCertId`).
   *
   * Idempotent per (myCertId, theirCertId, edgeType, appId): if an edge of
   * the same type already exists and is not revoked, returns it without
   * creating a new one.
   *
   * Requires `identityPort` to be bound.
   * Requires `theirCertId` to be in the local contact book.
   *
   * @throws `PORT_NOT_BOUND` if identityPort is not bound.
   * @throws `CONTACT_NOT_FOUND` if `theirCertId` is not in the local book.
   */
  connectTo(myCertId: string, theirCertId: string, opts?: ConnectOptions): Promise<EdgeRecord>;

  /**
   * Soft-delete an edge by setting `revokedAt`. Per Plexus §1.1.8, the edge
   * record is retained permanently for the cryptographic audit trail.
   *
   * @throws `CONTACT_NOT_FOUND` if `theirCertId` is not in the local book.
   * @throws `EDGE_NOT_FOUND` if no active edge of the given type exists.
   * @throws `EDGE_ALREADY_REVOKED` if the edge was already revoked.
   */
  revokeEdge(myCertId: string, theirCertId: string, edgeType?: EdgeType): Promise<void>;

  /**
   * True iff an active (non-revoked) edge of the given type exists for `theirCertId`.
   * Defaults to 'MESSAGING' if edgeType is omitted.
   */
  isConnected(theirCertId: string, edgeType?: EdgeType): boolean;

  /**
   * Return the stored edge record for `theirCertId` and `edgeType`.
   * Defaults to 'MESSAGING'. Returns null if no such edge exists.
   * Includes revoked edges — check `revokedAt` if you only want active ones.
   */
  getEdge(theirCertId: string, edgeType?: EdgeType): EdgeRecord | null;

  /**
   * Return all edge records (active and revoked) to a given contact.
   * Useful for displaying the full cryptographic audit trail.
   */
  listEdgesTo(theirCertId: string): EdgeRecord[];
}

// ── Error codes ───────────────────────────────────────────────────────────────

export type ContactBookErrorCode =
  | 'CONTACT_NOT_FOUND'
  | 'CERT_NOT_FOUND'
  | 'MISSING_PUBLIC_KEY'
  | 'ALREADY_CONNECTED'
  | 'EDGE_NOT_FOUND'
  | 'EDGE_ALREADY_REVOKED'
  | 'PORT_NOT_BOUND'
  | 'STORAGE_ERROR';

export class ContactBookError extends Error {
  readonly code: ContactBookErrorCode;
  constructor(code: ContactBookErrorCode, message: string) {
    super(message);
    this.name = 'ContactBookError';
    this.code = code;
  }
}

```
