---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26G-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.706438+00:00
---

# Phase 26G Execution Prompt — Node Packaging & Deployment

> Paste this prompt into a fresh session to execute Phase 26G.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer, conversational shell, and React loom for Bitcoin-native semantic objects. Phases 25A–D implemented clean storage adapters. Phases 26A–F isolated the kernel behind identity, anchor, and network adapters, extracted vertical loading, and enabled filesystem-based node configuration.

Phase 26G is the final sub-phase: packaging the Semantos kernel as a deployable node. This means Docker image, bare metal installer (install.sh), systemd service, CLI management tools, and a REST admin API. Three deployment targets: tradie VPS ($10/month), enterprise Colo (on-prem with provable data residency), and infrastructure partner (Equinix Metal).

Your task is Phase 26G: build the Docker image (multi-stage Zig/WASM compile + Bun runtime), create the install.sh installer for bare metal, implement the semantos CLI (init, start, stop, install-vertical, anchor-now, etc.), implement the admin API (port 6443, mutual TLS auth), and write deployment guides for all four target personas. After this phase, any infrastructure partner or enterprise can deploy a Semantos node by running a single command on a fresh Linux box.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the requirements, existing implementations, and reference patterns you are building on.

**Read first** (the PRDs — your requirements):
- `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-26G-NODE-PACKAGING.md` — Phase 26G spec with deliverables D26G.1–D26G.5, TDD gate T1–T10, completion criteria
- `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md` — Architecture overview, adapter interfaces, node deployment profiles
- `/Users/toddprice/projects/semantos-core/docs/prd/PLATFORM-ARCHITECTURE.md` — **Product context.** The node packaging must support multi-vertical deployment. A PM agency installs both property and trades verticals on their node. `semantos install vertical property` and `semantos install vertical trades` load different config directories. The Docker image and install.sh must handle the multi-operator model described in PLATFORM-ARCHITECTURE.md — each operator gets their own node cert, their own vertical configs, their own pricing policies.

**Read second** (the prior phase PRDs — understand the foundation):
- `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-26F-VERTICAL-LOADING.md` — Vertical config loading from filesystem
- `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-26E-NODE-BOOTSTRAP.md` — NodeConfig, node self-object creation, kernel initialization

**Read third** (the core infrastructure you are deploying):
- `/Users/toddprice/projects/semantos-core/packages/kernel/src/kernel.ts` — Kernel initialization, cell engine entry point, WASM interface
- `/Users/toddprice/projects/semantos-core/protocol-types/src/node.ts` — NodeConfig interface, NodeStatus type, deployment profiles
- `/Users/toddprice/projects/semantos-core/protocol-types/src/adapter-interfaces.ts` — StorageAdapter, IdentityAdapter, AnchorAdapter, NetworkAdapter (reference only)

**Read fourth** (deployment and orchestration patterns):
- `/Users/toddprice/projects/semantos-core/docs/deployment/` — Existing deployment documentation (if any)
- `/Users/toddprice/projects/semantos-core/Dockerfile` — Any existing Docker configuration (reference)
- `/Users/toddprice/projects/semantos-core/docker-compose.yml` — Any existing compose configuration

**Read fifth** (branching policy):
- `/Users/toddprice/projects/semantos-core/docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-26g-node-packaging`. Commits as `phase-26g/D26G.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

Same rules as Phases 25–26F. Plus:

### 1. NO STUBS IN DEPLOYMENT ARTIFACTS

Every shell script, Dockerfile, compose file, and CLI command must be production-ready. If the install.sh script exits with an obscure error or the Docker image doesn't build, you have failed. Test on actual bare metal (or a VM) or in Docker Desktop.

### 2. MUTUAL TLS IS MANDATORY

The admin API on port 6443 MUST use mutual TLS (client certificate authentication). A request without a valid node cert must return 401. This is not optional. Gate test T10 enforces it.

### 3. NO SECRETS IN THE IMAGE

Private keys, API keys, passphrases must NEVER be baked into the Docker image or installer. Use environment variables (SEMANTOS_BYOK_KEY, etc.) or mounted volumes (/etc/semantos mounted from host).

### 4. SYSTEMD SERVICE IS PERMANENT

The semantos.service unit must persist across node restarts, OS upgrades, and package updates. Use proper systemd directives (Restart=on-failure, Type=simple, EnvironmentFile, ExecStart).

### 5. THE CLI MUST WORK OFFLINE

The `semantos` CLI (init, start, stop, status, logs) must work without network access. Commands that require API contact (admin operations) must be explicit and fail gracefully if the node is unreachable.

### 6. DOCUMENTATION IS NOT OPTIONAL

D26G.5 requires four separate deployment guides. Each must include step-by-step instructions, expected output, cost estimates, and troubleshooting. A guide that skips any of these is incomplete.

### 7. NO HARDCODED PATHS

Paths like /etc/semantos, /var/semantos must be configurable or respect standard FHS conventions. Do not hardcode /home/semantos/semantos/ or similar.

### 8. TESTS MUST USE REAL ARTIFACTS

Test the Docker image build on fresh Docker. Test install.sh on a fresh Ubuntu VM (or Docker-based test). Do not mock the build process.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd /Users/toddprice/projects/semantos-core
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`. Discard stale files.

