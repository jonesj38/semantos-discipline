---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/verifier-sidecar/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.024334+00:00
---

# @semantos/verifier-sidecar — deployment guide

> **D-V2** — Codify per-node sidecar topology default.
> **Phase**: 0.5 (parallel with D-V1).
> **Source of decision**: `docs/prd/UNIFICATION-ROADMAP.md` §8 Q3
> (resolved 2026-04-26); `docs/spec/protocol-v0.5.md` §9.5.

The Verifier Sidecar is the runtime gate that turns BRC-100, BRC-52 cert
authenticity, identity binding, and capability UTXO SPV checks into a
single chokepoint at every adapter boundary. This README codifies *where*
it runs; the *what it does* lives in D-V1's reference implementation
(`packages/verifier-sidecar/src/types.ts`, post-refactor) and in
`docs/spec/protocol-v0.5.md` §9.5.

---

## Default: per-node sidecar process

**A conformant Semantos node SHOULD run exactly one Verifier Sidecar
process per node.** Adapters on that node (World Host, Helm, extensions,
etc.) reach the sidecar over loopback HTTP at the conventions below.

The per-node default applies because:

1. **Independent release cadence.** Security patches to the sidecar land
   without coupling to any adapter's release. The per-surface in-process
   alternative ties the sidecar version to whichever adapter binary
   embeds it; that's the wrong coupling for a security-critical
   chokepoint.
2. **Independent observability.** One process to scrape metrics from,
   one log stream to audit, one health endpoint to probe.
3. **Independent failure domain.** If the sidecar crashes, the node's
   adapters fail closed (no unverified request crosses the boundary)
   without taking the adapter processes down with it.
4. **Architectural fit.** The "sovereign node" deployment model already
   assumes a per-node ensemble of cooperating processes (cell engine,
   World Host, mesh adapter, Helm UI). The sidecar joins that ensemble
   on equal footing rather than embedding into one of them.

This is the rationale recorded in §8 Q3. It is normative for default
deployments. The two alternatives below remain available for the
exception cases their pros lift.

---

## Conventions (port, health route, image path)

| Convention                          | Default                  | Notes                                          |
|-------------------------------------|--------------------------|------------------------------------------------|
| Listen port                         | `8787` (TCP)             | Bound on the node's loopback or local network. |
| Health-check route                  | `GET /healthz`           | Returns `200 OK` when ready to verify.         |
| Topology env var                    | `VERIFIER_SIDECAR_TOPOLOGY=per-node` | Observable for ops dashboards.        |
| Image / build context               | `runtime/verifier-sidecar/` | Built by D-V1's reference implementation.   |
| Compose file                        | `docker-compose.sidecar.yml` (repo root) | Layered onto `docker-compose.yml`.   |

The compose file is layered onto the base node deployment:

```sh
docker compose -f docker-compose.yml -f docker-compose.sidecar.yml up -d
curl -fsS http://localhost:8787/healthz
```

The `/healthz` endpoint MUST return `200` once the sidecar's verifier
chain is initialised (cert cache primed, SPV header sync sufficient,
BRC-100 envelope parser ready). Until then it MUST return `503` so the
container orchestrator does not route traffic to a sidecar that would
fail-open or fail-spuriously.

---

## Boot ordering relative to World Host (D-V3 consumer)

The Verifier Sidecar MUST be ready before any adapter that consumes it
accepts external traffic. World Host (the D-V3 reference consumer) is
the canonical example.

```
1. semantos-node container starts (cell engine + admin API)
2. verifier-sidecar container starts; boots cert cache, SPV headers,
   parsers; flips /healthz from 503 → 200.
3. World Host (and any other D-V3-consuming adapter) starts only after
   step 2's /healthz is 200. Compose `depends_on` with
   `condition: service_healthy` makes this mechanical.
4. Adapter accepts external sockets; every inbound request goes
   sidecar-first via loopback HTTP.
```

The `docker-compose.sidecar.yml` exposes the health-check that other
compose files reference. Adapter compose definitions add:

