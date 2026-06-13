---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-contracts/src/graph.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.821981+00:00
---

# core/plexus-contracts/src/graph.ts

```ts
/**
 * Plexus DAG graph types.
 *
 * Based on Plexus Technical Requirements v1.3 — Tenant Node Record (component 19),
 * Edge Domain (component 12), Vendor SDK (component 5).
 */

/**
 * Structural node types in the DAG hierarchy.
 * Per Plexus Technical Requirements v1.3 §19 (Tenant Node Record) and visualiser schema.
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
 * How a tenant node is enrolled in disaster recovery.
 * Per Plexus Technical Requirements v1.3 §19 (recoveryVia enum).
 */
export type RecoveryVia =
  | 'PLEXUS_CHALLENGES'
  | 'PARENT_MANAGED'
  | 'SELF_MANAGED'
  | 'NONE';

/** Structural node in the Directed Acyclic Graph (DAG). */
export interface PlexusNode {
  /** 32-byte hex cert_id. */
  certId: string;
  /** Resource identifier for this node. */
  resourceId: string;
  /** Parent cert_id (null for root). */
  parentCertId: string | null;
  /** Monotonic child index within parent context. Per §4.2: never rewinds. */
  childIndex: number;
  /** 4-byte uint32 domain flag. */
  domainFlag: number;
  /** Derivation path from root. */
  derivationPath: string;
  /** 33-byte compressed public key, hex-encoded. */
  publicKey: string;
  /** Structural node type from the DAG hierarchy. */
  nodeType?: NodeType;
  /** How this node participates in disaster recovery. */
  recoveryVia?: RecoveryVia;
  /**
   * On-chain Metanet Protocol anchor tx id (nullable 32-byte BYTEA).
   * Per §19: included for future Metanet Protocol anchoring compatibility.
   */
  anchorTxid?: string | null;
}

/**
 * Functional purpose of an edge between two DAG nodes.
 * Per Plexus Technical Requirements v1.3 §12 (Edge Domain) and the visualiser schema.
 * Uniqueness constraint (§1.1.7): (certId, appId, counterpartyCert, edgeType) must be unique.
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
 * Edge recovery policy.
 * Per Plexus Client Requirements v2.1 §1.1 and Technical Requirements v1.3 §12.
 * - NONE: ephemeral, no backup recipe generated
 * - BACKUP_ON_CREATE: BRC-69 recipe stored atomically at edge creation
 * - BACKUP_ON_CONFIRM: recipe stored on a subsequent /edge/enroll call
 * - PARENT_MANAGED: parent node in the DAG manages backup/rotation
 */
export type EdgeRecoveryPolicy =
  | 'NONE'
  | 'BACKUP_ON_CREATE'
  | 'BACKUP_ON_CONFIRM'
  | 'PARENT_MANAGED';

/**
 * Edge record connecting two nodes in the DAG.
 *
 * Per §2.5.5 (Compact Metadata Storage): the system shall record ONLY the
 * counterparty's certificate ID and the signing key index. The actual ECDH
 * shared secret value is never stored — not even a hash of it.
 *
 * Per §1.1.8: edges are soft-deleted (revokedAt timestamp), never hard-deleted,
 * to preserve the cryptographic audit trail.
 */
export interface PlexusEdge {
  /** Unique edge identifier (SHA-256 derived). */
  edgeId: string;
  /** cert_id of the initiating party. */
  initiatorCertId: string;
  /** cert_id of the responding party. */
  responderCertId: string;
  /** Functional purpose of this edge. Part of the uniqueness tuple per §1.1.7. */
  edgeType: EdgeType;
  /**
   * BKDS signing key index (invoiceNumber) used to establish this edge.
   * Per §2.5.5: this is the only derivation metadata kept for edge reconstruction.
   * The client re-derives the ECDH shared secret locally using this index
   * without exposing the secret to Plexus.
   */
  signingKeyIndex: number;
  /** Recovery policy declared at creation time. Immutable after creation. */
  recoveryPolicy: EdgeRecoveryPolicy;
  /**
   * BRC-69 key linkage revelation recipe.
   * Present only when recoveryPolicy is BACKUP_ON_CREATE (stored atomically)
   * or after /edge/enroll is called for BACKUP_ON_CONFIRM edges.
   */
  backupRecipe?: string;
  /**
   * Application context for this edge. Part of the uniqueness tuple per §1.1.7.
   * Allows the same two parties to hold multiple typed edges per app.
   */
  appId?: string;
  /**
   * Soft-delete timestamp (Unix ms). Per §1.1.8: never hard-delete edges.
   * The edge_records row is retained permanently for the cryptographic audit trail.
   */
  revokedAt?: number;
  /** Unix timestamp in milliseconds when the edge was created. */
  createdAt: number;
}

```