### 0.3 Verify prerequisites are complete

```bash
# Phase 26F and earlier must be complete
ls packages/kernel/src/kernel.ts
ls protocol-types/src/node.ts
ls protocol-types/src/storage.ts
ls protocol-types/src/identity.ts
ls protocol-types/src/anchor.ts
ls protocol-types/src/network.ts
ls packages/node/src/ # Node bootstrap from 26E
```

All files must exist and not be stubbed. If anything is missing, STOP.

### 0.4 Create Phase 26G branch

```bash
git checkout -b phase-26g-node-packaging
```

---

## Step 1: Docker Image (D26G.1)

### 1.1 Create Dockerfile

**New file**: `/Users/toddprice/projects/semantos-core/Dockerfile`

Multi-stage build:
1. Builder stage: Alpine + Zig toolchain, compile kernel to WASM
2. Runtime stage: Minimal Bun image, copy kernel, copy node bootstrap + shell + loom

Reference the Phase 26G PRD (D26G.1) for the exact structure. Key requirements:
- Volume mounts: /var/semantos/data, /etc/semantos, /var/semantos/verticals
- Ports: 3000 (loom UI), 9000 (shard proxy UDP), 6443 (admin API)
- Environment variables: SEMANTOS_MODE, SEMANTOS_BYOK_KEY, SEMANTOS_SUBNET_PREFIX, SEMANTOS_CERT_PATH, SEMANTOS_DEBUG_LOGGING

### 1.2 Create docker-compose.yml

**New file**: `/Users/toddprice/projects/semantos-core/docker-compose.yml`

Services: semantos-node, block-headers-service (sidecar), volumes (semantos-data, semantos-config, block-headers-cache).

Health check: `GET http://localhost:6443/api/node/status` every 30s.

Restart policy: unless-stopped.

### 1.3 Test

```bash
docker build -t semantos:test .
docker-compose up -d
# Wait 30 seconds for health checks
docker-compose logs -f
# Verify: curl http://localhost:3000 (loom UI)
docker-compose down
```

Commit: `phase-26g/D26G.1: Dockerfile + docker-compose.yml multi-stage build with Bun runtime`

---

## Step 2: Bare Metal Installer (D26G.2)

### 2.1 Create install.sh

**New file**: `/Users/toddprice/projects/semantos-core/scripts/install.sh`

Executable (755 permissions).

