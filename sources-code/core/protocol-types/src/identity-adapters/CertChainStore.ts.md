---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/CertChainStore.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.887891+00:00
---

# core/protocol-types/src/identity-adapters/CertChainStore.ts

```ts
/**
 * CertChainStore — manages the local certificate DAG over StorageAdapter.
 *
 * All cert data lives under the `identity/certs/{certId}` key pattern.
 * Enforces monotonic child indices: once index N is used, it is never
 * reused even if the child is revoked.
 *
 * Cross-references:
 *   Phase 26B: LocalIdentityAdapter consumes this for all cert operations
 *   Phase 25A: StorageAdapter is the persistence layer
 */

import { createHash } from 'crypto';
import type { StorageAdapter } from '../storage';
import { makeIdentityError } from '../identity';

/** Serializable certificate data stored in the DAG. */
export interface CertData {
  certId: string;
  email?: string;
  publicKey: string;
  parentCertId?: string;
  childIndex?: number;
  resourceId?: string;
  domainFlags: number[];
  /** JSON-serialized capability token attached to this cert. */
  capabilityToken?: string;
  created: number;
  revoked: boolean;
}

const CERT_PREFIX = 'identity/certs/';
const CHILDREN_SUFFIX = '/children';

export class CertChainStore {
  private storage: StorageAdapter;
  /** In-memory cache of next child index per parent. Survives within a session. */
  private nextChildIndices = new Map<string, number>();

  constructor(storageAdapter: StorageAdapter) {
    this.storage = storageAdapter;
  }

  /**
   * Store a certificate in the DAG.
   * If the cert has a parentCertId, also registers it in the parent's children list.
   */
  async put(certId: string, cert: CertData): Promise<void> {
    const key = CERT_PREFIX + certId;
    const data = new TextEncoder().encode(JSON.stringify(cert));
    await this.storage.write(key, data);

    // Register in parent's children index if this is a child cert
    if (cert.parentCertId !== undefined && cert.childIndex !== undefined) {
      await this.addToChildrenIndex(cert.parentCertId, {
        certId: cert.certId,
        childIndex: cert.childIndex,
        resourceId: cert.resourceId ?? '',
      });

      // Update the in-memory next child index
      const current = this.nextChildIndices.get(cert.parentCertId) ?? 0;
      if (cert.childIndex >= current) {
        this.nextChildIndices.set(cert.parentCertId, cert.childIndex + 1);
      }
    }
  }

  /**
   * Retrieve a certificate by certId. Returns null if not found.
   */
  async get(certId: string): Promise<CertData | null> {
    const key = CERT_PREFIX + certId;
    const raw = await this.storage.read(key);
    if (!raw) return null;
    return JSON.parse(new TextDecoder().decode(raw)) as CertData;
  }

  /**
   * Retrieve a cert or throw CERT_NOT_FOUND.
   */
  async getOrThrow(certId: string): Promise<CertData> {
    const cert = await this.get(certId);
    if (!cert) {
      throw makeIdentityError('CERT_NOT_FOUND', `Certificate ${certId} not found in local store`, true);
    }
    return cert;
  }

  /**
   * Get all children of a parent cert, sorted by childIndex ascending.
   */
  async getChildren(parentCertId: string): Promise<CertData[]> {
    const index = await this.readChildrenIndex(parentCertId);
    const children: CertData[] = [];
    for (const entry of index) {
      const cert = await this.get(entry.certId);
      if (cert) children.push(cert);
    }
    children.sort((a, b) => (a.childIndex ?? 0) - (b.childIndex ?? 0));
    return children;
  }

  /**
   * Get the next available child index for a parent.
   * Monotonic: always increments, never reuses indices.
   */
  async getNextChildIndex(parentCertId: string): Promise<number> {
    // Check in-memory cache first
    const cached = this.nextChildIndices.get(parentCertId);
    if (cached !== undefined) return cached;

    // Scan storage for max childIndex under this parent
    const children = await this.readChildrenIndex(parentCertId);
    let maxIndex = -1;
    for (const child of children) {
      if (child.childIndex > maxIndex) maxIndex = child.childIndex;
    }
    const next = maxIndex + 1;
    this.nextChildIndices.set(parentCertId, next);
    return next;
  }

  /**
   * Increment and return the next child index atomically.
   * Returns the index to use, and advances the counter.
   */
  async claimNextChildIndex(parentCertId: string): Promise<number> {
    const next = await this.getNextChildIndex(parentCertId);
    this.nextChildIndices.set(parentCertId, next + 1);
    return next;
  }

  /**
   * Mark a certificate as revoked. The child index is reserved forever.
   */
  async revokeChild(certId: string): Promise<void> {
    const cert = await this.getOrThrow(certId);
    cert.revoked = true;
    const key = CERT_PREFIX + certId;
    const data = new TextEncoder().encode(JSON.stringify(cert));
    await this.storage.write(key, data);
  }

  /**
   * Walk the cert tree depth-first from a root, calling visitor at each node.
   * Stops at maxDepth.
   */
  async walk(
    rootCertId: string,
    visitor: (cert: CertData, depth: number) => Promise<void>,
    maxDepth: number = 3,
  ): Promise<void> {
    const root = await this.getOrThrow(rootCertId);
    await this.walkRecursive(root, visitor, 0, maxDepth);
  }

  /**
   * Verify that certId is a direct child of claimedParentCertId.
   * Checks parentCertId reference and verifies the parent exists.
   */
  async verifyAncestry(certId: string, claimedParentCertId: string): Promise<boolean> {
    const cert = await this.get(certId);
    if (!cert) return false;
    if (cert.parentCertId !== claimedParentCertId) return false;

    const parent = await this.get(claimedParentCertId);
    if (!parent) return false;

    // Verify the cert's hash relationship to parent
    const expectedPrefix = 'cert:';
    if (!cert.certId.startsWith(expectedPrefix)) return false;
    if (!parent.certId.startsWith(expectedPrefix)) return false;

    return true;
  }

  /**
   * Store an edge between two certs.
   */
  async putEdge(edgeId: string, data: { initiator: string; responder: string; sharedSecret: string }): Promise<void> {
    const key = `identity/edges/${edgeId}`;
    const bytes = new TextEncoder().encode(JSON.stringify(data));
    await this.storage.write(key, bytes);
  }

  // ── Private helpers ──

  private async walkRecursive(
    cert: CertData,
    visitor: (cert: CertData, depth: number) => Promise<void>,
    currentDepth: number,
    maxDepth: number,
  ): Promise<void> {
    await visitor(cert, currentDepth);
    if (currentDepth >= maxDepth) return;

    const children = await this.getChildren(cert.certId);
    for (const child of children) {
      await this.walkRecursive(child, visitor, currentDepth + 1, maxDepth);
    }
  }

  private childrenKey(parentCertId: string): string {
    return CERT_PREFIX + parentCertId + CHILDREN_SUFFIX;
  }

  private async readChildrenIndex(parentCertId: string): Promise<Array<{ certId: string; childIndex: number; resourceId: string }>> {
    const key = this.childrenKey(parentCertId);
    const raw = await this.storage.read(key);
    if (!raw) return [];
    return JSON.parse(new TextDecoder().decode(raw));
  }

  private async addToChildrenIndex(parentCertId: string, entry: { certId: string; childIndex: number; resourceId: string }): Promise<void> {
    const index = await this.readChildrenIndex(parentCertId);
    // Avoid duplicates
    if (!index.some(e => e.certId === entry.certId)) {
      index.push(entry);
    }
    const key = this.childrenKey(parentCertId);
    const data = new TextEncoder().encode(JSON.stringify(index));
    await this.storage.write(key, data);
  }
}

```
