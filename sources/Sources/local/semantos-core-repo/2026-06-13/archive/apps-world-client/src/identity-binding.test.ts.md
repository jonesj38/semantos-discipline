---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/identity-binding.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.823564+00:00
---

# archive/apps-world-client/src/identity-binding.test.ts

```ts
/**
 * Tests for PR-B3 identity wiring.
 *
 * Strategy:
 *   - WorldSocket tests: mock Phoenix (Socket/Channel) minimally — intercept
 *     `channel.join().receive("ok", cb)` and invoke cb synchronously.
 *   - EntityMesh / color tests: exercise the pure color-decision functions
 *     (`certColor`, `pickCubeColor`, `AVATAR_PALETTE`) directly without
 *     constructing THREE.js meshes (avoids jsdom dependency). The contract
 *     these functions satisfy is exactly what `CubeMesh` uses internally.
 *   - Recovery flow: drive the stub recoveryPort end-to-end and verify the
 *     decoded export payload.
 */

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import {
  bindAllIdentityPorts,
  unbindAllIdentityPorts,
  identityPort,
  recoveryPort,
} from "@semantos/identity-ports";
import { makeStubBindings } from "@semantos/identity-ports/stub";
import { certColor, pickCubeColor, AVATAR_PALETTE } from "@semantos/cube-object";

// ─── WorldSocket identity registration ───────────────────────────────────────

/**
 * Minimal Phoenix mock.
 * `socket.channel(topic)` returns a fake channel whose `.join()` returns a
 * push-like object; calling `.receive("ok", cb)` stores cb and exposes a
 * `triggerOk()` helper to fire it synchronously.
 */
function makePhoenixMock() {
  let joinOkCb: (() => void) | null = null;
  const triggerJoinOk = () => {
    if (joinOkCb) joinOkCb();
  };

  const pushLike = {
    receive(event: string, cb: (...args: unknown[]) => void) {
      if (event === "ok") joinOkCb = cb as () => void;
      return pushLike;
    },
  };

  const channel = {
    on: vi.fn(),
    join: vi.fn(() => pushLike),
    leave: vi.fn(),
  };

  const socket = {
    onOpen: vi.fn((cb: () => void) => cb()), // fire immediately
    onClose: vi.fn(),
    onError: vi.fn(),
    connect: vi.fn(),
    channel: vi.fn(() => channel),
    disconnect: vi.fn(),
  };

  return { socket, channel, triggerJoinOk };
}

describe("WorldSocket — identity registration on connect", () => {
  beforeEach(() => {
    bindAllIdentityPorts(makeStubBindings().bundle);
  });

  afterEach(() => {
    unbindAllIdentityPorts();
    vi.resetModules();
  });

  it("registers identity and stashes localCertId when channel joins", async () => {
    // We need to mock the 'phoenix' module so WorldSocket uses our fake Socket.
    const { socket: mockSocket, triggerJoinOk } = makePhoenixMock();

    vi.doMock("phoenix", () => ({
      Socket: vi.fn(() => mockSocket),
      Channel: vi.fn(),
    }));

    const { WorldSocket } = await import("./socket");

    const handlers = {
      onStatus: vi.fn(),
      onSnapshot: vi.fn(),
      onTickDelta: vi.fn(),
      onEntitySpawn: vi.fn(),
      onEntityDespawn: vi.fn(),
      onActionResult: vi.fn(),
    };

    const ws = new WorldSocket("region-0001", handlers);
    expect(ws.localCertId).toBeNull();

    ws.connect();
    triggerJoinOk();

    // After join OK, localCertId should be a non-empty string.
    expect(ws.localCertId).toBeTruthy();
    // It should be a deterministic stub certId (64 hex chars).
    expect(ws.localCertId).toMatch(/^[0-9a-f]{64}$/);
    // Should call onStatus("joined") after registering.
    expect(handlers.onStatus).toHaveBeenCalledWith("joined");
  });

  it("registers identity at most once per sessionId (idempotent)", async () => {
    const { socket: mockSocket, triggerJoinOk } = makePhoenixMock();

    vi.doMock("phoenix", () => ({
      Socket: vi.fn(() => mockSocket),
      Channel: vi.fn(),
    }));

    const { WorldSocket } = await import("./socket");

    const handlers = {
      onStatus: vi.fn(),
      onSnapshot: vi.fn(),
      onTickDelta: vi.fn(),
      onEntitySpawn: vi.fn(),
      onEntityDespawn: vi.fn(),
      onActionResult: vi.fn(),
    };

    const ws = new WorldSocket("region-0001", handlers);
    ws.connect();
    triggerJoinOk();

    const first = ws.localCertId;
    // Simulate reconnect — trigger OK again.
    triggerJoinOk();
    // Should still be the same certId (stub registerIdentity is idempotent).
    expect(ws.localCertId).toBe(first);
  });
});

// ─── Color resolution — avatar palette path ───────────────────────────────────

describe("certColor — resolves to AVATAR_PALETTE entry", () => {
  it("certColor maps a known publicKey to a value in AVATAR_PALETTE", () => {
    // Build a stub cert manually — same shape CubeMesh.safeGetCert returns.
    const fakeCert = {
      certId: "abc",
      publicKey: "02stubpk00" + "a".repeat(50),
      email: "test@stub.local",
      parentCertId: null,
      childIndex: -1,
      resourceId: undefined,
      domainFlag: undefined,
      derivationPath: "root",
      createdAt: 0,
    };

    const color = certColor(fakeCert as Parameters<typeof certColor>[0]);
    expect(AVATAR_PALETTE).toContain(color);
  });

  it("certColor is deterministic for the same publicKey", () => {
    const cert = {
      certId: "xyz",
      publicKey: "02stubpk00" + "b".repeat(50),
      email: "foo@stub.local",
      parentCertId: null,
      childIndex: -1,
      resourceId: undefined,
      domainFlag: undefined,
      derivationPath: "root",
      createdAt: 0,
    };

    const c1 = certColor(cert as Parameters<typeof certColor>[0]);
    const c2 = certColor(cert as Parameters<typeof certColor>[0]);
    expect(c1).toBe(c2);
  });

  it("pickCubeColor returns cert-derived color when cert is present (identity bound)", () => {
    const cert = {
      certId: "cid1",
      publicKey: "02stubpk00" + "c".repeat(50),
      email: "e@stub.local",
      parentCertId: null,
      childIndex: -1,
      resourceId: undefined,
      domainFlag: undefined,
      derivationPath: "root",
      createdAt: 0,
    };
    const color = pickCubeColor({ explicit: null, cert: cert as Parameters<typeof certColor>[0], linearity: 0 });
    expect(AVATAR_PALETTE).toContain(color);
  });

  it("pickCubeColor returns linearity color when cert is null (no identity)", () => {
    // linearity 0 = LINEAR = teal 0x2cb2a5
    const color = pickCubeColor({ explicit: null, cert: null, linearity: 0 });
    // Should NOT be in AVATAR_PALETTE (linearity colors are distinct).
    // Just verify it is a number and matches the linearity default.
    expect(color).toBe(0x2cb2a5);
    // linearity colors are NOT in the avatar palette.
    expect(AVATAR_PALETTE).not.toContain(color);
  });

  it("pickCubeColor explicit color takes priority over cert", () => {
    const cert = {
      certId: "cid2",
      publicKey: "02stubpk00" + "d".repeat(50),
      email: "e2@stub.local",
      parentCertId: null,
      childIndex: -1,
      resourceId: undefined,
      domainFlag: undefined,
      derivationPath: "root",
      createdAt: 0,
    };
    const explicitColor = 0x123456;
    const color = pickCubeColor({
      explicit: explicitColor,
      cert: cert as Parameters<typeof certColor>[0],
      linearity: 0,
    });
    expect(color).toBe(explicitColor);
  });
});

// ─── Full stub recovery flow ──────────────────────────────────────────────────

describe("recovery flow — stub defaults verify successfully", () => {
  beforeEach(() => {
    bindAllIdentityPorts(makeStubBindings().bundle);
  });

  afterEach(() => {
    unbindAllIdentityPorts();
  });

  it("returns verified:true and a decodable exportPayload with stub defaults", () => {
    const email = "session123@stub.local";
    const initiation = recoveryPort.get().initiateRecovery(email);

    expect(initiation.challengeCount).toBeGreaterThan(0);

    const answers = initiation.challenges.map((c) => ({
      challengeId: c.id,
      answer: "yes",
    }));

    const verdict = recoveryPort.get().submitChallengeAnswers(
      initiation.sessionId,
      answers,
    );

    expect(verdict.verified).toBe(true);
    expect(verdict.exportPayload).toBeTruthy();

    const decoded = JSON.parse(atob(verdict.exportPayload!));
    expect(decoded.stub).toBe(true);
    expect(decoded.email).toBe(email);
  });

  it("registers an identity and it resolves via identityPort", () => {
    const email = "session456@stub.local";
    const reg = identityPort.get().registerIdentity(email);

    expect(reg.certId).toMatch(/^[0-9a-f]{64}$/);
    expect(reg.publicKey).toMatch(/^02/);

    const resolved = identityPort.get().resolveIdentity(reg.certId);
    expect(resolved.email).toBe(email);
    expect(resolved.certId).toBe(reg.certId);
  });
});

```