Steps:
1. Detect OS (Ubuntu 22+, Debian 12+)
2. Detect CPU (x86-64 or ARM64)
3. Install Bun runtime (curl https://bun.sh/install | bash)
4. Create /var/semantos/data, /var/semantos/verticals, /var/semantos/cache
5. Create /etc/semantos with semantos:semantos ownership
6. Interactive prompts (cert path, subnet, OpenRouter key, verticals)
7. Write /etc/semantos/node.json with responses
8. Write /etc/systemd/system/semantos.service
9. Enable and start service (systemctl daemon-reload && systemctl enable semantos && systemctl start semantos)
10. Print success message (loom URL, admin API URL, node BCA, cert ID, log command)

Use trap to handle errors gracefully. Colors in output (green for success, red for error). No sudo required if run as root (typical for fresh VPS provisioning).

### 2.2 Test on Ubuntu VM

Spin up a fresh Ubuntu 22.04 VM (or Docker container with ubuntu:22.04 and systemd), run the installer, verify:
- /var/semantos/data exists with correct permissions
- /etc/semantos/node.json is valid JSON
- semantos.service is registered
- systemctl status semantos shows "active (running)"
- journalctl -u semantos -n 20 shows kernel startup logs

### 2.3 Test on Debian VM

Repeat on Debian 12.

Commit: `phase-26g/D26G.2: install.sh bare metal installer with OS detection and systemd service`

---

## Step 3: semantos CLI (D26G.3)

### 3.1 Create packages/node/src/cli.ts

Main entry point for `semantos` command.

Commands to implement:
- **node lifecycle**: init, start, stop, status, restart, logs (--follow)
- **vertical management**: install vertical <name>, list verticals, uninstall vertical <name>
- **identity management**: identity list, identity create --email <email>, identity export --cert-id <id>, identity revoke --cert-id <id>
- **anchoring**: anchor now, anchor status, anchor history
- **node self-object**: self, self --follow
- **admin operations**: admin --endpoint <url> status, admin --endpoint <url> install-vertical <name>

Each command should:
1. Validate arguments
2. Connect to local node (or remote if --endpoint provided)
3. Execute operation
4. Print formatted output (JSON for --json flag, human-readable by default)
5. Exit with non-zero status on error

Use yargs or a similar CLI parsing library. Store systemd unit location and PID file path as constants.

### 3.2 Wire into package.json

Add bin entry to make `semantos` available globally after npm install -g:
```json
{
  "bin": {
    "semantos": "packages/node/src/cli.ts"
  }
}
```

Or create packages/node/src/bin/semantos.js as a shebang script that requires the module.

### 3.3 Test

```bash
# Assuming node is running
semantos status
semantos list verticals
semantos identity list
semantos anchor status
semantos self

# Install a vertical
semantos install vertical trades

# Stop and start
semantos stop
sleep 2
semantos start
semantos status

# View logs
semantos logs --follow
```

Commit: `phase-26g/D26G.3: semantos CLI with lifecycle, vertical, identity, and anchor commands`

---

## Step 4: Admin API (D26G.4)

### 4.1 Create packages/node/src/api/admin.ts

Express or Fastify HTTP server on port 6443 with mutual TLS.

Endpoints to implement (per D26G.4):
- `GET /api/node/status` → NodeStatus
- `GET /api/node/verticals` → Array of vertical metadata
- `POST /api/node/verticals/install { name, version? }` → { status, progress? }
- `DELETE /api/node/verticals/:name` → { status }
- `POST /api/node/identities { email }` → { certId, publicKey }
- `GET /api/node/identities/:certId` → identity details
- `POST /api/node/identities/:certId/revoke` → { status }
- `POST /api/node/anchor` → trigger immediate anchor; return proof
- `GET /api/node/anchor/interval` → { intervalMs, nextAnchorAt }
- `PUT /api/node/anchor/interval { ms }` → { intervalMs }
- `GET /api/node/anchors` → recent anchor proofs (last 10)
- `GET /api/node/identities` → all identities
- `POST /api/node/shell { prompt }` → { response, objectPath, nextPrompt? }

All endpoints protected by mutual TLS. Only client cert matching the node cert is allowed.

Response envelope for all endpoints:
```typescript
{
  data: T,
  timestamp: number,
  signature?: string,  // optional ECDSA sig
  error?: { code: string; message: string }
}
```

Error responses:
- 401 Unauthorized (no cert or invalid cert)
- 403 Forbidden (cert not authorized)
- 500 Internal Server Error (unexpected failure)

### 4.2 Wire into kernel startup

In `packages/node/src/index.ts` (node bootstrap), after kernel initializes, start the admin API server on port 6443.

### 4.3 Test

Use curl with client cert:
```bash
curl --cert /etc/semantos/node.crt \
     --key /etc/semantos/node.key \
     --cacert /etc/semantos/node.crt \
     https://localhost:6443/api/node/status

# Should return 200 with node status JSON
```

Test without cert:
```bash
curl https://localhost:6443/api/node/status
# Should return 401 Unauthorized
```

Test POST (install vertical):
```bash
curl --cert /etc/semantos/node.crt \
     --key /etc/semantos/node.key \
     --cacert /etc/semantos/node.crt \
     -X POST \
     -H "Content-Type: application/json" \
     -d '{"name":"trades","version":"1.0.0"}' \
     https://localhost:6443/api/node/verticals/install
```

Commit: `phase-26g/D26G.4: Admin API on port 6443 with mutual TLS, all endpoints, node control`

---

## Step 5: Deployment Documentation (D26G.5)

### 5.1 Create docs/deployment/VPS-DEPLOYMENT.md

Step-by-step guide for deploying on DigitalOcean / Vultr / Hetzner.

Include:
- Droplet specs (2GB RAM, 2 vCPU, 50GB SSD, Ubuntu 22.04)
- SSH key setup
- Run install script: `curl -s https://semantos.io/install.sh | bash`
- Answer prompts
- Expected output (loom URL, admin API, node BCA, logs)
- Costs ($10/month cloud, $20/yr Plexus RaaS)
- Monitoring (journalctl -u semantos -f)
- Troubleshooting (common errors and fixes)
- Backup strategy (/var/semantos/data backup frequency)

### 5.2 Create docs/deployment/DOCKER-DEPLOYMENT.md

Step-by-step guide for Docker Compose on local or cloud.

Include:
- Prerequisites (Docker 20.10+, Docker Compose 1.29+)
- Clone repo, copy .env.example to .env
- Customize docker-compose.yml (volumes, ports)
- Run docker-compose up -d
- Verify health: docker-compose ps and docker exec semantos-node semantos status
- Expected output (running services, health checks passing)
- Logs: docker-compose logs -f semantos-node
- Stop/restart: docker-compose down, docker-compose up -d
- Persistence (named volumes)
- Scaling (shard-aware service discovery, optional)

### 5.3 Create docs/deployment/ENTERPRISE-COLO.md

Step-by-step guide for on-prem bare metal deployment.

Include:
- Bare metal provisioning (partner provisions server on campus LAN)
- OS: Ubuntu 22.04 Server, static IP, DNS, time sync
- Network: subnet allocation from enterprise IPAM (e.g., 192.168.100.0/24)
- Cert chain: enterprise root CA, issue node cert, mount at /etc/semantos
- Install: curl https://internal-mirror.corp/install.sh | bash (custom endpoint for on-prem mirror)
- Config: LocalIdentityAdapter (on-prem certs), DirectNetworkAdapter (campus LAN)
- Anchor cycle: 1 min for faster finality (vs 10 min for cloud)
- Audit logging: /var/semantos/audit/ directory for compliance
- Data residency: all data stays on customer hardware (verify no cloud calls)
- Disaster recovery (snapshots, replication strategy)
- Compliance (HIPAA, PCI, SOC2 considerations)

### 5.4 Create docs/deployment/INFRA-PARTNER.md

Step-by-step guide for infrastructure partner model.

Include:
- Partner model: partner provisions bare metal, Semantos provides software + mgmt
- Equinix Metal / Packet / AWS Dedicated Host provisioning
- Partner runs install.sh (same as VPS)
- Partner notifies Semantos of allocated subnet (2602:f9f8:0060:NNNN::/64)
- Semantos registers partner entry in node registry
- Partner's customers rent node slices; Semantos bills partner per customer/month
- BsvAnchorAdapter + DirectNetworkAdapter for hybrid connectivity
- Node manifests as sovereignty RELEVANT object
- Governance flows are partner-scoped (partner controls vertical installs, billing, compliance)
- SLA: uptime target, anchor finality SLA, support escalation

### 5.5 Quality check

Each guide should:
- Have a clear prerequisite section
- Include expected output and screenshots (or ASCII diagrams)
- List common errors and fixes
- Provide cost estimates
- Mention monitoring/observability
- Describe how to access node (loom URL, admin API, CLI commands)

Commit: `phase-26g/D26G.5: Deployment guides for VPS, Docker, Enterprise Colo, and Infra Partner`

---

## Step 6: Gate Tests

### 6.1 Create packages/__tests__/phase26g-gate.test.ts

Implement T1–T10 per the PRD (D26G gate tests):

```typescript
describe("Phase 26G: Node Packaging", () => {
  // T1: Docker build succeeds
  test("T1: Docker image builds without errors", async () => {
    const result = await exec("docker build -t semantos:test .");
    expect(result.exitCode).toBe(0);
  });

  // T2: docker-compose health checks pass
  test("T2: docker-compose services start and pass health checks", async () => {
    await exec("docker-compose up -d");
    await waitForCondition(() => healthCheckPasses(), 30000);
    await exec("docker-compose down");
  });

  // T3: Admin API responds to authenticated request
  test("T3: Admin API returns 200 for GET /api/node/status with valid cert", async () => {
    // Requires running node; make https request with client cert
    const response = await fetch("https://localhost:6443/api/node/status", {
      cert: fs.readFileSync("/etc/semantos/node.crt"),
      key: fs.readFileSync("/etc/semantos/node.key"),
    });
    expect(response.status).toBe(200);
  });

  // T4: install.sh creates required directories on fresh Ubuntu VM
  test("T4: install.sh creates /var/semantos and /etc/semantos", async () => {
    // Run on VM or Docker container
    await exec("bash scripts/install.sh <<< $'\\n\\n\\n'"); // empty prompts
    const hasDataDir = fs.existsSync("/var/semantos/data");
    const hasEtcDir = fs.existsSync("/etc/semantos/node.json");
    expect(hasDataDir && hasEtcDir).toBe(true);
  });

  // T5: systemd service is valid and starts
  test("T5: semantos.service unit is valid and starts without timeout", async () => {
    const result = await exec("systemctl start semantos");
    expect(result.exitCode).toBe(0);
    const status = await exec("systemctl is-active semantos");
    expect(status.stdout.trim()).toBe("active");
  });

  // T6: semantos CLI status command connects and returns status
  test("T6: 'semantos status' CLI command succeeds", async () => {
    const result = await exec("semantos status");
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.certId).toBeDefined();
  });

  // T7: semantos install vertical trades works
  test("T7: 'semantos install vertical trades' activates trades vertical", async () => {
    const result = await exec("semantos install vertical trades");
    expect(result.exitCode).toBe(0);
    const listResult = await exec("semantos list verticals");
    const parsed = JSON.parse(listResult.stdout);
    expect(parsed.find(v => v.name === "trades")).toBeDefined();
  });

  // T8: Manual anchor trigger produces proof
  test("T8: 'semantos anchor now' triggers anchor cycle", async () => {
    const result = await exec("semantos anchor now", { timeout: 15000 });
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.blockHeight).toBeDefined();
    expect(parsed.txId).toBeDefined();
  });

  // T9: Node self-object contains required fields
  test("T9: 'semantos self' returns valid RELEVANT object", async () => {
    const result = await exec("semantos self");
    const obj = JSON.parse(result.stdout);
    expect(obj.linearity).toBe("RELEVANT");
    expect(obj.typeHash).toBe(sha256("sovereignty.node"));
    expect(obj.payload.certId).toBeDefined();
    expect(obj.payload.verticals).toBeInstanceOf(Array);
  });

  // T10: Admin API rejects requests without valid cert
  test("T10: Admin API returns 401 without valid client cert", async () => {
    const response = await fetch("https://localhost:6443/api/node/status");
    expect(response.status).toBe(401);
  });
});
```

### 6.2 Run tests

```bash
bun test packages/__tests__/phase26g-gate.test.ts
```

All 10 tests must pass.

Commit: `phase-26g/T1-T10: Gate test suite for Docker, install, CLI, API, anchor, and verticals`

---

## Step 7: Pre-submission Checklist

Before declaring Phase 26G complete:

- [ ] Dockerfile builds on clean Docker engine: `docker build -t semantos:test .`
- [ ] docker-compose up -d starts without errors; health checks pass within 30s
- [ ] install.sh runs on fresh Ubuntu 22 VM or container; creates all directories
- [ ] semantos.service unit is valid; `systemctl start semantos` succeeds
- [ ] semantos CLI: all commands (status, start, stop, install vertical, anchor now, self, logs) work
- [ ] Admin API on port 6443: GET /api/node/status returns 200 with valid cert, 401 without
- [ ] Deployment docs: VPS, Docker, Colo, Partner (all four complete with expected output, costs, troubleshooting)
- [ ] Tests T1–T10 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] No prior phase tests regressed (Phase 25A–D, Phase 26A–F still pass)
- [ ] All commits follow `phase-26g/D26G.N:` naming
- [ ] Branch is `phase-26g-node-packaging`

