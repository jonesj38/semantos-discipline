---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30J-DOCKER-MULTIARCH.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.663963+00:00
---

# Phase 30J — Docker Multi-Arch Image & Node Bootstrap

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 3-4 days
**Prerequisites**: Phase 30D complete (anchor FFI), Phase 26E complete (NodeConfig/createNode)
**Master document**: `PHASE-30-FFI-MASTER.md`
**Branch**: `phase-30j-docker-multiarch`

---

## Context

### The Docker Rule

The Docker image is NOT a wrapper around a dev environment. It is a production deployment artifact. Minimal base image (scratch or distroless), no shell, no package manager, no debug tools. The Zig binary is statically linked — the image contains exactly one binary plus config files.

For server deployments, the Zig kernel compiles as a native binary linked against Zig-native adapter implementations (NodeFsAdapter, BsvOverlayNetworkAdapter, BsvAnchorAdapter). The Docker image packages this binary plus the conversational shell, vertical/extension config loader, and anchor scheduler. Multi-arch images (linux/amd64, linux/arm64) built via Zig cross-compilation — no Docker buildx emulation required.

---

## Source Files / References

| Alias | Path | What to extract |
|-------|------|-----------------|
| `MASTER-FFI` | `docs/prd/PHASE-30-FFI-MASTER.md` | Docker target, deployment profiles |
| `PHASE-26E` | `docs/prd/PHASE-26E-NODE-BOOTSTRAP.md` | NodeConfig, createNode(), self-object |
| `PHASE-26G` | `docs/prd/PHASE-26G-NODE-PACKAGING.md` | Docker packaging pattern, install.sh |
| `POLICY-BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming |

---

## Deliverables

### D30J.1 — Server binary build

In `build.zig` or `scripts/build-server.sh`:

Compile kernel for linux/amd64 and linux/arm64 as static binaries. Link against Zig-native adapter implementations:
- **NodeFsAdapter** — filesystem storage (for persistent data, queue, config)
- **BsvAnchorAdapter** — real anchoring to BSV blockchain
- **BsvOverlayNetworkAdapter** — P2P overlay network for synchronisation

Build targets:

```zig
// build.zig
pub fn build(b: *std.Build) !void {
    // Target 1: x86_64-linux
    const x64_step = b.step("build-server-amd64", "Build server for x86_64-linux");
    const x64_exe = b.addExecutable(.{
        .name = "semantos-server",
        .root_source_file = b.path("src/server/main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
        }),
        .optimize = .ReleaseFast,
    });
    // Link against adapters
    x64_exe.linkLibrary(node_fs_adapter);
    x64_exe.linkLibrary(bsv_anchor_adapter);
    x64_exe.linkLibrary(bsv_overlay_network_adapter);
    // Static linking
    x64_exe.link_libc = true;
    x64_exe.root_module.linkage = .static;

    // Target 2: aarch64-linux
    const arm64_step = b.step("build-server-arm64", "Build server for aarch64-linux");
    const arm64_exe = b.addExecutable(.{
        .name = "semantos-server",
        .root_source_file = b.path("src/server/main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .aarch64,
            .os_tag = .linux,
        }),
        .optimize = .ReleaseFast,
    });
    // Link same adapters
    arm64_exe.linkLibrary(node_fs_adapter);
    arm64_exe.linkLibrary(bsv_anchor_adapter);
    arm64_exe.linkLibrary(bsv_overlay_network_adapter);
    arm64_exe.link_libc = true;
    arm64_exe.root_module.linkage = .static;
}
```

Output binaries:
- `build/semantos-server` (x86_64)
- `build/semantos-server-arm64` (aarch64)

Both statically linked, no dynamic library dependencies.

### D30J.2 — Dockerfile

New file: `Dockerfile`

Multi-stage build with minimal final image:

```dockerfile
# Stage 1: Build
FROM ubuntu:22.04 as builder

RUN apt-get update && apt-get install -y \
    zig \
    clang \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY . .

ARG TARGET=x86_64-linux
RUN zig build build-server-${TARGET%-linux}

