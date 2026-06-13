---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/verifier-sidecar/__tests__/healthcheck.integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.086277+00:00
---

# runtime/verifier-sidecar/__tests__/healthcheck.integration.test.ts

```ts
/**
 * D-V2 / D-V3 — Verifier Sidecar deployment topology + server-direct contract.
 *
 * Three sections:
 *   1. Compose-file static assertions       (D-V2, always on)
 *   2. Docker-compose health-check          (D-V2, gated DOCKER_INTEGRATION=1)
 *   3. Server-direct /healthz contract      (D-V3, always on)
 *      Boots the real `VerifierSidecarServer` from
 *      `runtime/verifier-sidecar/src/server.ts` in-process and asserts
 *      the same contract end-to-end. This replaces the loopback-stub
 *      `createServer` path that pre-dated D-V1; the stub is now obsolete
 *      because D-V3 ships the real binary that the stub was simulating.
 *
 * The compose deployment is the codified default (per-node process,
 * per Unification Roadmap §8 Q3 / protocol-v0.5.md §9.5). The test
 * exercises the boot ordering an adapter (D-V3 World Host) would rely
 * on: depends_on with `condition: service_healthy`.
 *
 * Cross-references:
 *   docker-compose.sidecar.yml         — compose file under test
 *   runtime/verifier-sidecar/README.md — deployment guide
 *   runtime/verifier-sidecar/src/server.ts — D-V3 HTTP server entry-point
 *   docs/spec/protocol-v0.5.md §9.5    — Verifier Sidecar
 *   docs/prd/UNIFICATION-ROADMAP.md §8 Q3 — topology decision source
 */

import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { spawnSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { createServer, type Server } from "node:http";

import { VerifierSidecarServer } from "../src/server.js";

const REPO_ROOT = resolve(__dirname, "..", "..", "..");
const COMPOSE_FILE = resolve(REPO_ROOT, "docker-compose.sidecar.yml");
const SIDECAR_PORT = 8787;
const HEALTH_ROUTE = "/healthz";
const HEALTH_URL = `http://localhost:${SIDECAR_PORT}${HEALTH_ROUTE}`;

// ── Compose-file static assertions ────────────────────────────────────

describe("D-V2: docker-compose.sidecar.yml structure", () => {
  test("compose file exists at the repo root", () => {
    expect(existsSync(COMPOSE_FILE)).toBe(true);
  });

  test("declares verifier-sidecar service on port 8787", () => {
    const yml = readFileSync(COMPOSE_FILE, "utf8");
    expect(yml).toContain("verifier-sidecar:");
    expect(yml).toContain("8787:8787");
  });

  test("build context points at runtime/verifier-sidecar (D-V1)", () => {
    const yml = readFileSync(COMPOSE_FILE, "utf8");
    expect(yml).toContain("./runtime/verifier-sidecar");
  });

  test("declares healthcheck targeting /healthz", () => {
    const yml = readFileSync(COMPOSE_FILE, "utf8");
    expect(yml).toContain("/healthz");
    expect(yml).toMatch(/healthcheck:/);
  });

  test("topology env defaults to per-node", () => {
    const yml = readFileSync(COMPOSE_FILE, "utf8");
    expect(yml).toContain('VERIFIER_SIDECAR_TOPOLOGY: "per-node"');
  });
});

// ── Docker-compose path (gated) ───────────────────────────────────────

describe("D-V2: docker-compose health-check (gated)", () => {
  // Gated for two reasons:
  //   1. Docker is not always available in CI.
  //   2. D-V1's image build context does not yet exist in this worktree;
  //      the compose `build.context` will resolve only after D-V1 lands.
  // Run with: DOCKER_INTEGRATION=1 bun test runtime/verifier-sidecar
  const skipDocker = !process.env.DOCKER_INTEGRATION;

  test.skipIf(skipDocker)(
    "compose up + GET /healthz returns 200, then compose down",
    async () => {
      // TODO(D-V1): once runtime/verifier-sidecar/Dockerfile exists,
      // this block runs a real container. For now it is documented but
      // skipped by default.
      const up = spawnSync(
        "docker",
        ["compose", "-f", COMPOSE_FILE, "up", "-d", "--wait"],
        { cwd: REPO_ROOT, stdio: "inherit" },
      );
      expect(up.status).toBe(0);

      try {
        const res = await fetch(HEALTH_URL);
        expect(res.status).toBe(200);
      } finally {
        spawnSync("docker", ["compose", "-f", COMPOSE_FILE, "down", "-v"], {
          cwd: REPO_ROOT,
          stdio: "inherit",
        });
      }
    },
    60_000,
  );
});

// ── Server-direct path (D-V3, always on) ──────────────────────────────
//
// D-V3 brings the real HTTP server into runtime/verifier-sidecar/src/server.ts.
// Boot it on an ephemeral loopback port and assert the contract end-to-end.
// The pre-D-V3 `createServer` stub path is no longer needed — the real
// binary now provides the same /healthz contract the stub was simulating.

describe("D-V3: VerifierSidecarServer /healthz contract (in-process)", () => {
  let server: VerifierSidecarServer;
  // Port 0 lets the OS pick an ephemeral port; we then read it back via
  // server.listeningPort. Avoids collision with a real sidecar on 8787.
  beforeAll(() => {
    server = new VerifierSidecarServer({ port: 0, readyOnStart: false });
    server.start();
  });

  afterAll(() => {
    server.stop();
  });

  test("/healthz returns 503 before markReady()", async () => {
    const port = server.listeningPort;
    expect(port).not.toBeNull();
    const res = await fetch(`http://127.0.0.1:${port}${HEALTH_ROUTE}`);
    expect(res.status).toBe(503);
    const body = (await res.json()) as { status: string; topology: string };
    expect(body.status).toBe("starting");
    expect(body.topology).toBe("per-node");
  });

  test("/healthz returns 200 after markReady() — D-V2 contract honoured", async () => {
    server.markReady();
    const port = server.listeningPort;
    const res = await fetch(`http://127.0.0.1:${port}${HEALTH_ROUTE}`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { status: string; topology: string };
    expect(body.status).toBe("ok");
    expect(body.topology).toBe("per-node");
  });

  test("non-/healthz routes return 404", async () => {
    const port = server.listeningPort;
    const res = await fetch(`http://127.0.0.1:${port}/`);
    expect(res.status).toBe(404);
  });
});

// ── Legacy loopback-stub path (kept dormant — see comment) ────────────
//
// Reference the unused imports so the module still loads cleanly even
// though they are no longer exercised. The createServer + Server import
// remain in case a future test re-introduces a non-Bun stub path; remove
// these lines if/when that's been settled.
void createServer;
type _UnusedServer = Server;

```
