---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/contacts-api.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.083975+00:00
---

# apps/loom-svelte/src/lib/contacts-api.ts

```ts
/**
 * contacts-api.ts — typed HTTP client for /api/v1/contacts.
 *
 * Matches the JSON shape produced by runtime/semantos-brain/src/contacts_http.zig.
 * All timestamps are Unix seconds (i64 in Zig → number in TS).
 */

// ── Wire types (mirror Zig Contact + EdgeRecord structs) ──────────────────────

export interface BrainContact {
  certId: string;
  publicKey: string;
  displayName: string;
  email: string | null;
  source: string;
  addedAt: number;   // Unix seconds
  updatedAt: number; // Unix seconds
}

export interface BrainEdgeRecord {
  edgeId: string;
  certId: string;
  edgeType: string;
  signingKeyIndex: number;
  recoveryPolicy: string;
  revokedAt: number | null; // Unix seconds, null if active
  createdAt: number;        // Unix seconds
}

export interface BrainContactDetail extends BrainContact {
  edges: BrainEdgeRecord[];
}

// ── Fetch helpers ─────────────────────────────────────────────────────────────

function contactsHeaders(bearer: string): HeadersInit {
  return {
    Authorization: `Bearer ${bearer}`,
    Accept: 'application/json',
  };
}

/**
 * GET /api/v1/contacts — list all contacts.
 * Returns an empty array on 404 (no contacts yet) or network error.
 */
export async function listContacts(
  brainBase: string,
  bearer: string,
): Promise<BrainContact[]> {
  try {
    const res = await fetch(`${brainBase}/api/v1/contacts`, {
      headers: contactsHeaders(bearer),
    });
    if (!res.ok) return [];
    const data = await res.json() as { contacts?: BrainContact[] };
    return data.contacts ?? [];
  } catch {
    return [];
  }
}

/**
 * GET /api/v1/contacts/{certId} — get one contact with its edges.
 * Returns null if not found.
 */
export async function getContactDetail(
  brainBase: string,
  bearer: string,
  certId: string,
): Promise<BrainContactDetail | null> {
  try {
    const res = await fetch(`${brainBase}/api/v1/contacts/${encodeURIComponent(certId)}`, {
      headers: contactsHeaders(bearer),
    });
    if (res.status === 404) return null;
    if (!res.ok) return null;
    return await res.json() as BrainContactDetail;
  } catch {
    return null;
  }
}

/**
 * POST /api/v1/contacts — add a contact by certId.
 * Returns the created BrainContact, or null + errCode on failure.
 */
export async function addContact(
  brainBase: string,
  bearer: string,
  body: { certId: string; publicKey: string; displayName: string; email?: string },
): Promise<{ contact: BrainContact | null; errCode?: string }> {
  try {
    const res = await fetch(`${brainBase}/api/v1/contacts`, {
      method: 'POST',
      headers: {
        ...contactsHeaders(bearer),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      let errCode: string | undefined;
      try {
        const j = await res.json() as { error?: { code?: string } };
        errCode = j?.error?.code;
      } catch { /* ignore */ }
      return { contact: null, errCode };
    }
    return { contact: await res.json() as BrainContact };
  } catch {
    return { contact: null, errCode: 'network_error' };
  }
}

// ── Edge management ───────────────────────────────────────────────────────────

export type RecoveryPolicy = 'BACKUP_ON_CREATE' | 'BACKUP_ON_CONFIRM' | 'NONE';
export type EdgeType =
  | 'MESSAGING'
  | 'DATA_ACCESS'
  | 'ROLE_ASSIGNMENT'
  | 'AUTHORITY'
  | 'TRANSFER'
  | 'ATTESTATION'
  | 'CUSTOM';

/**
 * POST /api/v1/contacts/{certId}/edges — add an edge to a contact.
 * Returns the created BrainEdgeRecord, or null + errCode on failure.
 */
export async function addEdge(
  brainBase: string,
  bearer: string,
  certId: string,
  body: {
    edgeId: string;
    edgeType: EdgeType;
    signingKeyIndex: number;
    recoveryPolicy: RecoveryPolicy;
  },
): Promise<{ edge: BrainEdgeRecord | null; errCode?: string }> {
  try {
    const res = await fetch(
      `${brainBase}/api/v1/contacts/${encodeURIComponent(certId)}/edges`,
      {
        method: 'POST',
        headers: {
          ...contactsHeaders(bearer),
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      },
    );
    if (!res.ok) {
      let errCode: string | undefined;
      try {
        const j = await res.json() as { error?: { code?: string } };
        errCode = j?.error?.code;
      } catch { /* ignore */ }
      return { edge: null, errCode };
    }
    return { edge: await res.json() as BrainEdgeRecord };
  } catch {
    return { edge: null, errCode: 'network_error' };
  }
}

/**
 * DELETE /api/v1/contacts/{certId}/edges/{edgeId} — revoke an edge.
 * Returns true on 204; false + errCode on not_found (404) / already_revoked (409).
 */
export async function revokeEdge(
  brainBase: string,
  bearer: string,
  certId: string,
  edgeId: string,
): Promise<{ ok: boolean; errCode?: string }> {
  try {
    const res = await fetch(
      `${brainBase}/api/v1/contacts/${encodeURIComponent(certId)}/edges/${encodeURIComponent(edgeId)}`,
      {
        method: 'DELETE',
        headers: contactsHeaders(bearer),
      },
    );
    if (res.status === 204) return { ok: true };
    let errCode: string | undefined;
    try {
      const j = await res.json() as { error?: { code?: string } };
      errCode = j?.error?.code;
    } catch { /* ignore */ }
    return { ok: false, errCode };
  } catch {
    return { ok: false, errCode: 'network_error' };
  }
}

```