# Stage 2: Runtime
FROM scratch

COPY --from=builder /build/build/semantos-server /bin/semantos-server
COPY --from=builder /build/config/default-node.json /etc/semantos/node.json

EXPOSE 8080 9000
VOLUME ["/var/semantos", "/etc/semantos"]

ENTRYPOINT ["/bin/semantos-server"]
```

Configuration:

- **Base image**: `scratch` or `distroless:base` (no shell, no package manager)
- **Binary**: Single statically-linked ELF binary
- **Config**: Default `/etc/semantos/node.json` (NodeConfig)
- **Volumes**: `/var/semantos` (data), `/etc/semantos` (config)
- **Ports**: 8080 (admin API), 9000 (P2P)
- **Entrypoint**: `/bin/semantos-server` with no arguments

Image size target: **< 50MB** (static binary + minimal base).

### D30J.3 — Multi-arch manifest

Script: `scripts/build-docker-multiarch.sh` or CI step

Create multi-architecture Docker images:

```bash
#!/bin/bash

# Build amd64 image
docker build -t ghcr.io/semantos/kernel:latest-amd64 \
  --build-arg TARGET=x86_64-linux \
  -f Dockerfile .

# Build arm64 image
docker build -t ghcr.io/semantos/kernel:latest-arm64 \
  --build-arg TARGET=aarch64-linux \
  -f Dockerfile .

# Create multi-arch manifest
docker manifest create ghcr.io/semantos/kernel:latest \
  ghcr.io/semantos/kernel:latest-amd64 \
  ghcr.io/semantos/kernel:latest-arm64

# Push manifest
docker manifest push ghcr.io/semantos/kernel:latest
```

Result:
- `ghcr.io/semantos/kernel:latest` → resolves to amd64 or arm64 depending on host
- `ghcr.io/semantos/kernel:latest-amd64` → explicit amd64 image
- `ghcr.io/semantos/kernel:latest-arm64` → explicit arm64 image

No emulation required; Zig cross-compilation produces native binaries for each arch.

### D30J.4 — Node bootstrap integration

Wire Docker entry point into Phase 26E's `createNode()` / `NodeConfig`.

Server binary (`src/server/main.zig`):

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Read NodeConfig from /etc/semantos/node.json
    const config_file = try std.fs.cwd().openFile(
        "/etc/semantos/node.json",
        .{},
    );
    defer config_file.close();
    const config_json = try config_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(config_json);

    const node_config = try NodeConfig.fromJson(config_json);
    defer node_config.deinit();

    // 2. Initialize adapters
    const fs_adapter = try NodeFsAdapter.init("/var/semantos", allocator);
    defer fs_adapter.deinit();

    const anchor_adapter = try BsvAnchorAdapter.init(node_config.anchor_endpoint);
    defer anchor_adapter.deinit();

    const network_adapter = try BsvOverlayNetworkAdapter.init(
        node_config.overlay_seed_peers,
        allocator,
    );
    defer network_adapter.deinit();

    // 3. Create node (initialise kernel with configured adapters)
    const node = try createNode(
        node_config,
        fs_adapter,
        anchor_adapter,
        network_adapter,
    );
    defer node.deinit();

    // 4. Create self-object (node as semantic object)
    try node.createSelfObject(node_config.node_id);

    // 5. Start admin API listener
    const admin_api = try AdminApi.init(node, 8080, allocator);
    defer admin_api.deinit();

    try admin_api.start();

    // 6. Start P2P listeners
    try network_adapter.startListener(9000);

    // 7. Start anchor scheduler
    const anchor_scheduler = try AnchorScheduler.init(node, anchor_adapter);
    defer anchor_scheduler.deinit();

    try anchor_scheduler.start();

    // Block until shutdown
    std.debug.print("Node {} started\n", .{node_config.node_id});
    try node.waitForShutdown();
}
```

NodeConfig structure (JSON):

