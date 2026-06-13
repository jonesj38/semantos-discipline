---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30J-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.701994+00:00
---

# Phase 30J Execution Prompt — Docker Multi-Arch Image & Node Bootstrap

> Paste this prompt into a fresh session to execute Phase 30J.

## Context

### Key Rule

The Docker image is NOT a wrapper around a dev environment. It is a production deployment artifact. Minimal base image (scratch or distroless), no shell, no package manager, no debug tools. The Zig binary is statically linked — the image contains exactly one binary plus config files.

---

## CRITICAL: READ THESE FILES FIRST

1. `docs/prd/PHASE-30J-DOCKER-MULTIARCH.md` — Phase 30J specification
2. `docs/prd/PHASE-30-FFI-MASTER.md` — Docker target, deployment profiles
3. `docs/prd/PHASE-26E-NODE-BOOTSTRAP.md` — NodeConfig, createNode()
4. `docs/prd/PHASE-26G-NODE-PACKAGING.md` — Docker packaging pattern
5. `docs/BRANCHING-AND-CI-POLICY.md` — Commit naming

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

1. **NO STUBS** — Every function must have real implementation
2. **STATIC BINARY** — No dynamic linking, no libc dependency at runtime
3. **MINIMAL IMAGE** — scratch or distroless base; no shell, no package manager
4. **GRACEFUL SHUTDOWN** — Flush anchors, close connections, exit cleanly
5. **MULTI-ARCH IS MANDATORY** — Both amd64 and arm64; no single-arch cop-outs
6. **NODE BOOTSTRAP IS REAL** — `createNode()` with NodeConfig, not a mock
7. **HEALTH CHECK IS MANDATORY** — Not optional; /health endpoint required
8. **NO EASY TESTS** — Tests must exercise actual Docker containers and APIs

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
git status -u
git log --oneline -10
git branch -a
```

Expected state: clean working tree, on main, Phase 30D and Phase 26E complete.

### 0.2 Commit or discard

If working tree is dirty:
- Stage explicitly: `git add src/... Dockerfile ...`
- Never use `git add -A`
- Commit: `git commit -m "..."`
- Or discard: `git checkout -- <files>`

Verify: `git status` shows "nothing to commit, working tree clean"

### 0.3 Verify prerequisites

All of these must exist and be complete:

```bash
ls docs/prd/PHASE-30D-ANCHOR-FFI.md  # Phase 30D complete
ls docs/prd/PHASE-26E-NODE-BOOTSTRAP.md  # Phase 26E complete
ls src/ffi/  # FFI implementation directory
ls build.zig  # Build system
zig build test  # Gate tests pass
```

If any prerequisite is missing, **STOP**. Do not proceed.

### 0.4 Create branch

```bash
git checkout -b phase-30j-docker-multiarch
git push -u origin phase-30j-docker-multiarch
```

---

## Step 1: Server Binary Build Targets — D30J.1

**Commit message**: `phase-30j/D30J.1: Server binary build for x86_64-linux and aarch64-linux`

Update `build.zig` to add server build targets:

```zig
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build step: server for amd64
    const server_amd64 = b.step("build-server-amd64", "Build server for x86_64-linux");
    const exe_amd64 = b.addExecutable(.{
        .name = "semantos-server",
        .root_source_file = b.path("src/server/main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
        }),
        .optimize = .ReleaseFast,
    });

    // Link adapters
    exe_amd64.linkLibrary(fs_adapter);
    exe_amd64.linkLibrary(anchor_adapter);
    exe_amd64.linkLibrary(network_adapter);

    // Static linking
    exe_amd64.link_libc = true;
    exe_amd64.root_module.linkage = .static;

    // Install to build/
    b.installArtifact(exe_amd64);
    server_amd64.dependOn(&exe_amd64.step);

    // Build step: server for arm64
    const server_arm64 = b.step("build-server-arm64", "Build server for aarch64-linux");
    const exe_arm64 = b.addExecutable(.{
        .name = "semantos-server",
        .root_source_file = b.path("src/server/main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .aarch64,
            .os_tag = .linux,
        }),
        .optimize = .ReleaseFast,
    });

    exe_arm64.linkLibrary(fs_adapter);
    exe_arm64.linkLibrary(anchor_adapter);
    exe_arm64.linkLibrary(network_adapter);

    exe_arm64.link_libc = true;
    exe_arm64.root_module.linkage = .static;

    b.installArtifact(exe_arm64);
    server_arm64.dependOn(&exe_arm64.step);
}
```

Create `src/server/main.zig`:

```zig
const std = @import("std");
const semantos = @import("semantos");
const NodeConfig = @import("node_config.zig").NodeConfig;
const NodeFsAdapter = @import("adapters/fs.zig").NodeFsAdapter;
const BsvAnchorAdapter = @import("adapters/anchor.zig").BsvAnchorAdapter;
const BsvOverlayNetworkAdapter = @import("adapters/network.zig").BsvOverlayNetworkAdapter;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Read NodeConfig from /etc/semantos/node.json
    const config_file = std.fs.cwd().openFile(
        "/etc/semantos/node.json",
        .{},
    ) catch |err| {
        std.debug.print("Error opening config: {}\n", .{err});
        return err;
    };
    defer config_file.close();

    const config_json = try config_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(config_json);

    const node_config = try NodeConfig.fromJson(config_json, allocator);
    defer node_config.deinit();

    // 2. Initialize adapters
    const fs_adapter = try NodeFsAdapter.init(node_config.data_dir, allocator);
    defer fs_adapter.deinit();

    const anchor_adapter = try BsvAnchorAdapter.init(node_config.anchor_endpoint, allocator);
    defer anchor_adapter.deinit();

    const network_adapter = try BsvOverlayNetworkAdapter.init(
        node_config.overlay_seed_peers,
        allocator,
    );
    defer network_adapter.deinit();

    // 3. Create node
    const node = try semantos.createNode(
        node_config,
        fs_adapter,
        anchor_adapter,
        network_adapter,
        allocator,
    );
    defer node.deinit();

    // 4. Create self-object
    try node.createSelfObject(node_config.node_id);

    // 5. Start admin API
    const admin_api = try AdminApi.init(node, node_config.admin_api_port, allocator);
    defer admin_api.deinit();
    try admin_api.start();

    // 6. Start P2P listener
    try network_adapter.startListener(node_config.p2p_port);

    // 7. Start anchor scheduler
    const anchor_scheduler = try AnchorScheduler.init(node, anchor_adapter);
    defer anchor_scheduler.deinit();
    try anchor_scheduler.start();

    std.debug.print("Node {} started\n", .{node_config.node_id});

    // Block until shutdown
    try node.waitForShutdown();

    // Graceful shutdown
    std.debug.print("Shutting down...\n", .{});
    try anchor_scheduler.flush();
    try network_adapter.closeConnections();
    try fs_adapter.close();
}
```

Create `src/server/node_config.zig`:

```zig
pub const NodeConfig = struct {
    node_id: []const u8,
    anchor_endpoint: []const u8,
    overlay_seed_peers: [][]const u8,
    admin_api_port: u16,
    p2p_port: u16,
    data_dir: []const u8,

    pub fn fromJson(json: []const u8, allocator: std.mem.Allocator) !NodeConfig {
        // Parse JSON and return NodeConfig
        // Use std.json or similar
    }

    pub fn deinit(self: *NodeConfig) void {
        // Free allocated memory
    }
};
```

Create default config: `config/default-node.json`:

```json
{
    "node_id": "default-node",
    "anchor_endpoint": "https://mainnet.bitcoinsv.io",
    "overlay_seed_peers": [
        "seed-a.semantos.io:9000",
        "seed-b.semantos.io:9000"
    ],
    "admin_api_port": 8080,
    "p2p_port": 9000,
    "data_dir": "/var/semantos"
}
```

**Test** (T1, T2):

```bash
zig build build-server-amd64
file zig-cache/o/*/semantos-server  # Verify ELF, x86_64
ldd zig-cache/o/*/semantos-server  # Should show "not a dynamic executable" or similar