```yaml
depends_on:
  verifier-sidecar:
    condition: service_healthy
```

Boot-sequence step 8 of `docs/spec/protocol-v0.5.md` ("Verifier Sidecar
starts (per topology decision; §9.5)") is satisfied by step 2 above.
Step 9 ("World Host (if needed) starts regions") corresponds to step 3.

---

## Alternative: per-surface in-process

**When to use.** A tightly-coupled pair where byte-budget or latency
tightness rules out a loopback hop. The named example in §8 Q3 is the
cell engine + World Host on the same node when sub-millisecond gating
matters and the two are co-released anyway.

**How it differs from the default.** The sidecar's verification chain
runs as a library inside the adapter process; there is no `/healthz`
endpoint and no separate container. The adapter's own health check
covers the embedded verifier.

**Trade-offs.**

- **Pro.** Lowest possible latency; no IPC; deploys with the adapter.
- **Con.** Couples sidecar releases to the adapter's release cadence.
  Security patches to BRC-100 / BRC-52 / SPV verification cannot land
  without redeploying the adapter binary.
- **Con.** Multiplies the audit surface — every adapter that embeds is
  its own verifier instance to inspect.

Use this topology only where the latency budget is documented to
require it. Default to per-node otherwise.

---

## Alternative: edge gateway

**When to use.** Centralised deployments where audit-at-a-single-point
is the operational priority — for example, a multi-tenant operator who
wants every BRC-100 request crossing the perimeter logged through one
chokepoint, independent of which node serves it.

**How it differs from the default.** A single Verifier Sidecar
deployment fronts an entire fleet of nodes; adapters on those nodes
reach it over the data-centre network rather than over loopback. The
`/healthz` route still applies; the listen port is typically the same
`8787` exposed on the gateway's ingress address.

**Trade-offs.**

- **Pro.** Single audit point. One log stream covers every request.
- **Pro.** One deployment to patch when verification logic changes.
- **Con.** Single chokepoint — if it goes down, the whole fleet
  fail-closes.
- **Con.** Adds a network hop between adapters and the verifier; the
  per-request latency is dominated by network round-trip, not
  verification cost.
- **Con.** Cross-tenant blast radius on misconfiguration.

Use this topology where audit centralisation is a hard operational
requirement. Default to per-node otherwise.

---

## Per-topology decision matrix (from §9.5)

| Topology                  | Pros                                          | Cons                                              |
|---------------------------|-----------------------------------------------|---------------------------------------------------|
| Per-surface in-process    | Lowest latency; trivial to deploy             | Couples sidecar to each adapter's release cycle   |
| **Per-node sidecar process (default)** | Independent deployment; moderate latency      | One additional process per node                   |
| Edge gateway              | Operationally cleanest; single audit point    | Single chokepoint; adds network hop               |

---

## Tests

The integration test that asserts `GET /healthz` returns `200` against
the compose-deployed sidecar lives at:

- [`__tests__/healthcheck.integration.test.ts`](./__tests__/healthcheck.integration.test.ts)

The test brings the sidecar up via `docker-compose.sidecar.yml`. While
D-V1's binary is not yet merged, the test stubs the verifier-sidecar
container with a minimal HTTP responder bound to the same port + route;
when D-V1 lands, the stub flips to using the real image. See the
TODO(D-V1) markers in the test file.

---

## Related

- [`docs/spec/protocol-v0.5.md`](../../docs/spec/protocol-v0.5.md) §9.5 — Verifier Sidecar normative spec.
- [`docs/prd/UNIFICATION-ROADMAP.md`](../../docs/prd/UNIFICATION-ROADMAP.md) §8 Q3 — topology decision and rationale.
- [`docs/canon/glossary.yml`](../../docs/canon/glossary.yml) § `verifier-sidecar` — canonical term.
- [`docs/canon/deliverables.yml`](../../docs/canon/deliverables.yml) — D-V1 (parallel), D-V2 (this), D-V3 (first integration).
- [`docker-compose.sidecar.yml`](../../docker-compose.sidecar.yml) — codified per-node deployment.