```json
{
    "node_id": "node-001",
    "anchor_endpoint": "https://mainnet.bitcoinsv.io",
    "overlay_seed_peers": ["peer-a.semantos.io:9000", "peer-b.semantos.io:9000"],
    "admin_api_port": 8080,
    "p2p_port": 9000,
    "data_dir": "/var/semantos"
}
```

Default config: `config/default-node.json` (packaged in image).

### D30J.5 — Health check & readiness

Implement health endpoint (HTTP GET `/health`):

```zig
pub fn handleHealth(allocator: std.mem.Allocator, node: *Node) ![]u8 {
    const version = "1.0.0"; // semver
    const adapter_status = .{
        .fs = node.fs_adapter.isReady(),
        .anchor = node.anchor_adapter.isConnected(),
        .network = node.network_adapter.isListening(),
    };
    const queue_depth = try node.getQueueDepth();

    const response = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "status": "healthy",
        \\  "version": "{}",
        \\  "adapters": {{}},
        \\  "queue_depth": {}
        \\}}
    , .{ version, adapter_status, queue_depth });

    return response;
}
```

Docker `HEALTHCHECK` instruction:

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD ["/bin/semantos-server", "--health-check"]
```

Or expose as admin API endpoint:

```bash
curl http://localhost:8080/health
# Returns:
# {
#   "status": "healthy",
#   "version": "1.0.0",
#   "adapters": { "fs": true, "anchor": true, "network": true },
#   "queue_depth": 0
# }
```

### D30J.6 — Docker integration tests

New file: `tests/docker_integration_test.zig` or shell script:

Test scenarios:

1. **Container startup**:
   ```bash
   docker run -d --name test-node semantos:latest
   sleep 2
   docker exec test-node curl http://localhost:8080/health
   # Expected: 200, JSON response with "status": "healthy"
   ```

2. **Cell write/read via admin API**:
   ```bash
   docker run -d --name test-node -p 8080:8080 semantos:latest
   curl -X POST http://localhost:8080/cell \
     -d '{"object_id": "test", "data": "value"}'
   curl http://localhost:8080/cell/test
   # Expected: 200, cell data
   ```

3. **Graceful shutdown**:
   ```bash
   docker run -d --name test-node semantos:latest
   docker stop test-node
   # Verify: server flushes pending anchors, closes connections cleanly
   docker logs test-node | grep -i shutdown
   ```

4. **Multi-arch test** (verify both images boot):
   ```bash
   docker run --rm --platform linux/amd64 semantos:latest ./health
   docker run --rm --platform linux/arm64 semantos:latest ./health
   # Both should return version successfully
   ```

5. **Volume persistence**:
   ```bash
   docker run -d -v data:/var/semantos --name test-node semantos:latest
   # Write data
   docker stop test-node
   docker run -d -v data:/var/semantos --name test-node-2 semantos:latest
   # Read data (should persist)
   ```

---

## TDD Gate Tests

- **T1**: `zig build build-server-amd64` produces statically-linked x86_64 ELF binary
- **T2**: `zig build build-server-arm64` produces statically-linked aarch64 ELF binary
- **T3**: Docker build succeeds for both architectures (TARGET=x86_64-linux, TARGET=aarch64-linux)
- **T4**: Container starts and `GET /health` returns 200 with version + adapter status
- **T5**: Cell write/read works through container's admin API (POST/GET /cell)
- **T6**: Container shutdown flushes pending anchors and closes connections gracefully
- **T7**: Multi-arch manifest resolves correctly (`docker run` picks right image)
- **T8**: Image size < 50MB (verify with `docker images`)
- **T9**: No shell, no package manager in final image (verify: `docker run ... /bin/sh` fails)
- **T10**: Node self-object created on bootstrap (verify: query node via API)

---

## Completion Criteria

- Both server binaries build successfully and are statically linked
- Dockerfile builds minimal images for both architectures
- Multi-arch manifest works correctly
- Container starts, health endpoint responds, admin API works
- Node bootstrap initializes with configured adapters
- Graceful shutdown flushes pending operations
- All TDD gate tests passing
- Image size < 50MB
- No shell or package manager in final image
