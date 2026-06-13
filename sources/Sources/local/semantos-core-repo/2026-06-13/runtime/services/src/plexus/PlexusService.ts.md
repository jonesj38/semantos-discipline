---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/plexus/PlexusService.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.100337+00:00
---

# runtime/services/src/plexus/PlexusService.ts

```ts
/**
 * PlexusService — renderer-agnostic wrapper with useSyncExternalStore state.
 *
 * Wraps PlexusAdapter with state management. All async operations
 * trigger state updates and notify listeners. Never imports React.
 */

import type { PlexusAdapter, PlexusConfig, PlexusState } from './types';
import { createAdapter } from './config';
import type {
  PlexusEdgeType,
  TypedEdge,
  ZoneState,
  OrganizationState,
  OrganizationMetadata,
  OrganizationRole,
  TeamMember,
} from '../../../../core/protocol-types/src/conversation-types';

export class PlexusService {
  private adapter: PlexusAdapter;
  private listeners = new Set<() => void>();
  private state: PlexusState = {
    identities: new Map(),
    edges: new Map(),
  };

  // Phase 2: Typed edge metadata and ZONE state
  private typedEdges: Map<string, TypedEdge> = new Map();
  private zones: Map<string, ZoneState> = new Map();

  // Phase 3: Organization state and team membership
  private organizations: Map<string, OrganizationState> = new Map();
  private teamMembers: Map<string, TeamMember[]> = new Map(); // orgCertId → members

  constructor(config: PlexusConfig) {
    this.adapter = createAdapter(config);
  }

  /** Register a new identity. Updates state and notifies listeners. */
  async registerIdentity(email: string): Promise<{
    certId: string;
    publicKey: string;
  }> {
    const result = await this.adapter.registerIdentity(email);

    this.state = {
      ...this.state,
      identities: new Map(this.state.identities).set(result.certId, {
        certId: result.certId,
        publicKey: result.publicKey,
        created: Date.now(),
      }),
      currentIdentity: {
        certId: result.certId,
        email,
      },
      lastOperation: {
        method: 'registerIdentity',
        timestamp: Date.now(),
        success: true,
      },
    };

    this.notifyListeners();
    return result;
  }

  /** Derive a child identity. Updates state and notifies listeners. */
  async deriveChild(
    parentCertId: string,
    resourceId: string,
    domainFlag: number,
  ): Promise<{
    certId: string;
    publicKey: string;
    childIndex: number;
  }> {
    const result = await this.adapter.deriveChild(parentCertId, resourceId, domainFlag);

    this.state = {
      ...this.state,
      identities: new Map(this.state.identities).set(result.certId, {
        certId: result.certId,
        publicKey: result.publicKey,
        created: Date.now(),
      }),
      lastOperation: {
        method: 'deriveChild',
        timestamp: Date.now(),
        success: true,
      },
    };

    this.notifyListeners();
    return result;
  }

  /** Resolve an identity. Read-only — does not update state. */
  async resolveIdentity(certId: string): Promise<{
    certId: string;
    publicKey: string;
    email?: string;
    created: number;
    updated: number;
    children?: Array<{ certId: string; childIndex: number; resourceId: string }>;
  }> {
    return this.adapter.resolveIdentity(certId);
  }

  /** Create an edge between two identities. Updates state and notifies listeners. */
  async createEdge(
    initiatorCertId: string,
    responderCertId: string,
  ): Promise<{
    edgeId: string;
    sharedSecret: string;
  }> {
    const result = await this.adapter.createEdge(initiatorCertId, responderCertId);

    this.state = {
      ...this.state,
      edges: new Map(this.state.edges).set(result.edgeId, {
        edgeId: result.edgeId,
        initiator: initiatorCertId,
        responder: responderCertId,
      }),
      lastOperation: {
        method: 'createEdge',
        timestamp: Date.now(),
        success: true,
      },
    };

    this.notifyListeners();
    return result;
  }

  /** Query a subtree. Read-only — does not update state. */
  async querySubtree(rootCertId: string, depth: number) {
    return this.adapter.querySubtree(rootCertId, depth);
  }

  /** Present a capability. Read-only — does not update state. */
  async presentCapability(certId: string, capabilityId: string) {
    return this.adapter.presentCapability(certId, capabilityId);
  }

  /** Initiate recovery. Read-only — does not update state. */
  async initiateRecovery(email: string) {
    return this.adapter.initiateRecovery(email);
  }

  /** Submit recovery challenge answers. Read-only — does not update state. */
  async submitChallengeAnswers(
    sessionId: string,
    answers: Array<{ challengeId: string; answer: string }>,
  ) {
    return this.adapter.submitChallengeAnswers(sessionId, answers);
  }

  /** Send authenticated message. Read-only — does not update state. */
  async sendAuthenticated(
    senderCertId: string,
    receiverCertId: string,
    payload: Record<string, string>,
  ) {
    return this.adapter.sendAuthenticated(senderCertId, receiverCertId, payload);
  }

  // ── Phase 2: Typed Edge Operations ───────────────────────────

  /**
   * Create a typed edge between two identities.
   * Wraps createEdge() with edge type metadata.
   */
  async createTypedEdge(
    initiatorCertId: string,
    responderCertId: string,
    edgeType: PlexusEdgeType,
  ): Promise<TypedEdge> {
    const result = await this.createEdge(initiatorCertId, responderCertId);
    const typed: TypedEdge = {
      edgeId: result.edgeId,
      initiator: initiatorCertId,
      responder: responderCertId,
      edgeType,
      sharedSecret: result.sharedSecret,
      createdAt: new Date().toISOString(),
    };
    this.typedEdges.set(result.edgeId, typed);
    this.notifyListeners();
    return typed;
  }

  /** Get all edges of a specific type involving a certId. */
  getEdgesByType(certId: string, edgeType: PlexusEdgeType): TypedEdge[] {
    return Array.from(this.typedEdges.values()).filter(
      e => e.edgeType === edgeType && (e.initiator === certId || e.responder === certId),
    );
  }

  /** Get a typed edge by ID. */
  getTypedEdge(edgeId: string): TypedEdge | undefined {
    return this.typedEdges.get(edgeId);
  }

  /** Get all typed edges (for graph dump). */
  getAllTypedEdges(): TypedEdge[] {
    return Array.from(this.typedEdges.values());
  }

  // ── Phase 3: Organization Operations ─────────────────────────

  /**
   * Derive an ORGANIZATION node from a founder's identity.
   * Uses HMAC-SHA-512 HD key derivation with domain flag 0x0c.
   * Creates AUTHORITY edge from founder to org.
   */
  async deriveOrganization(
    founderCertId: string,
    orgName: string,
    metadata: OrganizationMetadata = {},
  ): Promise<OrganizationState> {
    const orgId = `org-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
    // Derive org key: child derivation with ORGANIZATION domain flag (0x0c)
    const child = await this.adapter.deriveChild(founderCertId, orgId, 0x0c);
    const org: OrganizationState = {
      orgCertId: child.certId,
      orgName,
      founderCertId,
      memberList: [founderCertId],
      derivedPublicKey: child.publicKey,
      metadata,
      createdAt: new Date().toISOString(),
    };
    this.organizations.set(child.certId, org);
    this.teamMembers.set(child.certId, [{
      certId: founderCertId,
      role: 'admin',
      edgeId: '', // populated below
      joinedAt: org.createdAt,
    }]);

    // Create AUTHORITY edge: founder → org
    const edge = await this.createTypedEdge(founderCertId, child.certId, 'AUTHORITY');
    // Update founder's team member record with edge ID
    const members = this.teamMembers.get(child.certId)!;
    members[0].edgeId = edge.edgeId;

    this.notifyListeners();
    return org;
  }

  /**
   * Add a team member to an ORGANIZATION.
   * Creates a ROLE_ASSIGNMENT typed edge with role metadata.
   */
  async addTeamMember(
    orgCertId: string,
    memberCertId: string,
    role: OrganizationRole,
  ): Promise<TeamMember> {
    const org = this.organizations.get(orgCertId);
    if (!org) throw new Error(`ORGANIZATION not found: ${orgCertId}`);
    if (org.memberList.includes(memberCertId)) {
      throw new Error(`Member already in organization: ${memberCertId}`);
    }
    org.memberList.push(memberCertId);
    const edge = await this.createTypedEdge(memberCertId, orgCertId, 'ROLE_ASSIGNMENT');
    const member: TeamMember = {
      certId: memberCertId,
      role,
      edgeId: edge.edgeId,
      joinedAt: new Date().toISOString(),
    };
    const members = this.teamMembers.get(orgCertId) || [];
    members.push(member);
    this.teamMembers.set(orgCertId, members);
    this.notifyListeners();
    return member;
  }

  /** Remove a team member from an ORGANIZATION. */
  removeTeamMember(orgCertId: string, memberCertId: string): void {
    const org = this.organizations.get(orgCertId);
    if (!org) throw new Error(`ORGANIZATION not found: ${orgCertId}`);
    if (memberCertId === org.founderCertId) {
      throw new Error('Cannot remove founder from organization');
    }
    org.memberList = org.memberList.filter(m => m !== memberCertId);
    // Remove ROLE_ASSIGNMENT edges for this member + org
    for (const [edgeId, edge] of this.typedEdges) {
      if (edge.edgeType === 'ROLE_ASSIGNMENT' &&
          edge.initiator === memberCertId &&
          edge.responder === orgCertId) {
        this.typedEdges.delete(edgeId);
      }
    }
    const members = this.teamMembers.get(orgCertId) || [];
    this.teamMembers.set(orgCertId, members.filter(m => m.certId !== memberCertId));
    this.notifyListeners();
  }

  /** Get team members for an ORGANIZATION. */
  getTeamMembers(orgCertId: string): TeamMember[] {
    return this.teamMembers.get(orgCertId) || [];
  }

  /** Check if a certId has a specific role in an ORGANIZATION. */
  checkOrgCapability(
    orgCertId: string,
    memberCertId: string,
    requiredRole: OrganizationRole,
  ): boolean {
    const members = this.teamMembers.get(orgCertId) || [];
    const member = members.find(m => m.certId === memberCertId);
    if (!member) return false;
    // admin can do everything; tradie can do tradie+viewer; viewer is read-only
    const roleHierarchy: Record<OrganizationRole, number> = { admin: 3, tradie: 2, viewer: 1 };
    return roleHierarchy[member.role] >= roleHierarchy[requiredRole];
  }

  /** Get an ORGANIZATION by certId. */
  getOrganization(orgCertId: string): OrganizationState | undefined {
    return this.organizations.get(orgCertId);
  }

  /** Get all ORGANIZATIONs. */
  getAllOrganizations(): OrganizationState[] {
    return Array.from(this.organizations.values());
  }

  /** Find ORGANIZATIONs by service category. */
  findOrganizationsByCategory(category: string): OrganizationState[] {
    return Array.from(this.organizations.values()).filter(
      org => org.metadata.category?.toLowerCase() === category.toLowerCase(),
    );
  }

  /** Update ORGANIZATION metadata. */
  updateOrganizationMetadata(
    orgCertId: string,
    metadata: Partial<OrganizationMetadata>,
  ): void {
    const org = this.organizations.get(orgCertId);
    if (!org) throw new Error(`ORGANIZATION not found: ${orgCertId}`);
    org.metadata = { ...org.metadata, ...metadata };
    this.notifyListeners();
  }

  // ── Phase 2: ZONE Operations (Group Conversations) ──────────

  /**
   * Create a ZONE node for group conversations.
   * Derives a zone key from the owner's identity.
   */
  async createZone(
    ownerCertId: string,
    groupName: string,
  ): Promise<ZoneState> {
    const zoneId = `zone-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
    // Derive zone key: child derivation with ZONE_KEY domain flag (0x0b)
    const child = await this.adapter.deriveChild(ownerCertId, zoneId, 0x0b);
    const zone: ZoneState = {
      zoneId,
      groupName,
      createdBy: ownerCertId,
      memberList: [ownerCertId],
      derivedKey: child.publicKey,
      createdAt: new Date().toISOString(),
    };
    this.zones.set(zoneId, zone);

    // Create DATA_ACCESS edge: owner → ZONE
    await this.createTypedEdge(ownerCertId, zoneId, 'DATA_ACCESS');

    this.notifyListeners();
    return zone;
  }

  /** Add a member to a ZONE. Creates a DATA_ACCESS edge. */
  async addZoneMember(
    zoneId: string,
    memberCertId: string,
  ): Promise<{ edgeId: string }> {
    const zone = this.zones.get(zoneId);
    if (!zone) throw new Error(`ZONE not found: ${zoneId}`);
    if (zone.memberList.includes(memberCertId)) {
      throw new Error(`Member already in zone: ${memberCertId}`);
    }
    zone.memberList.push(memberCertId);
    const edge = await this.createTypedEdge(memberCertId, zoneId, 'DATA_ACCESS');
    this.notifyListeners();
    return { edgeId: edge.edgeId };
  }

  /** Remove a member from a ZONE. */
  removeZoneMember(zoneId: string, memberCertId: string): void {
    const zone = this.zones.get(zoneId);
    if (!zone) throw new Error(`ZONE not found: ${zoneId}`);
    zone.memberList = zone.memberList.filter(m => m !== memberCertId);
    // Remove DATA_ACCESS edges for this member + zone
    for (const [edgeId, edge] of this.typedEdges) {
      if (edge.edgeType === 'DATA_ACCESS' &&
          edge.initiator === memberCertId &&
          edge.responder === zoneId) {
        this.typedEdges.delete(edgeId);
      }
    }
    this.notifyListeners();
  }

  /** Get a ZONE by ID. */
  getZone(zoneId: string): ZoneState | undefined {
    return this.zones.get(zoneId);
  }

  /** Get all ZONEs. */
  getAllZones(): ZoneState[] {
    return Array.from(this.zones.values());
  }

  /** Subscribe for useSyncExternalStore compatibility. Returns unsubscribe function. */
  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  /** Get current state snapshot for useSyncExternalStore. */
  getSnapshot(): PlexusState {
    return this.state;
  }

  private notifyListeners(): void {
    for (const listener of this.listeners) {
      listener();
    }
  }
}

// === Singleton ===

let plexusService: PlexusService | null = null;

export function initializePlexusService(config: PlexusConfig): PlexusService {
  plexusService = new PlexusService(config);
  return plexusService;
}

export function getPlexusService(): PlexusService {
  if (!plexusService) {
    throw new Error('PlexusService not initialized. Call initializePlexusService() first.');
  }
  return plexusService;
}

```
