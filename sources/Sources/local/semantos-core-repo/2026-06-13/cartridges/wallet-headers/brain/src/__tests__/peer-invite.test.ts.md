---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/__tests__/peer-invite.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.675798+00:00
---

# cartridges/wallet-headers/brain/src/__tests__/peer-invite.test.ts

```ts
import { describe, it, expect, beforeEach } from 'bun:test';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 } from '@noble/hashes/sha2';

// Wire sync HMAC backend for secp (required before any secp ops in tests)
secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(sha256, key, secp.etc.concatBytes(...msgs));

import {
  generateInvite,
  encodeInviteToken,
  decodeInviteToken,
  buildInviteUrl,
  parseInviteUrl,
} from '../peer-invite';

import {
  loadEdgeEnvelopes,
  saveEdgeEnvelope,
  getEdgeEnvelope,
  findEdgeTo,
  type LocalEdgeEnvelope,
} from '../local-edge-store';

import {
  deriveEdgeSharedSecret,
  buildEdgeBackupRecipe,
  acceptInvite,
} from '../ecdh-edge';

// ── In-memory localStorage mock ───────────────────────────────────────────────

const store: Record<string, string> = {};
const mockLocalStorage = {
  getItem: (k: string) => store[k] ?? null,
  setItem: (k: string, v: string) => { store[k] = v; },
};

// Inject before tests run
(globalThis as any).localStorage = mockLocalStorage;

// ── Test key pairs ────────────────────────────────────────────────────────────

function randomSk(): Uint8Array {
  // Generate a valid secp256k1 private key
  let sk: Uint8Array;
  do {
    sk = crypto.getRandomValues(new Uint8Array(32));
  } while (!secp.utils.isValidPrivateKey(sk));
  return sk;
}

function hexFromBytes(b: Uint8Array): string {
  return Array.from(b).map(x => x.toString(16).padStart(2, '0')).join('');
}

// ── generateInvite ─────────────────────────────────────────────────────────

describe('generateInvite', () => {
  it('returns object with correct fields', () => {
    const sk = randomSk();
    const pk = secp.getPublicKey(sk, true);
    const certId = hexFromBytes(crypto.getRandomValues(new Uint8Array(32)));

    const invite = generateInvite(certId, pk);

    expect(invite.certId).toBe(certId);
    expect(invite.publicKey).toBe(hexFromBytes(pk));
    expect(typeof invite.nonce).toBe('string');
    expect(invite.nonce.length).toBe(64); // 32-byte hex
    expect(typeof invite.timestamp).toBe('number');
    expect(invite.timestamp).toBeGreaterThan(0);
  });

  it('generates unique nonces on each call', () => {
    const sk = randomSk();
    const pk = secp.getPublicKey(sk, true);
    const certId = hexFromBytes(crypto.getRandomValues(new Uint8Array(32)));

    const a = generateInvite(certId, pk);
    const b = generateInvite(certId, pk);
    expect(a.nonce).not.toBe(b.nonce);
  });
});

// ── encodeInviteToken / decodeInviteToken ─────────────────────────────────────

describe('encodeInviteToken / decodeInviteToken', () => {
  it('round-trips a valid invite', () => {
    const sk = randomSk();
    const pk = secp.getPublicKey(sk, true);
    const certId = hexFromBytes(crypto.getRandomValues(new Uint8Array(32)));
    const invite = generateInvite(certId, pk);

    const token = encodeInviteToken(invite);
    expect(typeof token).toBe('string');
    expect(token.length).toBeGreaterThan(0);

    const decoded = decodeInviteToken(token);
    expect(decoded).not.toBeNull();
    expect(decoded!.certId).toBe(invite.certId);
    expect(decoded!.publicKey).toBe(invite.publicKey);
    expect(decoded!.nonce).toBe(invite.nonce);
    expect(decoded!.timestamp).toBe(invite.timestamp);
  });

  it('returns null for malformed token', () => {
    expect(decodeInviteToken('not-valid-base64url!!!')).toBeNull();
    expect(decodeInviteToken('')).toBeNull();
    expect(decodeInviteToken('YWJj')).toBeNull(); // valid b64 but not valid JSON invite
  });

  it('returns null for expired invite (>24h old)', () => {
    const sk = randomSk();
    const pk = secp.getPublicKey(sk, true);
    const certId = hexFromBytes(crypto.getRandomValues(new Uint8Array(32)));

    const oldInvite = generateInvite(certId, pk);
    // Backdate by 25 hours
    oldInvite.timestamp = Date.now() - 25 * 60 * 60 * 1000;

    const token = encodeInviteToken(oldInvite);
    expect(decodeInviteToken(token)).toBeNull();
  });

  it('accepts invite that is exactly 23h old (not expired)', () => {
    const sk = randomSk();
    const pk = secp.getPublicKey(sk, true);
    const certId = hexFromBytes(crypto.getRandomValues(new Uint8Array(32)));

    const invite = generateInvite(certId, pk);
    invite.timestamp = Date.now() - 23 * 60 * 60 * 1000;

    const token = encodeInviteToken(invite);
    expect(decodeInviteToken(token)).not.toBeNull();
  });
});

// ── buildInviteUrl / parseInviteUrl ──────────────────────────────────────────

describe('buildInviteUrl', () => {
  it('contains "invite=" parameter', () => {
    const sk = randomSk();
    const pk = secp.getPublicKey(sk, true);
    const certId = hexFromBytes(crypto.getRandomValues(new Uint8Array(32)));
    const invite = generateInvite(certId, pk);

    const url = buildInviteUrl(invite);
    expect(url).toContain('invite=');
  });

  it('uses default base URL when none provided', () => {
    const sk = randomSk();
    const pk = secp.getPublicKey(sk, true);
    const certId = hexFromBytes(crypto.getRandomValues(new Uint8Array(32)));
    const invite = generateInvite(certId, pk);

    const url = buildInviteUrl(invite);
    expect(url).toContain('wallet.semantos.me');
  });

  it('uses provided base URL', () => {
    const sk = randomSk();
    const pk = secp.getPublicKey(sk, true);
    const certId = hexFromBytes(crypto.getRandomValues(new Uint8Array(32)));
    const invite = generateInvite(certId, pk);

    const url = buildInviteUrl(invite, 'https://example.com/connect');
    expect(url).toContain('example.com');
    expect(url).toContain('invite=');
  });
});

describe('parseInviteUrl', () => {
  it('recovers PeerInvite from a built URL', () => {
    const sk = randomSk();
    const pk = secp.getPublicKey(sk, true);
    const certId = hexFromBytes(crypto.getRandomValues(new Uint8Array(32)));
    const invite = generateInvite(certId, pk);

    const url = buildInviteUrl(invite);
    const parsed = parseInviteUrl(url);

    expect(parsed).not.toBeNull();
    expect(parsed!.certId).toBe(invite.certId);
    expect(parsed!.publicKey).toBe(invite.publicKey);
    expect(parsed!.nonce).toBe(invite.nonce);
    expect(parsed!.timestamp).toBe(invite.timestamp);
  });

  it('returns null for URL with no invite param', () => {
    expect(parseInviteUrl('https://wallet.semantos.me/connect')).toBeNull();
  });

  it('returns null for URL with expired invite', () => {
    const sk = randomSk();
    const pk = secp.getPublicKey(sk, true);
    const certId = hexFromBytes(crypto.getRandomValues(new Uint8Array(32)));
    const invite = generateInvite(certId, pk);
    invite.timestamp = Date.now() - 25 * 60 * 60 * 1000;

    const url = buildInviteUrl(invite);
    expect(parseInviteUrl(url)).toBeNull();
  });
});

// ── deriveEdgeSharedSecret ────────────────────────────────────────────────────

describe('deriveEdgeSharedSecret', () => {
  it('returns 32 bytes for valid inputs', () => {
    const mySk = randomSk();
    const theirSk = randomSk();
    const theirPk = secp.getPublicKey(theirSk, true);

    const secret = deriveEdgeSharedSecret(mySk, theirPk, 1);
    expect(secret).not.toBeNull();
    expect(secret!.length).toBe(32);
  });

  it('is deterministic (same inputs → same output)', () => {
    const mySk = randomSk();
    const theirSk = randomSk();
    const theirPk = secp.getPublicKey(theirSk, true);

    const a = deriveEdgeSharedSecret(mySk, theirPk, 1);
    const b = deriveEdgeSharedSecret(mySk, theirPk, 1);

    expect(a).not.toBeNull();
    expect(b).not.toBeNull();
    expect(hexFromBytes(a!)).toBe(hexFromBytes(b!));
  });

  it('produces different results for different indices', () => {
    const mySk = randomSk();
    const theirSk = randomSk();
    const theirPk = secp.getPublicKey(theirSk, true);

    const a = deriveEdgeSharedSecret(mySk, theirPk, 1);
    const b = deriveEdgeSharedSecret(mySk, theirPk, 2);

    expect(a).not.toBeNull();
    expect(b).not.toBeNull();
    expect(hexFromBytes(a!)).not.toBe(hexFromBytes(b!));
  });
});

// ── buildEdgeBackupRecipe ─────────────────────────────────────────────────────

describe('buildEdgeBackupRecipe', () => {
  it('returns non-null hex string', () => {
    const mySk = randomSk();
    const theirSk = randomSk();
    const theirPk = secp.getPublicKey(theirSk, true);
    const edgeId = hexFromBytes(crypto.getRandomValues(new Uint8Array(32)));

    const recipe = buildEdgeBackupRecipe(mySk, theirPk, 1, edgeId);
    expect(recipe).not.toBeNull();
    expect(typeof recipe).toBe('string');
    expect(recipe!.length).toBe(64); // 32-byte HMAC → 64 hex chars
  });

  it('is deterministic', () => {
    const mySk = randomSk();
    const theirSk = randomSk();
    const theirPk = secp.getPublicKey(theirSk, true);
    const edgeId = hexFromBytes(crypto.getRandomValues(new Uint8Array(32)));

    const a = buildEdgeBackupRecipe(mySk, theirPk, 1, edgeId);
    const b = buildEdgeBackupRecipe(mySk, theirPk, 1, edgeId);

    expect(a).toBe(b);
  });
});

// ── loadEdgeEnvelopes / saveEdgeEnvelope / findEdgeTo ────────────────────────

describe('localStorage edge store', () => {
  beforeEach(() => {
    // Clear the in-memory store between tests
    for (const key of Object.keys(store)) {
      delete store[key];
    }
  });

  it('loadEdgeEnvelopes returns empty array when nothing stored', () => {
    expect(loadEdgeEnvelopes()).toEqual([]);
  });

  it('saveEdgeEnvelope / loadEdgeEnvelopes round-trip', () => {
    const env: LocalEdgeEnvelope = {
      edgeId: 'edge-001',
      myCertId: 'my-cert',
      theirCertId: 'their-cert',
      theirPublicKey: '02' + 'ab'.repeat(32),
      signingKeyIndex: 1,
      edgeType: 'MESSAGING',
      backupRecipe: 'de'.repeat(32),
      createdAt: Date.now(),
    };

    saveEdgeEnvelope(env);
    const loaded = loadEdgeEnvelopes();
    expect(loaded.length).toBe(1);
    expect(loaded[0]!.edgeId).toBe('edge-001');
    expect(loaded[0]!.myCertId).toBe('my-cert');
    expect(loaded[0]!.theirCertId).toBe('their-cert');
  });

  it('getEdgeEnvelope returns correct envelope by edgeId', () => {
    const env: LocalEdgeEnvelope = {
      edgeId: 'edge-abc',
      myCertId: 'my-cert',
      theirCertId: 'their-cert',
      theirPublicKey: '02' + 'ab'.repeat(32),
      signingKeyIndex: 1,
      edgeType: 'MESSAGING',
      backupRecipe: 'de'.repeat(32),
      createdAt: Date.now(),
    };

    saveEdgeEnvelope(env);
    const found = getEdgeEnvelope('edge-abc');
    expect(found).not.toBeNull();
    expect(found!.edgeId).toBe('edge-abc');
    expect(getEdgeEnvelope('nonexistent')).toBeNull();
  });

  it('findEdgeTo returns most recent envelope for theirCertId', () => {
    const now = Date.now();
    const older: LocalEdgeEnvelope = {
      edgeId: 'edge-old',
      myCertId: 'my-cert',
      theirCertId: 'peer-cert',
      theirPublicKey: '02' + 'ab'.repeat(32),
      signingKeyIndex: 1,
      edgeType: 'MESSAGING',
      backupRecipe: 'de'.repeat(32),
      createdAt: now - 1000,
    };
    const newer: LocalEdgeEnvelope = {
      edgeId: 'edge-new',
      myCertId: 'my-cert',
      theirCertId: 'peer-cert',
      theirPublicKey: '02' + 'cd'.repeat(32),
      signingKeyIndex: 2,
      edgeType: 'MESSAGING',
      backupRecipe: 'ef'.repeat(32),
      createdAt: now,
    };

    saveEdgeEnvelope(older);
    saveEdgeEnvelope(newer);

    const found = findEdgeTo('peer-cert');
    expect(found).not.toBeNull();
    expect(found!.edgeId).toBe('edge-new');
  });

  it('findEdgeTo returns null for unknown certId', () => {
    expect(findEdgeTo('nobody')).toBeNull();
  });
});

// ── acceptInvite ──────────────────────────────────────────────────────────────

describe('acceptInvite', () => {
  beforeEach(() => {
    for (const key of Object.keys(store)) {
      delete store[key];
    }
  });

  it('creates LocalEdgeEnvelope with correct fields', () => {
    const inviterSk = randomSk();
    const inviterPk = secp.getPublicKey(inviterSk, true);
    const inviterCertId = hexFromBytes(crypto.getRandomValues(new Uint8Array(32)));

    const invite = generateInvite(inviterCertId, inviterPk);

    const mySk = randomSk();
    const myPk = secp.getPublicKey(mySk, true);
    const myCertId = hexFromBytes(crypto.getRandomValues(new Uint8Array(32)));

    const result = acceptInvite(
      invite,
      { certId: myCertId, sk: mySk, pk: myPk },
      1,
    );

    expect(result).not.toBeNull();
    expect(result!.myCertId).toBe(myCertId);
    expect(result!.theirCertId).toBe(inviterCertId);
    expect(result!.theirPublicKey).toBe(invite.publicKey);
    expect(result!.signingKeyIndex).toBe(1);
    expect(result!.edgeType).toBe('MESSAGING');
    expect(typeof result!.edgeId).toBe('string');
    expect(result!.edgeId.length).toBeGreaterThan(0);
    expect(typeof result!.backupRecipe).toBe('string');
    expect(result!.backupRecipe.length).toBe(64);
    expect(typeof result!.createdAt).toBe('number');
  });

  it('stores the envelope in localStorage', () => {
    const inviterSk = randomSk();
    const inviterPk = secp.getPublicKey(inviterSk, true);
    const inviterCertId = hexFromBytes(crypto.getRandomValues(new Uint8Array(32)));
    const invite = generateInvite(inviterCertId, inviterPk);

    const mySk = randomSk();
    const myPk = secp.getPublicKey(mySk, true);
    const myCertId = hexFromBytes(crypto.getRandomValues(new Uint8Array(32)));

    const result = acceptInvite(
      invite,
      { certId: myCertId, sk: mySk, pk: myPk },
      1,
    );

    expect(result).not.toBeNull();
    const stored = findEdgeTo(inviterCertId);
    expect(stored).not.toBeNull();
    expect(stored!.edgeId).toBe(result!.edgeId);
  });
});

```