zig build build-server-arm64
file zig-cache/o/*/semantos-server  # Verify ELF, aarch64
```

Commit and push.

---

## Step 2: Dockerfile Multi-Stage Build — D30J.2

**Commit message**: `phase-30j/D30J.2: Multi-stage Dockerfile for minimal production image`

Create `Dockerfile`:

```dockerfile
# Stage 1: Build
FROM ubuntu:22.04 as builder

RUN apt-get update && apt-get install -y \
    zig \
    clang \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY . .

ARG TARGET=x86_64-linux
RUN zig build build-server-${TARGET%-linux}

# Stage 2: Runtime
FROM scratch

# Copy binary from builder
COPY --from=builder /build/zig-cache/o/*/semantos-server /bin/semantos-server
# Copy default config
COPY --from=builder /build/config/default-node.json /etc/semantos/node.json

# Expose admin API and P2P ports
EXPOSE 8080 9000

# Volumes
VOLUME ["/var/semantos", "/etc/semantos"]

# Entrypoint
ENTRYPOINT ["/bin/semantos-server"]
```

**Test** (T3):

```bash
docker build -t semantos:test-amd64 \
  --build-arg TARGET=x86_64-linux \
  -f Dockerfile .

docker build -t semantos:test-arm64 \
  --build-arg TARGET=aarch64-linux \
  -f Dockerfile .

