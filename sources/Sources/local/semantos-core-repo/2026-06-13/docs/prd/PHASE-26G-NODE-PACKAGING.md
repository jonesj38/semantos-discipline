---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26G-NODE-PACKAGING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.664801+00:00
---

# Phase 26G — Node Packaging & Deployment

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1 week
**Prerequisites**: Phase 26F complete (vertical loading)
**Master document**: `PHASE-26-KERNEL-ISOLATION-MASTER.md`
**Branch**: `phase-26g-node-packaging`

---

## Context

Phase 26G is the final sub-phase: packaging the Semantos kernel as a deployable node that an infrastructure partner or enterprise client can install on bare metal, VPS, or Docker. The node ships with the conversational shell, vertical loading system, and all four adapter interfaces (storage, identity, anchor, network).

The kernel binary itself (Zig/WASM cell engine) is immutable and agnostic to deployment environment. The wrapper — installer, systemd service, Docker orchestration, admin API — adapts the kernel to physical deployment targets.

Three target personas:

1. **Tradie ($10/month VPS)** — cloud-hosted Ubuntu 22, managed via phone app, automatic BSV anchoring
2. **Enterprise Colo** — bare metal with provable data residency, on-prem cert chain, faster anchor cycle, subnet allocation
3. **Infrastructure Partner** — Equinix Metal or similar, partner-provisioned hardware, Semantos-provisioned software stack

All three use the same `semantos-node` package. The difference is in the adapter configuration loaded at startup.

---

## Source Files / References

| Alias | Path | What to reference |
|-------|------|------------------|
| `MASTER:26` | `docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md` | Node deployment profiles, adapter summary |
| `PHASE:26F` | `docs/prd/PHASE-26F-VERTICAL-LOADING.md` | Vertical config loading from filesystem |
| `PHASE:26E` | `docs/prd/PHASE-26E-NODE-BOOTSTRAP.md` | NodeConfig, node self-object creation |
| `SVC:KERNEL` | `packages/kernel/src/kernel.ts` | Kernel initialization, cell engine entry point |
| `TYPES:NODE` | `protocol-types/src/node.ts` | NodeConfig interface, NodeStatus type |
| `ADAPT:STORAGE` | `protocol-types/src/storage.ts` | StorageAdapter reference (Phase 25A–D) |
| `ADAPT:IDENTITY` | `protocol-types/src/identity.ts` | IdentityAdapter (Phase 26A–B) |
| `ADAPT:ANCHOR` | `protocol-types/src/anchor.ts` | AnchorAdapter (Phase 26C) |
| `ADAPT:NETWORK` | `protocol-types/src/network.ts` | NetworkAdapter (Phase 26D) |
| `POLICY:BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming convention, branch rules |

---

## Deliverables

### D26G.1 — Docker Image & Compose

**New files**: `Dockerfile`, `docker-compose.yml`

A multi-stage Docker build that compiles the Zig/WASM kernel and packages it with Bun runtime into a minimal production image.

#### Build stages:
1. **Builder stage**: Alpine + Zig toolchain, compile kernel to WASM
2. **Runtime stage**: Minimal Bun image + compiled kernel + shell

#### Dockerfile structure:
```dockerfile
FROM alpine:latest as builder
# Install Zig, compile kernel to WASM
RUN apk add zig ...
COPY packages/kernel /kernel
RUN cd /kernel && zig build -Doptimize=ReleaseSafe

FROM oven/bun:latest
# Copy compiled kernel WASM
COPY --from=builder /kernel/dist/kernel.wasm /app/kernel/
# Copy node bootstrap + shell
COPY packages/node /app/node
COPY packages/shell /app/shell
COPY packages/loom /app/workbench
WORKDIR /app
ENTRYPOINT ["bun", "run", "packages/node/src/index.ts"]
```

#### Volume structure:
- `/var/semantos/data` — storage adapter directory (NodeFsAdapter on production nodes)
- `/etc/semantos` — configuration (node.json, vertical configs, cert files)
- `/var/semantos/verticals` — installed vertical grammars (mounted from host)

#### Ports:
- `3000` — loom UI (React dev server or static bundle)
- `9000` — shard proxy UDP (mesh network participation)
- `6443` — admin API (node management, authenticated via cert)

#### Environment variables:
```
SEMANTOS_MODE=docker|vps|colo|partner
SEMANTOS_BYOK_KEY=<BYOK provider API key>
SEMANTOS_SUBNET_PREFIX=2602:f9f8:0060:0001::
SEMANTOS_ANCHOR_INTERVAL=600000 (ms, default 10min)
SEMANTOS_CERT_PATH=/etc/semantos/node.crt
SEMANTOS_CERT_KEY_PATH=/etc/semantos/node.key
SEMANTOS_DEBUG_LOGGING=false
```

#### docker-compose.yml:
```yaml
version: '3.9'
services:
  semantos-node:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
      - "9000:9000/udp"
      - "6443:6443"
    volumes:
      - semantos-data:/var/semantos/data
      - semantos-config:/etc/semantos
      - ./verticals:/var/semantos/verticals:ro
    environment:
      SEMANTOS_MODE: docker
      SEMANTOS_BYOK_KEY: ${SEMANTOS_BYOK_KEY}
    restart: unless-stopped
    healthcheck:
      test: ["GET", "http://localhost:6443/api/node/status"]
      interval: 30s
      timeout: 5s
      retries: 3

  block-headers-service:
    image: bitcoinops/block-headers:latest
    ports:
      - "8080:8080"
    volumes:
      - block-headers-cache:/var/cache/block-headers

