---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/peer-invite.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.649087+00:00
---

# cartridges/wallet-headers/brain/src/peer-invite.ts

```ts
// peer-invite.ts — Phase C: off-band invite URL generation/parsing + ECDH edge creation

// Off-band invite — encode your identity so a peer can initiate ECDH
export interface PeerInvite {
  certId: string;    // inviter's cert_id (32-byte hex)
  publicKey: string; // inviter's 33-byte compressed secp256k1 pubkey (hex)
  nonce: string;     // 32-byte random hex (anti-replay)
  timestamp: number; // unix ms
}

const DEFAULT_BASE_URL = 'https://wallet.semantos.me/connect';
const INVITE_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours

function bytesToHex(b: Uint8Array): string {
  return Array.from(b).map(x => x.toString(16).padStart(2, '0')).join('');
}

// base64url encode: standard base64 with + → -, / → _, = stripped
function toBase64url(str: string): string {
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// base64url decode
function fromBase64url(s: string): string {
  // Restore standard base64 padding and characters
  const padded = s.replace(/-/g, '+').replace(/_/g, '/');
  const pad = (4 - padded.length % 4) % 4;
  return atob(padded + '='.repeat(pad));
}

/**
 * Generate a new invite token.
 */
export function generateInvite(myCertId: string, myPk: Uint8Array): PeerInvite {
  const nonce = bytesToHex(crypto.getRandomValues(new Uint8Array(32)));
  return {
    certId: myCertId,
    publicKey: bytesToHex(myPk),
    nonce,
    timestamp: Date.now(),
  };
}

/**
 * Encode to a URL-safe token string (base64url of JSON).
 */
export function encodeInviteToken(invite: PeerInvite): string {
  const json = JSON.stringify(invite);
  return toBase64url(json);
}

/**
 * Decode — returns null if malformed or expired (>24h old).
 */
export function decodeInviteToken(token: string): PeerInvite | null {
  if (!token) return null;
  let json: string;
  try {
    json = fromBase64url(token);
  } catch {
    return null;
  }

  let invite: PeerInvite;
  try {
    invite = JSON.parse(json) as PeerInvite;
  } catch {
    return null;
  }

  // Validate required fields
  if (
    typeof invite.certId !== 'string' ||
    typeof invite.publicKey !== 'string' ||
    typeof invite.nonce !== 'string' ||
    typeof invite.timestamp !== 'number'
  ) {
    return null;
  }

  // Check expiry
  if (Date.now() - invite.timestamp > INVITE_TTL_MS) {
    return null;
  }

  return invite;
}

/**
 * Build a full invite URL for sharing.
 * e.g. "https://wallet.semantos.me/connect?invite=<token>"
 */
export function buildInviteUrl(invite: PeerInvite, baseUrl?: string): string {
  const base = baseUrl ?? DEFAULT_BASE_URL;
  const token = encodeInviteToken(invite);
  const sep = base.includes('?') ? '&' : '?';
  return `${base}${sep}invite=${token}`;
}

/**
 * Parse an invite URL, returns the decoded PeerInvite or null.
 */
export function parseInviteUrl(url: string): PeerInvite | null {
  try {
    const parsed = new URL(url);
    const token = parsed.searchParams.get('invite');
    if (!token) return null;
    return decodeInviteToken(token);
  } catch {
    return null;
  }
}

```
