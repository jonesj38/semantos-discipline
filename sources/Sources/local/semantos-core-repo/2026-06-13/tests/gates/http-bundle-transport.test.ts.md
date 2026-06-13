---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/http-bundle-transport.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.582967+00:00
---

# tests/gates/http-bundle-transport.test.ts

```ts
/**
 * Gate test — HttpBundleTransport behavior.
 *
 * Exercises HTTP-specific concerns that InMemoryTransport doesn't:
 * - port binding + conflict detection
 * - real fetch round-trip between two localhost ports
 * - peer registry lookup
 * - graceful shutdown
 * - malformed request handling
 *
 * Interface parity with InMemoryTransport is separately proved by
 * intent-pipeline-federation-http-transport.test.ts which re-runs the
 * Slice 5d capstone over HTTP and must pass the same gates.
 */
import { afterEach, describe, expect, test } from "bun:test";
import {
  createHttpTransport,
  TransportError,
  signBundle,
  StubSigner,
  type SignedBundle,
} from "../../runtime/session-protocol/src/index.js";

const OJT_CERT = "ojt-http-cert";
const REA_CERT = "rea-http-cert";

// Each test picks its own port range to avoid cross-test conflicts.
let nextPort = 19000;
function port(): number {
  return nextPort++;
}

interface TestPayload {
  jobId: string;
}

async function mkSignedBundle(
  payload: TestPayload,
  senderCert: string,
  recipientCert: string,
): Promise<SignedBundle<TestPayload>> {
  const signer = new StubSigner("01".repeat(32));
  const ident = await signer.identity();
  const pubkeyHex = Array.from(ident.pubkey)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  const bundle = await signBundle(payload, signer, {
    recipient: { certId: recipientCert, pubkeyHex },
  });
  return {
    ...bundle,
    signer: { ...bundle.signer, certId: senderCert },
  };
}

describe("HttpBundleTransport — HTTP-specific gates", () => {
  const teardowns: Array<() => Promise<void>> = [];
  afterEach(async () => {
    while (teardowns.length) {
      const fn = teardowns.pop()!;
      try {
        await fn();
      } catch {
        // best-effort
      }
    }
  });

  test("G1 round-trip: OJT sends bundle to REA via HTTP", async () => {
    const ojtPort = port();
    const reaPort = port();

    const ojt = createHttpTransport({
      ownCertId: OJT_CERT,
      listenPort: ojtPort,
      peerRegistry: new Map([[REA_CERT, `http://127.0.0.1:${reaPort}`]]),
    });
    const rea = createHttpTransport({
      ownCertId: REA_CERT,
      listenPort: reaPort,
      peerRegistry: new Map([[OJT_CERT, `http://127.0.0.1:${ojtPort}`]]),
    });
    teardowns.push(() => ojt.close());
    teardowns.push(() => rea.close());

    const received: SignedBundle<TestPayload>[] = [];
    rea.onReceive<TestPayload>((b) => {
      received.push(b);
    });

    const bundle = await mkSignedBundle({ jobId: "job-1" }, OJT_CERT, REA_CERT);
    await ojt.send(bundle);

    // Bun.serve handlers run synchronously on the same loop; the
    // HTTP response is only sent after the handler completes.
    expect(received.length).toBe(1);
    expect(received[0].payload.jobId).toBe("job-1");
  });

  test("G2 self_send rejected before the wire", async () => {
    const p = port();
    const t = createHttpTransport({
      ownCertId: OJT_CERT,
      listenPort: p,
      peerRegistry: new Map([[OJT_CERT, `http://127.0.0.1:${p}`]]),
    });
    teardowns.push(() => t.close());
    const bundle = await mkSignedBundle(
      { jobId: "self" },
      OJT_CERT,
      OJT_CERT,
    );
    await expect(t.send(bundle)).rejects.toMatchObject({
      code: "self_send",
    });
  });

  test("G3 recipient_not_registered when peer missing from registry", async () => {
    const p = port();
    const t = createHttpTransport({
      ownCertId: OJT_CERT,
      listenPort: p,
      peerRegistry: new Map(), // empty — REA not registered
    });
    teardowns.push(() => t.close());
    const bundle = await mkSignedBundle(
      { jobId: "nope" },
      OJT_CERT,
      "unknown-cert",
    );
    await expect(t.send(bundle)).rejects.toMatchObject({
      code: "recipient_not_registered",
    });
  });

  test("G4 unaddressed_bundle rejected at send()", async () => {
    const p = port();
    const t = createHttpTransport({
      ownCertId: OJT_CERT,
      listenPort: p,
      peerRegistry: new Map(),
    });
    teardowns.push(() => t.close());
    const signer = new StubSigner("01".repeat(32));
    const unaddressed = await signBundle({ jobId: "unaddressed" }, signer);
    await expect(t.send(unaddressed)).rejects.toMatchObject({
      code: "unaddressed_bundle",
    });
  });

  test("G5 port conflict throws at construction", async () => {
    const p = port();
    const first = createHttpTransport({
      ownCertId: OJT_CERT,
      listenPort: p,
      peerRegistry: new Map(),
    });
    teardowns.push(() => first.close());
    expect(() =>
      createHttpTransport({
        ownCertId: "second",
        listenPort: p,
        peerRegistry: new Map(),
      }),
    ).toThrow(TransportError);
  });

  test("G6 send to unreachable peer URL surfaces an error", async () => {
    const p = port();
    const deadPort = port(); // nothing bound here
    const t = createHttpTransport({
      ownCertId: OJT_CERT,
      listenPort: p,
      peerRegistry: new Map([[REA_CERT, `http://127.0.0.1:${deadPort}`]]),
      requestTimeoutMs: 2000,
    });
    teardowns.push(() => t.close());
    const bundle = await mkSignedBundle({ jobId: "ghost" }, OJT_CERT, REA_CERT);
    await expect(t.send(bundle)).rejects.toBeInstanceOf(TransportError);
  });

  test("G7 malformed POST body returns 400", async () => {
    const p = port();
    const t = createHttpTransport({
      ownCertId: OJT_CERT,
      listenPort: p,
      peerRegistry: new Map(),
    });
    teardowns.push(() => t.close());
    t.onReceive(() => {
      /* never fires for bad body */
    });
    const res = await fetch(`http://127.0.0.1:${p}/federation/bundle`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "not json {{",
    });
    expect(res.status).toBe(400);
  });

  test("G8 close() stops accepting new connections", async () => {
    const p = port();
    const t = createHttpTransport({
      ownCertId: OJT_CERT,
      listenPort: p,
      peerRegistry: new Map(),
    });
    await t.close();
    // Either the fetch errors (connection refused) OR the server still
    // returns 503 because Bun.stop(true) is in progress. Both are
    // acceptable post-close behaviors.
    try {
      const res = await fetch(`http://127.0.0.1:${p}/federation/bundle`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: "{}",
      });
      expect([503, 404].includes(res.status)).toBe(true);
    } catch (err) {
      // connection refused is also acceptable
      expect(String(err)).toMatch(/failed|refused|closed|fetch|ECONNREFUSED|unable to connect/i);
    }
  });

  test("G9 custom pathPrefix works", async () => {
    const ojtPort = port();
    const reaPort = port();
    const ojt = createHttpTransport({
      ownCertId: OJT_CERT,
      listenPort: ojtPort,
      peerRegistry: new Map([[REA_CERT, `http://127.0.0.1:${reaPort}`]]),
      pathPrefix: "/v3",
    });
    const rea = createHttpTransport({
      ownCertId: REA_CERT,
      listenPort: reaPort,
      peerRegistry: new Map([[OJT_CERT, `http://127.0.0.1:${ojtPort}`]]),
      pathPrefix: "/v3",
    });
    teardowns.push(() => ojt.close());
    teardowns.push(() => rea.close());
    const received: SignedBundle<TestPayload>[] = [];
    rea.onReceive<TestPayload>((b) => {
      received.push(b);
    });
    const bundle = await mkSignedBundle({ jobId: "j-v3" }, OJT_CERT, REA_CERT);
    await ojt.send(bundle);
    expect(received[0]?.payload.jobId).toBe("j-v3");
  });

  test("G10 localCertId reflects ownCertId", () => {
    const p = port();
    const t = createHttpTransport({
      ownCertId: "some-cert",
      listenPort: p,
      peerRegistry: new Map(),
    });
    teardowns.push(() => t.close());
    expect(t.localCertId).toBe("some-cert");
  });
});

```