volumes:
  semantos-data:
  semantos-config:
  block-headers-cache:
```

### D26G.2 — install.sh Bare Metal Installer

**New file**: `scripts/install.sh` (755 permissions)

A single-command installer that detects the OS, provisions the node, and starts it as a systemd service.

#### Prerequisites check:
- OS: Ubuntu 22.04+, Debian 12+, or error exit
- CPU: x86-64 or ARM64
- Memory: 2GB+ recommended
- Disk: 10GB+ for /var/semantos

#### Installation steps:
1. **Detect OS and package manager** (apt)
2. **Install Bun runtime** (via https://bun.sh/install)
3. **Create /var/semantos directory structure**:
   ```
   /var/semantos/
   ├── data/          (storage adapter root)
   ├── verticals/     (grammar configs)
   └── cache/         (WASM runtime cache)
   ```
4. **Create /etc/semantos** with owner semantos:semantos (644 permissions)
5. **Download latest semantos-node package** from release artifacts or npm
6. **Interactive prompts**:
   ```
   ┌─────────────────────────────────┐
   │ Semantos Node Installation      │
   ├─────────────────────────────────┤
   │ Certificate path: /etc/semantos/node.crt
   │ (Copy a BRC-52 cert file or press Enter to generate stub)
   │
   │ Subnet prefix [2602:f9f8:0060:0001::]:
   │
   │ OpenRouter API key (for conversational shell):
   │
   │ Anchor interval (ms) [600000]:
   │
   │ Install trades vertical? (y/n) [y]:
   └─────────────────────────────────┘
   ```
7. **Write /etc/semantos/node.json**:
   ```json
   {
     "nodeId": "generated-uuid",
     "mode": "vps",
     "certPath": "/etc/semantos/node.crt",
     "certKeyPath": "/etc/semantos/node.key",
     "subnetPrefix": "2602:f9f8:0060:0001::",
     "byokKey": "your-openrouter-key",
     "anchorInterval": 600000,
     "verticals": ["trades"]
   }
   ```
8. **Create systemd service unit** at `/etc/systemd/system/semantos.service`:
   ```ini
   [Unit]
   Description=Semantos Kernel Node
   After=network-online.target
   Wants=network-online.target

   [Service]
   Type=simple
   User=semantos
   WorkingDirectory=/var/semantos
   EnvironmentFile=/etc/semantos/node.json
   ExecStart=/home/semantos/.bun/bin/bun run /opt/semantos/index.ts
   Restart=on-failure
   RestartSec=10
   StandardOutput=journal
   StandardError=journal

   [Install]
   WantedBy=multi-user.target
   ```
9. **Enable and start the service**:
   ```bash
   systemctl daemon-reload
   systemctl enable semantos
   systemctl start semantos
   ```
10. **Print success message**:
    ```
    ✓ Semantos node installed and running
    Loom UI:    http://<ip>:3000
    Admin API:       https://<ip>:6443/api/node/status
    Node BCA:        2602:f9f8:0060:0001::a3f8
    Node cert ID:    <cert-id-truncated>

    View logs:       journalctl -u semantos -f
    ```

### D26G.3 — semantos CLI Node Management

**New file**: `packages/node/src/cli.ts`

A command-line tool for managing local or remote Semantos nodes. Invoked as `semantos` after npm global install or docker exec.

#### Commands:

**Node lifecycle**:
- `semantos init --cert <path> --subnet <prefix>` — Initialize node from config prompts
- `semantos start` — Start node service (systemd or Docker)
- `semantos stop` — Stop node service
- `semantos status` — Show node status (uptime, adapter mode, verticals, last anchor)
- `semantos restart` — Restart node service
- `semantos logs [--follow]` — Stream systemd journal logs

**Vertical management**:
- `semantos install vertical trades` — Install trades vertical from release
- `semantos install vertical sovereignty` — Install sovereignty vertical
- `semantos list verticals` — List installed and available verticals
- `semantos uninstall vertical <name>` — Remove vertical and wipe its storage

**Identity management**:
- `semantos identity list` — List all identities (root + facets)
- `semantos identity create --email <email>` — Register new root identity
- `semantos identity export --cert-id <id>` — Export identity recovery payload
- `semantos identity revoke --cert-id <id>` — Revoke a facet or identity

**Anchoring**:
- `semantos anchor now` — Trigger manual anchor cycle (without waiting for interval)
- `semantos anchor status` — Show last anchor proof, next scheduled anchor
- `semantos anchor history` — List recent anchor proofs (last 10)

**Node self-object**:
- `semantos self` — Print node RELEVANT object (JSON)
- `semantos self --follow` — Watch node object for changes

**Admin operations** (auth via node cert):
- `semantos admin --endpoint https://localhost:6443 status`
- `semantos admin --endpoint https://localhost:6443 install-vertical sovereignty`

