---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/OJT/OJT-PHASE-3-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.790027+00:00
---

# OJT Phase 3 Execution Prompt — HTTP BundleTransport

> Paste this prompt into a fresh session to execute Phase 3 of the OJT
> migration. Repo: `semantos-core` (not oddjobtodd). Branch:
> `feat/http-bundle-transport`. Can run in parallel with P1 / P2.

## Context

You are working in the `semantos-core` repo at
`/sessions/nifty-bold-sagan/mnt/semantos-core`.

Slice 5d shipped `BundleTransport` as an interface with one concrete
implementation: `InMemoryTransport` + `InMemoryTransportNetwork`. Every
Slice 5 gate test (signed, trusted, addressed, policy-gated) runs over
this in-process wire.

Phase 3 adds an `HttpBundleTransport` — the first real transport. It
accepts `SignedBundle<T>` payloads over HTTP POST and dispatches outbound
bundles to peer HTTP endpoints from a `peerRegistry`. Every Slice 5 gate
must still pass when the wire is swapped from `InMemoryTransport` to
`HttpBundleTransport` between two localhost ports.

This phase is on semantos-core, not OJT, because `BundleTransport` lives
in `runtime/session-protocol/` and is shared across all semantos tenants.

**Why this matters**: P4 (OJT HTTP edge) imports this transport to
receive and dispatch bundles between OJT-node and REA-node on separate
VPS processes. P7's end-to-end gate runs through this transport.

---

## CRITICAL: READ THESE FILES FIRST

**Semantos side (the interface to implement):**
- `runtime/session-protocol/src/bundle-transport.ts` — the
  `BundleTransport` interface. Methods: `send(bundle, recipientCertId)`,
  `onReceive(handler)`, `register(certId)`, `close()`. Error codes:
  `self_send`, `recipient_not_registered`, plus transport-specific.
- `runtime/session-protocol/src/in-memory-transport.ts` —
  `InMemoryTransport` + `InMemoryTransportNetwork`. Read this end to end
  — your HTTP implementation must behave identically from the caller's
  perspective.
- `runtime/session-protocol/src/bundle-envelope.ts` — `SignedBundle<T>`
  shape (JSON-serializable).
- `runtime/session-protocol/src/known-cert-store.ts` — not used directly
  by transport but informs how certIds flow through.
- `runtime/session-protocol/src/index.ts` — how existing primitives are
  exported. Follow the same pattern.

**Gate tests you must still pass:**
- `tests/gates/intent-pipeline-federation-transport.test.ts` (Slice 5d,
  the capstone). The 7 gates (G1–G7) must pass unchanged when the test
  harness is run with `HttpBundleTransport` instead of
  `InMemoryTransport`.

**HTTP conventions in semantos:**
- `apps/loom-react/server/index.ts` — Bun.serve patterns in the repo
  (port config, route shape, shutdown handling).
- `runtime/node/src/api/server.ts` — the admin API's mTLS Bun.serve.
  Note: HTTP transport is **not** mTLS — it does its own cert
  verification at the envelope layer (via `verifyBundleWithTrust`), so
  plain HTTP over a tunnel/VPN or plain HTTPS with a public cert is
  correct.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. INTERFACE PARITY WITH `InMemoryTransport`

Every method signature, every error code, every behaviour must match.
If `InMemoryTransport.send()` returns `{ ok: false, code: 'self_send' }`
when asked to send to its own certId, `HttpBundleTransport.send()` must
do the same — even though the underlying mechanism differs. The Slice 5d
gate test drives both transports through the same assertions.

### 2. THE WIRE IS PLAIN JSON

Payloads are `JSON.stringify(signedBundle)`. Nothing fancy. No protobuf,
no MessagePack. The wire format is the same format the existing gates
use; this transport just moves bytes over HTTP.

### 3. NO TRUST LOGIC IN THE TRANSPORT

The transport does NOT call `verifyBundleWithTrust`, does NOT check
signatures, does NOT consult any cert store. All of that is the
receiver's job (above the transport layer). The transport's only
concerns are:
- Route the JSON-serialized bundle to the registered peer URL for the
  recipient certId.