docker images | grep semantos
# Verify image size < 50MB
```

Commit and push.

---

## Step 3: Health Check Endpoint — D30J.5

**Commit message**: `phase-30j/D30J.5: Health check endpoint /health`

Create `src/server/admin_api.zig`:

```zig
pub const AdminApi = struct {
    node: *Node,
    port: u16,
    allocator: std.mem.Allocator,
    server: ?*http.Server,

    pub fn init(node: *Node, port: u16, allocator: std.mem.Allocator) !AdminApi {
        return .{
            .node = node,
            .port = port,
            .allocator = allocator,
            .server = null,
        };
    }

    pub fn start(self: *AdminApi) !void {
        // Start HTTP server on self.port
        // Register routes:
        //   GET /health -> handleHealth
        //   GET /cell/{id} -> handleGetCell
        //   POST /cell -> handlePostCell
    }

    fn handleHealth(self: *AdminApi, allocator: std.mem.Allocator) ![]u8 {
        const version = "1.0.0";
        const adapters = .{
            .fs = self.node.fs_adapter.isReady(),
            .anchor = self.node.anchor_adapter.isConnected(),
            .network = self.node.network_adapter.isListening(),
        };
        const queue_depth = try self.node.getQueueDepth();

        return try std.fmt.allocPrint(allocator,
            \\{{
            \\  "status": "healthy",
            \\  "version": "{}",
            \\  "adapters": {{ "fs": {}, "anchor": {}, "network": {} }},
            \\  "queue_depth": {}
            \\}}
        , .{ version, adapters.fs, adapters.anchor, adapters.network, queue_depth });
    }

    pub fn deinit(self: *AdminApi) void {
        if (self.server) |server| {
            server.deinit();
        }
    }
};
```

Update `Dockerfile` to add HEALTHCHECK:

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD ["/bin/semantos-server", "--health-check"]
```

Or use curl if libc available in runtime:

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD curl -f http://localhost:8080/health || exit 1
```

**Test** (T4):

```bash
docker run -d --name test-node semantos:test-amd64
sleep 3
docker exec test-node curl -s http://localhost:8080/health | jq .
# Expected: { "status": "healthy", "version": "1.0.0", ... }
docker stop test-node
```

Commit and push.

---

## Step 4: Admin API Cell Operations — D30J.6

**Commit message**: `phase-30j/D30J.6: Admin API cell read/write endpoints`

Extend `src/server/admin_api.zig`:

```zig
fn handleGetCell(self: *AdminApi, object_id: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const cell = self.node.getCell(object_id) catch |err| {
        return try std.fmt.allocPrint(allocator, "{{ \"error\": \"{}\" }}", .{err});
    };

    return try std.fmt.allocPrint(allocator,
        \\{{ "object_id": "{}", "data": "{}" }}
    , .{ object_id, cell.data });
}

fn handlePostCell(self: *AdminApi, body: []const u8, allocator: std.mem.Allocator) ![]u8 {
    // Parse JSON: { "object_id": "...", "data": "..." }
    const object_id = try extractJsonString(body, "object_id", allocator);
    const data = try extractJsonString(body, "data", allocator);

    try self.node.setCell(object_id, data);

    return try std.fmt.allocPrint(allocator, "{{ \"ok\": true }}", .{});
}
```

**Test** (T5):

```bash
docker run -d --name test-node -p 8080:8080 semantos:test-amd64
sleep 3

# Write cell
curl -X POST http://localhost:8080/cell \
  -H "Content-Type: application/json" \
  -d '{"object_id": "test-cell", "data": "hello"}'
# Expected: { "ok": true }

# Read cell
curl http://localhost:8080/cell/test-cell
# Expected: { "object_id": "test-cell", "data": "hello" }