All commands that mutate state require the node cert to be loaded and valid.

### D26G.4 — Admin API (port 6443)

**New file**: `packages/node/src/api/admin.ts`

A REST API for remote node management, authenticated via TLS client certificate (mutual TLS).

#### Authentication:
- Endpoint: `https://node-ip:6443`
- Mutual TLS: client must present valid node cert (same cert that boots the node)
- All responses signed with node cert private key (optional, for offline verification)

#### Endpoints:

**Node introspection**:
- `GET /api/node/status` → `{ certId, uptime, mode, version, adapters: {...} }`
- `GET /api/node/verticals` → `[{ name, version, installed, typeCount, flowCount }]`
- `GET /api/node/anchors` → `[{ hash, timestamp, blockHeight, txId }]` (last 10)
- `GET /api/node/identities` → `[{ certId, email, created, children }]`

**Vertical management**:
- `POST /api/node/verticals/install { name, version? }` → `{ status: "installing|installed", progress? }`
- `DELETE /api/node/verticals/:name` → `{ status: "removed" }`

**Identity management**:
- `POST /api/node/identities { email }` → `{ certId, publicKey }`
- `GET /api/node/identities/:certId` → `{ certId, email, children }`
- `POST /api/node/identities/:certId/revoke` → `{ status: "revoked" }`

**Anchor management**:
- `POST /api/node/anchor` → Trigger immediate anchor cycle; returns `{ blockHeight, txId, proof }`
- `GET /api/node/anchor/interval` → `{ intervalMs, nextAnchorAt }`
- `PUT /api/node/anchor/interval { ms }` → `{ intervalMs }`

**Shell integration** (for phone app):
- `POST /api/node/shell { prompt }` → `{ response, objectPath, nextPrompt? }`
  - Scoped to node RELEVANT object; returns intent-classified response and next suggested action

#### Response format (all endpoints):
```typescript
{
  data: T,
  timestamp: number,
  signature?: string,  // optional ECDSA sig of (data + timestamp + certId)
  error?: { code: string; message: string }
}
```

#### Error handling:
- 401 Unauthorized → cert not presented or invalid
- 403 Forbidden → cert valid but not authorized for this operation
- 500 Internal Server Error → unexpected kernel failure

### D26G.5 — Deployment Documentation

**New files**:
- `docs/deployment/VPS-DEPLOYMENT.md`
- `docs/deployment/DOCKER-DEPLOYMENT.md`
- `docs/deployment/ENTERPRISE-COLO.md`
- `docs/deployment/INFRA-PARTNER.md`

#### VPS Deployment Guide (Digital Ocean, Vultr, Hetzner):
- Minimal Ubuntu 22 droplet (2GB RAM, 2 vCPU, 50GB SSD)
- SSH into fresh OS, run `curl -s https://semantos.io/install.sh | bash`
- Answer prompts (cert path, subnet, OpenRouter key)
- Node boots automatically via systemd
- Phone app connects to `https://<ip>:6443` using node cert
- Costs: ~$10/month cloud + $20/yr Plexus cloud identity RaaS

#### Docker Deployment Guide:
- Prerequisites: Docker 20.10+, Docker Compose 1.29+
- Clone repo, customize `docker-compose.yml` volumes
- Run `docker-compose up -d`
- Check health: `docker exec semantos-node bun run packages/node/src/cli.ts status`
- Persistence: volumes survive container restarts
- Scaling: shard-aware service discovery via network overlay

