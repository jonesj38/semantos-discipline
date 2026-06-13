---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/conversation-types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.852676+00:00
---

# core/protocol-types/src/conversation-types.ts

```ts
/**
 * Conversation Types — Phase 2: Multi-context conversation model.
 *
 * Defines the four conversation contexts (SELF, INDIVIDUAL, GROUP, AI_AGENT),
 * thread structure, message schema, and encryption metadata.
 *
 * These types are imported by shell (chat.ts, router.ts), loom
 * (PlexusService, ChatView), and paskian (cross-context learning).
 *
 * @module @semantos/protocol-types/conversation-types
 */

// ── Conversation Context ───────────────────────────────────────

/** The four conversation contexts routed through the semantic shell. */
export enum ConversationType {
  /** Self-reflection, journaling — encrypted at rest, visible only to user. */
  SELF = 'SELF',
  /** 1:1 encrypted conversation via BRC-85/86 ECDH MESSAGING edge. */
  INDIVIDUAL = 'INDIVIDUAL',
  /** Group conversation via ZONE node with shared key. */
  GROUP = 'GROUP',
  /** Conversation with an AI agent persona (local-only, no settlement). */
  AI_AGENT = 'AI_AGENT',
}

/**
 * Context weights for dimension scoring.
 * Self-reflection counts fully; group chat is diluted.
 */
export const ContextWeight: Record<ConversationType, number> = {
  [ConversationType.SELF]: 1.0,
  [ConversationType.INDIVIDUAL]: 0.7,
  [ConversationType.GROUP]: 0.5,
  [ConversationType.AI_AGENT]: 0.3,
};

// ── Encryption ─────────────────────────────────────────────────

/** Encryption metadata attached to a Thread. */
export interface EncryptionMetadata {
  /** Cipher algorithm. */
  algorithm: 'AES-256-GCM';
  /** Key derivation method. */
  keyDerivation: 'BRC-85' | 'BRC-86' | 'ZONE' | 'LOCAL';
  /** Plexus MESSAGING edge ID (INDIVIDUAL context). */
  edgeId?: string;
  /** Plexus ZONE node ID (GROUP context). */
  zoneId?: string;
}

// ── Thread ─────────────────────────────────────────────────────

/** A conversation thread — the unit of conversation state. */
export interface Thread {
  /** Unique thread identifier. */
  conversationId: string;
  /** Routing context type. */
  contextType: ConversationType;
  /** Human-readable name: contact name, group name, "Self", or agent name. */
  displayName: string;
  /** Participant certIds: 1 for SELF, 2 for INDIVIDUAL, 2+ for GROUP, 1 for AI_AGENT. */
  participants: string[];
  /** Encryption configuration (absent for SELF and AI_AGENT). */
  encryptionMetadata?: EncryptionMetadata;
  /** Ordered message IDs in this thread. */
  messageIds: string[];
  /** ISO 8601 creation timestamp. */
  createdAt: string;
  /** ISO 8601 last activity timestamp. */
  lastActivity: string;
  /** Number of unread messages. */
  unreadCount: number;
  /** User preference: pinned threads stay at top. */
  isPinned: boolean;
  /** User preference: muted threads don't notify. */
  isMuted: boolean;
}

// ── Message ────────────────────────────────────────────────────

/** A conversation message — persisted as a kernel cell. */
export interface ConversationMessage {
  /** Unique message identifier (UUID). */
  id: string;
  /** Conversation thread this message belongs to. */
  conversationId: string;
  /** Routing context. */
  contextType: ConversationType;
  /** Message role (user or assistant). */
  role: 'user' | 'assistant';
  /** Plaintext content (stored encrypted in kernel for INDIVIDUAL/GROUP). */
  content: string;
  /** AES-256-GCM ciphertext for transport (Base64). */
  encryptedContent?: string;
  /** Sender identity (certId). */
  senderId: string;
  /** ISO 8601 creation timestamp. */
  timestamp: string;
  /** SHA-256 hash of the previous message in thread (hash chain). */
  prevMessageHash: string;
  /** ECDSA signature over plaintext content (Base64). */
  signature: string;
  /** Associated life dimension (optional tagging). */
  dimensionTag?: string;
}

// ── Plexus Edge Types ──────────────────────────────────────────

/** Typed Plexus edge types used in Phase 2 conversations. */
export type PlexusEdgeType =
  | 'MESSAGING'
  | 'DATA_ACCESS'
  | 'ATTESTATION'
  | 'ROLE_ASSIGNMENT'
  | 'AUTHORITY'
  | 'TRANSFER'
  | 'CUSTOM';

/** Extended edge record with type information. */
export interface TypedEdge {
  edgeId: string;
  initiator: string;
  responder: string;
  edgeType: PlexusEdgeType;
  sharedSecret?: string;
  createdAt: string;
}

// ── ZONE ───────────────────────────────────────────────────────

/** A Plexus ZONE node for group conversations. */
export interface ZoneState {
  zoneId: string;
  groupName: string;
  createdBy: string;
  memberList: string[];
  derivedKey: string;
  createdAt: string;
}

// ── Organization ──────────────────────────────────────────────

/** Team member role for ROLE_ASSIGNMENT edges within an ORGANIZATION. */
export type OrganizationRole = 'admin' | 'tradie' | 'viewer';

/** A Plexus ORGANIZATION node for business identity (Phase 3). */
export interface OrganizationState {
  /** Derived org identity certId. */
  orgCertId: string;
  /** Human-readable business name. */
  orgName: string;
  /** Founder's certId (AUTHORITY edge source). */
  founderCertId: string;
  /** Team member certIds. */
  memberList: string[];
  /** HD-derived public key for the org node. */
  derivedPublicKey: string;
  /** Business metadata. */
  metadata: OrganizationMetadata;
  /** ISO 8601 creation timestamp. */
  createdAt: string;
}

/** Business metadata stored in SemanticFS. */
export interface OrganizationMetadata {
  description?: string;
  /** Service category (plumbing, electrical, cleaning, consulting, etc). */
  category?: string;
  /** ZONE ID for service area. */
  serviceArea?: string;
  /** Contact email for the business. */
  contactEmail?: string;
  /** Avatar / logo URL. */
  avatarUrl?: string;
  /** Business hours as JSON: { mon: ["08:00","17:00"], ... } */
  hoursJson?: Record<string, [string, string]>;
  /** Founder-configurable markup percent (0-50). */
  markupPercent?: number;
}

/** Team member record within an ORGANIZATION. */
export interface TeamMember {
  certId: string;
  role: OrganizationRole;
  edgeId: string;
  joinedAt: string;
}

// ── AI Agent ───────────────────────────────────────────────────

/** An AI agent persona for AI_AGENT conversations. */
export interface AgentPersona {
  id: string;
  name: string;
  expertise: string;
  personality: string;
  systemPrompt: string;
  dimensionFocus?: string[];
}

// ── Context Config ─────────────────────────────────────────────

/** Configuration returned by the context router for each ConversationType. */
export interface ContextConfig {
  /** System prompt prefix for LLM routing. */
  systemPromptPrefix: string;
  /** Whether to run LLM extraction on messages. */
  extractionEnabled: boolean;
  /** Weight for dimension scoring (1.0 = full, 0.3 = lowest). */
  contextWeight: number;
  /** Whether messages must be encrypted before persistence. */
  encryptionRequired: boolean;
  /** Governance constraint level. */
  governanceLevel: 'L0' | 'L1';
  /** Settlement cost in satoshis (0 = no settlement). */
  settlementSats: number;
}

// ── Serialization helpers ──────────────────────────────────────

/** Serialized thread state for JSON persistence. */
export interface SerializedConversationStore {
  threads: Array<[string, Thread]>;
  messages: Array<[string, ConversationMessage]>;
}

```