- Call the `onReceive` handler when a POST arrives.
- Enforce `self_send` (don't send to own certId) and
  `recipient_not_registered` (unknown certId in the registry).

Adding trust checks here breaks the layer boundary and the existing
gate tests.

### 4. PEER REGISTRY IS STATIC AT CONSTRUCTION

`createHttpTransport({ peerRegistry })` takes a `Map<certId, url>` at
construction time. There is no dynamic peer discovery in this phase.
Adding a peer requires restarting the transport with a new registry.
(Dynamic peer discovery is a future concern — overlay gossip, BCA
resolution, etc.)

### 5. PORT CONFLICTS MUST BE DETECTED AT BOOT

If the configured `listenPort` is in use, `createHttpTransport` must
throw a clear error synchronously, not silently fail. Bun.serve throws
on port conflict; surface that error with context.

### 6. GRACEFUL SHUTDOWN

`transport.close()` must:
- Stop accepting new inbound connections.
- Wait for in-flight inbound handlers to complete (with a 5s timeout).
- Complete all pending outbound sends (or reject them with `closed`).
- Return only when the server is fully stopped.

The Slice 5d harness spins up and tears down transports in `beforeAll`
/ `afterAll`; your implementation must not leak ports between tests.

### 7. NO GLOBAL STATE

No `let globalTransport = ...` at module scope. Multiple transports must
be able to coexist in the same process (for the gate test that stands
up OJT + REA-1 + REA-2 on three different ports).

---

## PART 0: GIT HYGIENE

```bash
cd /sessions/nifty-bold-sagan/mnt/semantos-core
git status -u
git log --oneline -5
git checkout main && git pull
git checkout -b feat/http-bundle-transport
```

Verify Slice 5d is on main (or on your working branch if still in review):

```bash
ls runtime/session-protocol/src/bundle-transport.ts
ls runtime/session-protocol/src/in-memory-transport.ts
grep -n "BundleTransport" runtime/session-protocol/src/index.ts
```

---

## Step 1: `HttpBundleTransportOptions` type (D3.1)

File: `runtime/session-protocol/src/http-transport.ts` (new)

```ts
import type { BundleTransport, TransportResult, TransportErrorCode } from './bundle-transport';
import type { SignedBundle } from './bundle-envelope';

export interface HttpBundleTransportOptions {
  /** certId of the transport's owner — used for self_send detection */
  ownCertId: string;

  /** Port to bind the HTTP listener on. */
  listenPort: number;

  /** Optional hostname to bind to (default 0.0.0.0) */
  listenHost?: string;

  /** Map of peer certId → base URL (e.g., "http://10.0.0.5:8080"). */
  peerRegistry: Map<string, string>;

  /** Optional HTTP request timeout for outbound sends (ms). Default 10000. */
  requestTimeoutMs?: number;

  /** Path prefix for federation endpoints. Default "/federation". */
  pathPrefix?: string;
}
```

Commit: `feat(ojt-p3/D3.1): HttpBundleTransportOptions type`

---

## Step 2: Outbound `send()` via fetch (D3.2)

```ts
async send<T>(
  bundle: SignedBundle<T>,
  recipientCertId: string,
): Promise<TransportResult> {
  if (recipientCertId === this.opts.ownCertId) {
    return { ok: false, code: 'self_send' };
  }
  const baseUrl = this.opts.peerRegistry.get(recipientCertId);
  if (!baseUrl) {
    return { ok: false, code: 'recipient_not_registered' };
  }

  const url = `${baseUrl}${this.opts.pathPrefix ?? '/federation'}/bundle`;
  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    this.opts.requestTimeoutMs ?? 10000,
  );

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-semantos-recipient-cert': recipientCertId,
      },
      body: JSON.stringify(bundle),
      signal: controller.signal,
    });
    if (!res.ok) {
      return { ok: false, code: 'transport_error' as TransportErrorCode, detail: `http ${res.status}` };
    }
    return { ok: true };
  } catch (e) {
    return { ok: false, code: 'transport_error', detail: String(e) };
  } finally {
    clearTimeout(timeout);
  }
}
```

Note: `transport_error` may need to be added to `TransportErrorCode`
in `bundle-transport.ts`. If it already exists, reuse it. If not, add
it as a union member with a short comment.

Commit: `feat(ojt-p3/D3.2): outbound send() via fetch with timeout`

---

## Step 3: Inbound listener via Bun.serve (D3.3)

```ts
private startListener() {
  this.server = Bun.serve({
    port: this.opts.listenPort,
    hostname: this.opts.listenHost ?? '0.0.0.0',
    fetch: async (req) => {
      const url = new URL(req.url);
      const expectedPath = `${this.opts.pathPrefix ?? '/federation'}/bundle`;
      if (url.pathname !== expectedPath || req.method !== 'POST') {
        return new Response('not found', { status: 404 });
      }
      try {
        const bundle = await req.json() as SignedBundle<unknown>;
        if (!this.handler) {
          return new Response('no handler', { status: 503 });
        }
        await this.handler(bundle);
        return new Response('ok', { status: 200 });
      } catch (e) {
        return new Response(`bad request: ${String(e)}`, { status: 400 });
      }
    },
  });
}
```

The listener must bind synchronously during `createHttpTransport()` and
throw on port conflict.

Commit: `feat(ojt-p3/D3.3): inbound Bun.serve listener`

---

## Step 4: `register()` + `onReceive()` + `close()` (D3.4)

```ts
register(certId: string): void {
  // No-op on HTTP transport — peers are configured via peerRegistry at
  // construction. Included for interface parity with InMemoryTransport.
}

onReceive(handler: (bundle: SignedBundle<unknown>) => Promise<void>): void {
  this.handler = handler;
}

async close(): Promise<void> {
  if (this.server) {
    await this.server.stop(true);       // graceful
    this.server = undefined;
  }
}
```

Commit: `feat(ojt-p3/D3.4): register + onReceive + graceful close`

---

## Step 5: `createHttpTransport` factory + export (D3.5)

```ts
export function createHttpTransport(
  opts: HttpBundleTransportOptions,
): BundleTransport {
  return new HttpBundleTransport(opts);
}
```

Wire into `runtime/session-protocol/src/index.ts`:

```ts
export {
  createHttpTransport,
  type HttpBundleTransportOptions,
} from './http-transport';
```

Commit: `feat(ojt-p3/D3.5): factory + index export`

---

## Step 6: Unit gates for HTTP-specific behaviour (D3.6)

File: `tests/gates/http-bundle-transport.test.ts`

```ts
describe('HttpBundleTransport', () => {
  test('G1 round-trip bundle between two transports on different ports', async () => {
    // Stand up two HttpBundleTransports, peer them, send a bundle, assert receive
  });

  test('G2 self_send rejected at send()', async () => {
    // send to ownCertId → { ok: false, code: 'self_send' }
  });

  test('G3 recipient_not_registered when peer absent from registry', async () => {
    // send to unknown certId → { ok: false, code: 'recipient_not_registered' }
  });

  test('G4 port conflict throws at construction', () => {
    // Create two transports on the same port → second throws
  });

  test('G5 transport_error when peer URL unreachable', async () => {
    // Register peer pointing at a closed port → send returns transport_error
  });

  test('G6 close() stops accepting new connections', async () => {
    // close() then fetch the endpoint → ECONNREFUSED
  });

  test('G7 malformed JSON body returns 400', async () => {
    // POST non-JSON to /federation/bundle → 400
  });
});
```

Commit: `feat(ojt-p3/D3.6): 7 HTTP-specific transport gates`

---

## Step 7: Re-run Slice 5d capstone over HTTP (D3.7)

Duplicate `tests/gates/intent-pipeline-federation-transport.test.ts`
into `tests/gates/intent-pipeline-federation-http-transport.test.ts`.
Change the transport construction from `InMemoryTransport` to
`createHttpTransport` on three ports (OJT: 18080, REA-1: 18081, REA-2:
18082). Every gate (G1–G7) must pass identically.

Key adaptations:
- `beforeAll` now starts three HTTP listeners; `afterAll` closes them.
- `peerRegistry` is constructed with `localhost:18081` / `localhost:18082`
  URLs.
- All other assertions unchanged.

Run:

```bash
bun test tests/gates/intent-pipeline-federation-http-transport.test.ts
```

All 7 gates pass.

Commit: `feat(ojt-p3/D3.7): Slice 5d capstone over HttpBundleTransport`

---

## Step 8: Full pipeline sweep + PR

```bash
bun test    # all 150+ gates still green, plus the 14 new ones from D3.6 + D3.7
git push -u origin feat/http-bundle-transport
gh pr create --title "Slice 5 + OJT P3: HttpBundleTransport" \
  --body "First real BundleTransport implementation. Interface-parity with InMemoryTransport. 14 new gates (7 HTTP-specific + 7 Slice 5d capstone over HTTP). All 157 existing gates still pass."
```

---

## Gate tests (must pass before PR)

- **G1–G7** of the new `http-bundle-transport.test.ts`.
- **G1–G7** of Slice 5d capstone re-run over HTTP.
- All 157 pre-existing pipeline-surface tests still pass.
- No regression in the in-memory gate test.

## Completion criteria

- `runtime/session-protocol/src/http-transport.ts` exists and exports
  `createHttpTransport` + `HttpBundleTransportOptions`.
- `runtime/session-protocol/src/index.ts` exports both.
- 14 new gates pass.
- All 157 pre-existing gates pass.
- PR open with the body above.

When merged, this unblocks P4 (OJT HTTP edge), which imports
`createHttpTransport` to peer with REA nodes.