#### Enterprise Colo Deployment Guide:
- Bare metal provisioning: partner provides Ubuntu 22 server on campus LAN
- Cert chain: enterprise must have root cert from Plexus or local CA
- Install: `curl https://internal-mirror.corp/install.sh | bash`
- Config: subnet allocation from enterprise IPAM, on-prem cert signing
- Compliance: all data stays on customer hardware; audit logs to `/var/semantos/audit/`
- Anchor cycle: 1 min instead of 10 min for faster state finality
- Networking: DirectNetworkAdapter for campus LAN + optional BsvOverlay for inter-site WAN

#### Infrastructure Partner Deployment Guide:
- Partner provisions bare metal on Equinix Metal / Packet Bare Metal / AWS Dedicated Host
- Partner runs install script (same as VPS)
- Partner notifies Semantos of allocated subnet (2602:f9f8:0060:NNNN::/64)
- Semantos creates partner entry in node registry
- Partner's customers rent node slices; Semantos bills partner per customer per month
- Node manifests as infrastructure partner RELEVANT object; governance flows are partner-scoped
- Partner can install verticals (sovereignty, CDM, SCADA) and bill back to customers

---

## TDD Gate: 10+ Tests

**Category: Deployment & Node Lifecycle**

- **T1**: Docker image builds successfully on fresh `docker build` with no errors
- **T2**: `docker-compose up` starts all services; health checks pass within 30 seconds
- **T3**: Node API responds to `GET /api/node/status` with valid cert-signed response
- **T4**: install.sh runs on Ubuntu 22 bare metal; creates /var/semantos and /etc/semantos
- **T5**: systemd service unit is valid; `systemctl start semantos` succeeds without timeout
- **T6**: `semantos status` CLI command connects to running node and returns status
- **T7**: `semantos install vertical trades` downloads and activates trades vertical
- **T8**: Manual anchor trigger (`semantos anchor now`) produces valid anchor proof within 10s
- **T9**: Node self-object (`semantos self`) contains correct certId, adapters, and verticals
- **T10**: Admin API mutual TLS rejects requests without valid node cert (401 response)

**Example test structure** (pseudocode):
```typescript
describe("Phase 26G: Node Packaging", () => {
  // T1: Docker build
  test("docker build produces valid image", async () => {
    const result = await exec("docker build -t semantos:test .");
    expect(result.exitCode).toBe(0);
  });

  // T2: docker-compose health
  test("docker-compose services pass health checks", async () => {
    await exec("docker-compose up -d");
    await waitForCondition(() => healthCheckPasses(), 30000);
    const status = await fetch("http://localhost:6443/api/node/status");
    expect(status.status).toBe(200);
  });

  // T3–T10: similar integration tests
});
```

---

## What NOT to Do

- **Don't hardcode infrastructure partner details** in the node package. Use environment variables or config files.
- **Don't include private keys in the Docker image**. Certs must be mounted at runtime.
- **Don't skip cert authentication on the admin API.** Mutual TLS is mandatory.
- **Don't assume IPv4-only networking.** Subnet prefix defaults to IPv6; support both.
- **Don't start the node without loading verticals.** Kernel boots; shell loads verticals from /var/semantos/verticals.
- **Don't embed OpenRouter key in the image.** Use BYOK_KEY env var.
- **Don't assume root user.** All file operations use semantos:semantos user.
- **Don't break existing Phase 25A–D and 26A–F tests.** All prior gate tests must still pass.

---

## Completion Criteria

- [ ] `Dockerfile` builds multi-stage image with Zig/WASM compilation
- [ ] `docker-compose.yml` defines three services (node, block-headers, volumes)
- [ ] `scripts/install.sh` is executable, detects OS, creates directory structure, writes node.json
- [ ] `packages/node/src/cli.ts` implements all D26G.3 commands (init, start, stop, status, etc.)
- [ ] `packages/node/src/api/admin.ts` implements all D26G.4 endpoints with mutual TLS auth
- [ ] Deployment docs exist for all four target personas (VPS, Docker, Colo, Partner)
- [ ] Tests T1–T10 all pass (Docker build, compose health, CLI, API, anchor, vertical install)
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] No prior phase tests regressed (Phase 25A–D, Phase 26A–F still pass)
- [ ] All commits follow `phase-26g/D26G.N:` naming convention
- [ ] Branch is `phase-26g-node-packaging`

---

## Next Phase

Phase 27 deploys the first production tradie node (VPS) and the first enterprise demo node (Colo). Phase 28 integrates the Flutter mobile shell as the primary UI for tradie daily operations.
