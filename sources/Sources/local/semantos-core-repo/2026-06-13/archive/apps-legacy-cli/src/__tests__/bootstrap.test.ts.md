---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/src/__tests__/bootstrap.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.701622+00:00
---

# archive/apps-legacy-cli/src/__tests__/bootstrap.test.ts

```ts
import { describe, expect, test, beforeEach, afterEach } from 'bun:test';
import { bootstrap } from '../bootstrap';
import { mkdtempSync, rmSync, existsSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { lockKek } from '../kek-from-passphrase';
import { makeRouteLegacy } from '@semantos/legacy-ingest';

describe('bootstrap', () => {
  let root: string;

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), 'semantos-cli-bootstrap-'));
    lockKek();
  });

  afterEach(async () => {
    rmSync(root, { recursive: true, force: true });
  });

  test('returns a verb context with all stores wired', async () => {
    const b = await bootstrap({ root, passphrase: 'test-pw' });
    expect(b.ctx.registry).toBeDefined();
    expect(b.ctx.store).toBeDefined();
    expect(b.ctx.orchestrator).toBeDefined();
    expect(b.ctx.blobStore).toBeDefined();
    expect(b.ctx.cursorStore).toBeDefined();
    expect(b.ctx.worker).toBeDefined();
    expect(b.ctx.proposalStore).toBeDefined();
    expect(b.ctx.ratification).toBeDefined();
    expect(b.ctx.clientConfigStore).toBeDefined();
    expect(b.ctx.clientConfigCache).toBeDefined();
    await b.shutdown();
  });

  test('Gmail is registered as a provider', async () => {
    const b = await bootstrap({ root, passphrase: 'test-pw' });
    const gmail = b.ctx.registry.get('gmail');
    expect(gmail).toBeDefined();
    expect(gmail!.id).toBe('gmail');
    expect(gmail!.oauthScopes).toContain('https://www.googleapis.com/auth/gmail.readonly');
    await b.shutdown();
  });

  test('Meta Business Suite is registered as a provider', async () => {
    const b = await bootstrap({ root, passphrase: 'test-pw' });
    const meta = b.ctx.registry.get('meta');
    expect(meta).toBeDefined();
    expect(meta!.id).toBe('meta');
    expect(meta!.oauthScopes).toContain('pages_messaging');
    await b.shutdown();
  });

  test('end-to-end: register-client → connect builds an authorize URL with the persisted client_id', async () => {
    const b = await bootstrap({ root, passphrase: 'test-pw' });
    const route = makeRouteLegacy(b.ctx);

    const reg = await route({
      positional: ['register-client', 'gmail'],
      flags: {
        'client-id': '0123456789-abcdefghij.apps.googleusercontent.com',
        'client-secret': 'GOCSPX-test-secret',
        'redirect-uri': 'https://oddjobtodd.info/auth/callback',
      },
    }, null) as { ok: boolean };
    expect(reg.ok).toBe(true);

    const conn = await route({ positional: ['connect', 'gmail'] }, null) as { ok: boolean; authorizeUrl: string };
    expect(conn.ok).toBe(true);
    expect(conn.authorizeUrl).toContain('client_id=0123456789-abcdefghij.apps.googleusercontent.com');
    expect(conn.authorizeUrl).toContain('redirect_uri=https%3A%2F%2Foddjobtodd.info%2Fauth%2Fcallback');

    await b.shutdown();
  });

  test('credentials persist across bootstrap restarts', async () => {
    let b = await bootstrap({ root, passphrase: 'test-pw' });
    let route = makeRouteLegacy(b.ctx);
    await route({
      positional: ['register-client', 'gmail'],
      flags: { 'client-id': 'persist-test', 'redirect-uri': 'https://x/cb' },
    }, null);
    await b.shutdown();

    // Re-bootstrap with the same root + passphrase → cache should populate
    // from the encrypted file.
    b = await bootstrap({ root, passphrase: 'test-pw' });
    route = makeRouteLegacy(b.ctx);
    const r = await route({ positional: ['clients'] }, null) as { clients: Array<{ providerId: string }> };
    expect(r.clients.length).toBe(1);
    expect(r.clients[0].providerId).toBe('gmail');
    await b.shutdown();
  });

  test('audit log is written on register-client', async () => {
    const b = await bootstrap({ root, passphrase: 'test-pw' });
    const route = makeRouteLegacy(b.ctx);
    await route({
      positional: ['register-client', 'gmail'],
      flags: { 'client-id': 'audit-test', 'redirect-uri': 'https://x/cb' },
    }, null);
    const auditPath = join(root, 'audit.log');
    expect(existsSync(auditPath)).toBe(true);
    const lines = readFileSync(auditPath, 'utf8').trim().split('\n').filter(Boolean);
    const ops = lines.map(l => JSON.parse(l).op);
    expect(ops).toContain('client.register');
    await b.shutdown();
  });

  test('OAuth pending state survives bootstrap restart (two-process flow)', async () => {
    // Regression for the bug this PR fixes — the legacy-cli is invoked
    // as one-shot bun verbs (`bun apps/legacy-cli/src/cli.ts <verb>`)
    // so each bootstrap is a fresh process with its own in-memory state.
    // Pre-fix, the pending-state Map would die between `legacy connect`
    // and `legacy resume`. Post-fix, the disk-backed PendingStateStore
    // (wired in bootstrap) carries the state across.

    // Process A: register-client + connect → prints state nonce, exits.
    let b = await bootstrap({ root, passphrase: 'test-pw' });
    let route = makeRouteLegacy(b.ctx);
    await route({
      positional: ['register-client', 'gmail'],
      flags: {
        'client-id': 'pending-state-test',
        'redirect-uri': 'http://localhost:3001/auth/callback',
      },
    }, null);
    const conn = await route({ positional: ['connect', 'gmail'] }, null) as {
      ok: boolean;
      stateNonce: string;
    };
    expect(conn.ok).toBe(true);
    expect(typeof conn.stateNonce).toBe('string');

    // Confirm the encrypted pending-state file lives on disk.
    const pendingDir = join(root, 'legacy-pending');
    expect(existsSync(pendingDir)).toBe(true);
    expect(existsSync(join(pendingDir, `${conn.stateNonce}.json`))).toBe(true);
    await b.shutdown();

    // Process B: fresh bootstrap, same root, same passphrase. Resume
    // with the captured state nonce. The token-exchange will fail at
    // the network layer (no fetch stub for the real Google endpoint),
    // but the failure is the *exchange* failing — not the pending-state
    // lookup, which is the bug we're regression-protecting against.
    b = await bootstrap({ root, passphrase: 'test-pw' });
    route = makeRouteLegacy(b.ctx);
    const resume = await route({
      positional: ['resume', conn.stateNonce, 'fake-auth-code'],
    }, null) as { error?: string };
    // The verb returned an error (because the fake code can't be
    // exchanged) — but it's NOT the "state nonce unknown or expired"
    // error that the in-memory-Map bug produced.
    expect(resume.error).toBeDefined();
    expect(resume.error).not.toMatch(/unknown or expired/);
    expect(resume.error).not.toMatch(/bad_state/);
    // The pending file was consumed on the get-then-delete by the
    // (otherwise-failed) exchange path.
    expect(existsSync(join(pendingDir, `${conn.stateNonce}.json`))).toBe(false);
    await b.shutdown();
  });

  test('wrong passphrase fails closed when reading existing credentials', async () => {
    let b = await bootstrap({ root, passphrase: 'pw-A' });
    let route = makeRouteLegacy(b.ctx);
    await route({
      positional: ['register-client', 'gmail'],
      flags: { 'client-id': 'x', 'redirect-uri': 'https://x/cb' },
    }, null);
    await b.shutdown();

    // Different passphrase → bootstrap fails when it tries to decrypt
    // the cached client config during reload().
    await expect(bootstrap({ root, passphrase: 'pw-B' })).resolves.toBeDefined();
    // The reload silently skipped the corrupt entry (per `list()` behaviour
    // in client-config-store) so cache is empty. Subsequent connect fails.
    const b2 = await bootstrap({ root, passphrase: 'pw-B' });
    const r2 = await makeRouteLegacy(b2.ctx)({
      positional: ['connect', 'gmail'],
    }, null) as { error?: string };
    expect(r2.error).toMatch(/no client config/);
    await b2.shutdown();
  });
});

```