docker stop test-node
```

Commit and push.

---

## Step 5: Graceful Shutdown — D30J.6

**Commit message**: `phase-30j/D30J.6: Graceful shutdown with anchor flush`

Update `src/server/main.zig`:

```zig
pub fn main() !void {
    // ... setup code ...

    // Register signal handler
    var sigaction = std.os.Sigaction{
        .handler = .{ .sigaction = handleShutdown },
        .mask = std.os.empty_sigset,
        .flags = 0,
    };
    try std.os.sigaction(std.os.SIGTERM, &sigaction, null);
    try std.os.sigaction(std.os.SIGINT, &sigaction, null);

    std.debug.print("Node {} started\n", .{node_config.node_id});

    // Block
    try node.waitForShutdown();

    // Graceful shutdown
    std.debug.print("Shutting down...\n", .{});

    // Flush pending anchors
    try anchor_scheduler.flush();
    std.debug.print("Anchors flushed\n", .{});

    // Close network connections
    try network_adapter.closeConnections();
    std.debug.print("Network connections closed\n", .{});

    // Close file handles
    try fs_adapter.close();
    std.debug.print("Filesystem adapter closed\n", .{});

    std.debug.print("Shutdown complete\n", .{});
}
```

**Test** (T6):

```bash
docker run -d --name test-node semantos:test-amd64
sleep 2
docker stop test-node
docker logs test-node | grep -i "shutdown"
# Expected: "Shutting down...", "Anchors flushed", "Shutdown complete"
```

Commit and push.

---

## Step 6: Multi-Arch Manifest — D30J.3

**Commit message**: `phase-30j/D30J.3: Multi-arch Docker manifest`

Create `scripts/build-docker-multiarch.sh`:

```bash
#!/bin/bash
set -e

echo "Building amd64 image..."
docker build -t ghcr.io/semantos/kernel:latest-amd64 \
  --build-arg TARGET=x86_64-linux \
  -f Dockerfile .

echo "Building arm64 image..."
docker build -t ghcr.io/semantos/kernel:latest-arm64 \
  --build-arg TARGET=aarch64-linux \
  -f Dockerfile .

echo "Creating multi-arch manifest..."
docker manifest create ghcr.io/semantos/kernel:latest \
  ghcr.io/semantos/kernel:latest-amd64 \
  ghcr.io/semantos/kernel:latest-arm64

echo "Pushing manifest..."
docker manifest push ghcr.io/semantos/kernel:latest

echo "Done!"
```

**Test** (T7):

```bash
chmod +x scripts/build-docker-multiarch.sh
./scripts/build-docker-multiarch.sh

docker manifest inspect ghcr.io/semantos/kernel:latest
# Verify manifests list both amd64 and arm64
```

Commit and push.

---

## Step 7: Integration Tests — D30J.6

**Commit message**: `phase-30j/D30J.6: Docker integration tests`

Create `tests/docker_integration_test.sh`:

```bash
#!/bin/bash
set -e

echo "Test 1: Container startup and health check"
docker run -d --name test-node -p 8080:8080 semantos:test-amd64
sleep 3
response=$(curl -s http://localhost:8080/health)
echo "$response" | jq .
if ! echo "$response" | jq -e '.status == "healthy"' > /dev/null; then
    echo "FAIL: Health check did not return healthy"
    exit 1
fi
docker stop test-node
docker rm test-node

echo "Test 2: Cell write/read"
docker run -d --name test-node -p 8080:8080 semantos:test-amd64
sleep 3
curl -s -X POST http://localhost:8080/cell \
  -H "Content-Type: application/json" \
  -d '{"object_id": "test", "data": "value"}'
response=$(curl -s http://localhost:8080/cell/test)
if ! echo "$response" | jq -e '.data == "value"' > /dev/null; then
    echo "FAIL: Cell read returned unexpected data"
    exit 1
fi
docker stop test-node
docker rm test-node

echo "Test 3: Graceful shutdown"
docker run -d --name test-node semantos:test-amd64
sleep 2
docker stop test-node
logs=$(docker logs test-node 2>&1)
if ! echo "$logs" | grep -q "Shutdown"; then
    echo "FAIL: Graceful shutdown not logged"
    exit 1
fi
docker rm test-node

echo "Test 4: Multi-arch (both amd64 and arm64 boot)"
docker run --rm --platform linux/amd64 semantos:test-amd64 echo "amd64 OK"
docker run --rm --platform linux/arm64 semantos:test-arm64 echo "arm64 OK"

echo "All tests passed!"
```

**Test** (T8, T9, T10):

```bash
# Check image size
docker images semantos:test-amd64 --format "{{.Size}}"
# Must be < 50MB

# Verify no shell
docker run --rm semantos:test-amd64 /bin/sh 2>&1 || echo "OK: No shell found"

# Run integration tests
chmod +x tests/docker_integration_test.sh
./tests/docker_integration_test.sh
```

Commit and push.

---

## Completion Criteria

- Server binaries build for both x86_64-linux and aarch64-linux
- Both binaries are statically linked (ldd shows "not a dynamic executable")
- Dockerfile builds minimal images for both architectures
- Multi-arch manifest works and resolves correctly
- Container starts, health endpoint responds with correct JSON
- Cell write/read works through admin API
- Graceful shutdown logs anchor flush, connection close, filesystem close
- All TDD gate tests passing (T1-T10)
- Image size < 50MB
- No shell or package manager in final image
- Node bootstrap initializes with configured adapters (fs, anchor, network)