---

## Step 8: Final Integration

Push to origin (do NOT merge to main until Phase 27 integration):

```bash
git push -u origin phase-26g-node-packaging
```

Create a draft PR (GitHub CLI):

```bash
gh pr create --title "Phase 26G: Node Packaging & Deployment" \
  --body "Dockerfile, install.sh, semantos CLI, admin API, deployment guides" \
  --draft
```

---

## Completion Criteria

- [ ] All D26G.1–D26G.5 deliverables exist and are non-trivial
- [ ] Docker image builds; docker-compose up succeeds
- [ ] install.sh is executable, detects OS, creates systemd unit
- [ ] semantos CLI implements all commands (init, start, stop, status, install vertical, anchor now, etc.)
- [ ] Admin API on 6443 is protected by mutual TLS
- [ ] Deployment docs for VPS, Docker, Colo, Partner (all four complete)
- [ ] Tests T1–T10 pass
- [ ] `bun run check` and `bun run build` succeed
- [ ] No regressions (Phase 25A–D, Phase 26A–F tests still pass)
- [ ] All commits follow phase-26g/D26G.N: naming
- [ ] Branch is phase-26g-node-packaging

---

## Next Phase

Phase 27 deploys the first production tradie node (VPS) and the first enterprise demo node (Colo). Phase 28 integrates the Flutter mobile shell as the primary admin UI for tradie daily operations.
