---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/identity-api.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.079914+00:00
---

# apps/loom-svelte/src/lib/identity-api.ts

```ts
/**
 * identity-api.ts — typed HTTP client for /api/v1/identity/*.
 *
 * Matches the JSON shape produced by
 * runtime/semantos-brain/src/identity_http.zig.
 *
 * Endpoints:
 *   GET  /api/v1/identity/hat         → active hat for the authenticated bearer
 *   GET  /api/v1/identity/hats        → all known hats (admin view)
 *   POST /api/v1/identity/hat/switch  → switch active hat { hat_id }
 *   GET  /api/v1/identity/cert        → cert snapshot for the bearer
 */

// ── Wire types ────────────────────────────────────────────────────────────────

export interface BrainHatInfo {
  id: string;                // internal row id (UUIDv4)
  hat_id: string;            // stable hat id from cert (context_tag namespace)
  hat_name: string;
  cert_id: string;
  bearer_fingerprint: string;
  brain_base_url: string;
  color_hex: string;
  logged_in_at: number;      // epoch milliseconds
  last_used_at: number;      // epoch milliseconds
  is_active: boolean;
}

export interface BrainHatList {
  hats: BrainHatInfo[];
}

export interface BrainCertSnapshot {
  cert_id: string;
  label: string;
  issued_at: number;         // epoch milliseconds
  push_platform: string;
  active: boolean;
}

/**
 * Subset of GET /api/v1/info the "me" panel surfaces for parity with the
 * PWA's oddjobz "me" sheet. Matches the keys emitted by
 * runtime/semantos-brain/src/info_http.zig (brain_pin_pubkey / brain_pin_cert_id
 * / server_version / cartridges[]).
 */
export interface BrainInfo {
  /** 66-hex compressed-SEC1 operator pin pubkey. */
  pinPubkey: string;
  /** 32-hex pin cert id. */
  pinCertId: string;
  /** e.g. "brain 0.1.0". */
  serverVersion: string;
  /** Installed cartridge ids (best-effort; may be empty). */
  cartridges: string[];
}

// ── Fetch helpers ─────────────────────────────────────────────────────────────

function identityHeaders(bearer: string): HeadersInit {
  return {
    Authorization: `Bearer ${bearer}`,
    Accept: 'application/json',
  };
}

/**
 * GET /api/v1/identity/hat — returns the active hat for this bearer.
 * Returns null on 404 (no hat linked) or any error.
 */
export async function getActiveHat(
  brainBase: string,
  bearer: string,
): Promise<BrainHatInfo | null> {
  try {
    const res = await fetch(`${brainBase}/api/v1/identity/hat`, {
      headers: identityHeaders(bearer),
    });
    if (res.status === 404) return null;
    if (!res.ok) return null;
    return await res.json() as BrainHatInfo;
  } catch {
    return null;
  }
}

/**
 * GET /api/v1/identity/hats — returns all known hats.
 * Returns null on error.
 */
export async function listHats(
  brainBase: string,
  bearer: string,
): Promise<BrainHatList | null> {
  try {
    const res = await fetch(`${brainBase}/api/v1/identity/hats`, {
      headers: identityHeaders(bearer),
    });
    if (!res.ok) return null;
    return await res.json() as BrainHatList;
  } catch {
    return null;
  }
}

/**
 * POST /api/v1/identity/hat/switch — switch the active hat by hat_id.
 * Returns true on 200/204, false on any error.
 */
export async function switchHat(
  brainBase: string,
  bearer: string,
  hatId: string,
): Promise<boolean> {
  try {
    const res = await fetch(`${brainBase}/api/v1/identity/hat/switch`, {
      method: 'POST',
      headers: {
        ...identityHeaders(bearer),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ hat_id: hatId }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

/**
 * GET /api/v1/identity/cert — returns the cert snapshot for this bearer.
 * Returns null on 404 or error.
 */
export async function getCert(
  brainBase: string,
  bearer: string,
): Promise<BrainCertSnapshot | null> {
  try {
    const res = await fetch(`${brainBase}/api/v1/identity/cert`, {
      headers: identityHeaders(bearer),
    });
    if (res.status === 404) return null;
    if (!res.ok) return null;
    return await res.json() as BrainCertSnapshot;
  } catch {
    return null;
  }
}

/**
 * GET /api/v1/info — operator/brain identity for the "me" panel (pubkey,
 * cert id, server version, cartridges). Tolerant of missing keys so a thin
 * brain build still renders. Returns null on error.
 */
export async function fetchBrainInfo(
  brainBase: string,
  bearer: string,
): Promise<BrainInfo | null> {
  try {
    const res = await fetch(`${brainBase}/api/v1/info`, {
      headers: identityHeaders(bearer),
    });
    if (!res.ok) return null;
    const d = await res.json() as {
      brain_pin_pubkey?: string;
      brain_pin_cert_id?: string;
      server_version?: string;
      cartridges?: Array<{ id?: string; name?: string }>;
    };
    return {
      pinPubkey: d.brain_pin_pubkey ?? '',
      pinCertId: d.brain_pin_cert_id ?? '',
      serverVersion: d.server_version ?? '',
      cartridges: Array.isArray(d.cartridges)
        ? d.cartridges.map((c) => c.id ?? c.name ?? '').filter((s) => s.length > 0)
        : [],
    };
  } catch {
    return null;
  }
}

```
