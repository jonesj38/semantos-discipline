---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/demo/MNCA-MESH-DEMO.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.748380+00:00
---

# Live MNCA-on-mesh + on-chain + visualization demo

Autonomous build (overnight /loop). Goal: the MNCA cellular automaton running
distributed across the Pi mesh (each node owns a tile, steps it, multicasts the
result), rendered live in the browser, with periodic on-chain anchoring.

**SAFETY:** the build never broadcasts a real mainnet transaction. On-chain
anchoring is BUILD + DRY-RUN only; the live broadcast stays gated on the
operator via the browser wallet. No private keys are printed or committed.

## Status (slices)

- [x] **1. Mesh node steps + multicasts its MNCA tile.**
  `runtime/semantos-brain/tools/mesh-node/main.zig` — each node seeds an MNCA
  tile (deterministic from its cellId), steps the interior every `--tile-ms`,
  and broadcasts the 768-byte tile payload as a `cell_sync`. Tile coord is
  `--tile-x/--tile-y`, side `--tile-side` (default 18, halo 3 → 12×12 interior).
  Tests: `zig build test-udp` (runtime/semantos-brain). `--tile-ms 0` = off
  (default), so existing gossip behaviour is unchanged.

- [x] **2. Mac bridge → SSE.** `docs/demo/mesh-bridge.ts` — joins the IPv6
  multicast group (`MCAST_GROUP`/`MCAST_PORT`/`MCAST_IFACE`), decodes cell_sync
  tile broadcasts, keeps the latest tile per (x,y), serves `GET /tiles` (JSON)
  and `GET /events` (SSE) on `BRIDGE_PORT` (4400), CORS-open. Read-only observer
  (no HMAC verify — trusted-loopback demo). Decode verified against synthetic
  datagrams. `bun docs/demo/mesh-bridge.ts`.

- [x] **3. Webview consumes the live bridge SSE** (falls back to local sim).
  `docs/demo/mnca-grid.html` + `docs/demo/mnca-grid.js` (built from
  `core/protocol-types/src/mnca/grid-viz.ts`). On load, tries SSE at
  `http://localhost:4400/events`. When tiles arrive, switches from local
  simulation to a composite N×M live-mesh grid (one tile per (tileX,tileY)
  coord; cell interiors rendered at `CELL_PX=16`). Falls back after 2.5 s if
  bridge unreachable. Bridge status badge: `● live mesh · N tiles` / `○ local sim`.

- [x] **4. Local run harness.** `docs/demo/run-local-mesh.ts` — generates N fresh
  node configs (loopback=true), spawns N `mesh-node` processes arranged in a
  `ceil(√N) × ⌈N/cols⌉` tile grid, launches `mesh-bridge.ts` (:4400),
  `serve.ts` (:4321), and the snapshot anchor service (:4401). Polls
  `/tiles` on startup; once tiles are flowing prints the ready URL. Verified:
  4 nodes produce a live 2×2 MNCA grid. macOS loopback: `--iface lo0`.

- [x] **5. On-chain snapshot anchoring** (proven pushdrop), dry-run, WoC links
  in viz. `docs/demo/mesh-snapshot-anchor.ts` — reads tiles from bridge every
  30 s, packs a 1024-byte `mnca.snapshot.grid` cell (version, typeHash, tile
  metadata + interior cells), builds a pushdrop anchor tx via `mesh-bsv-sink.ts`
  (throwaway key, synthetic UTXO — DRY-RUN only, no broadcast). Serves
  `GET /anchor-preview` on :4401. `mnca-grid.html` polls for it and surfaces the
  preview txid + WoC link. Broadcast is operator-gated via `wallet.html`.

- [x] **D-SRS-sns-multicast-wire: type-derived multicast groups (Phase 34A SNS).**
  `core/protocol-types/src/mnca/srv6.ts` — implements `deriveMulticastGroup` per
  Phase 34A: `ff15:WHAT[0:4]:HOW[0:4]:INST[0:4]:0000` where each prefix is the
  first 4 bytes of SHA-256(`"what."+path`, `"how."+slug`, `"inst."+path`). MNCA
  type axes declared in `MNCA_TYPE_AXES`; pinned known-answer table in
  `MNCA_MULTICAST_GROUPS`. The local mesh harness (`run-local-mesh.ts`) now writes
  the SNS-derived group into every node config — mesh-nodes join the type-derived
  group (`ff15:4ed1:aabd:873d:e970:0000:0000:0000` for `mnca.tile.tick`) rather
  than the legacy hand-assigned `ff15::5e:1`. 32 conformance tests pass.
  **Pi mesh (Skyminer) upgraded 2026-05-23** — all 6 active Pis patched via SSH
  (`mesh.json` `multicast.group` updated, `mesh-node` restarted); 6/6 tiles
  confirmed flowing on the SNS group. `run-real-mesh.ts` requires no flags
  (legacy `--multitenant` guard remains for the `--iface` default path).

- [x] **D-SRS-tenant-gateway: bidirectional loopback↔LAN multicast relay.**
  `docs/demo/mesh-tenant-gateway.py` — joins the SNS multicast group on BOTH
  the loopback (`--local-iface lo/lo0`) and LAN (`--wan-iface end0/en8`) interfaces,
  forwarding packets bidirectionally so N tenant brains on one Pi appear as N
  distinct nodes to the full mesh. `RecentCache` (TTL-keyed SHA-256 digest, LRU
  512 entries) suppresses self-echo loops. 16 Python unit tests pass.
  `docs/demo/run-real-mesh.ts` gains `--multitenant` flag to use the SNS group.

- [x] **D-SRS-multitenant-spawn: on-Pi spawn script for N≈16 tenant brains.**
  `docs/demo/run-multitenant-pi.sh` — Armbian shell script (no Bun needed):
  inline Python config generation, global tile coordinate scheme
  (`tileX = piCol×localCols + localX`), spawns N mesh-nodes on loopback + gateway.
  6 Pis × 16 brains = 96 ≈ N100 (24×8 tile grid, 12×12 interior each = 23,040
  MNCA cells live). Usage: `./run-multitenant-pi.sh --pi-index N --count 16`.

- [x] **D-SRS-mnca-cell-source: data-derived MNCA seed (data becomes the program).**
  `docs/demo/mesh-data-cell-source.ts` — standalone SSE server on `:4402` that
  polls the bridge (`/tiles`), maps live mesh metrics to initial MNCA cell density
  (tick freshness → WHEN validity, peer count → WHO density, tile coords → WHERE
  gradient, SNS group bits → WHAT signal), runs `stepTile()` for 3 pre-steps, and
  serves the result as SSE events. "Ageing cells die" — low-tick tiles decay under
  the MNCA rule while fresh/busy tiles stay alive. 15 Bun tests pass.
  15 conformance tests + wired into `run-local-mesh.ts`.
  Browser viz: connect to `:4402/events` for the data-layer view alongside the
  raw mesh `:4400/events`.

- [x] **D-SRS-typepath-fuzzer: coverage-guided semantic type-path fuzzer.**
  `docs/demo/mesh-typepath-fuzzer.ts` — explores the `*.fuzz.*` type-path namespace
  (safety: no production subscriber state ever perturbed), derives SNS multicast
  groups for each candidate path, fingerprints the group address as a proxy for the
  emergent MNCA state, and tracks novel fingerprints as "new subscriber topology
  discovered." HRR (Holographic Reduced Representation) guides the walk: Jaccard
  similarity of path bigrams prioritises frontier-adjacent mutations over already-
  explored regions (high `1 - maxSim` → expand first). LCG PRNG makes fuzz
  sequences deterministic and replayable. Novel paths emitted on `:4403/events`
  (SSE); full corpus at `:4403/corpus`; live coverage stats at `:4403/stats`.
  Anchor candidates logged every 10 novel discoveries (DRY-RUN only — no broadcast).
  44 Bun tests pass. Wired into `run-local-mesh.ts` (launches on `:4403`).

## Run — real Pi mesh (Skyminer hardware)

Connects to the 6-Pi Orange Pi Prime mesh over IPv6 multicast on the Pi LAN
interface. Pi nodes broadcast their MNCA tile every 500 ms. The browser shows
a live 3×2 composite grid.

### Current Skyminer tile layout (6 nodes)

| IP             | tile coord | systemd drop-in |
|----------------|-----------|-----------------|
| 192.168.0.3    | (0,0)     | deployed ✓      |
| 192.168.0.4    | (1,0)     | deployed ✓      |
| 192.168.0.5    | (2,0)     | deployed ✓      |
| 192.168.0.6    | (0,1)     | deployed ✓      |
| 192.168.0.7    | (1,1)     | deployed ✓      |
| 192.168.0.8    | (2,1)     | deployed ✓      |
| 192.168.0.2    | —         | **locked out** — credentials unknown, needs physical console access to recover |

> The tile drop-in is `/etc/systemd/system/mesh-node.service.d/tile.conf` on
> each Pi. It adds `--tile-ms 500 --tile-x TX --tile-y TY --iface end0` to the
> base `mesh-node` service.

### Prerequisites

1. Pi mesh already running `mesh-node --heartbeat-ms 2000` (base service active).
2. Tiles deployed via `tools/u2-mesh/bulk-bringup-pi.sh` + systemd drop-in.
3. Mac has `en8` (USB-Ethernet) connected to the Pi LAN.
4. `python3` on the Mac for `mcast-relay.py` (IPv6 multicast bridge workaround).

### Start the real-mesh bridge

```sh
# From semantos-core root:
bun docs/demo/run-real-mesh.ts

# If Pi LAN is on a different Mac interface:
bun docs/demo/run-real-mesh.ts --iface en9
```

This spawns four processes:
- `mcast-relay.py` — Python IPv6 multicast receiver (en8) → UDP4 relay on :47101
  (works around Bun's `addMembership` bug on non-default Mac interfaces)
- `mesh-bridge.ts` — reads relay port, decodes tile payloads, serves SSE on :4400
- `serve.ts` — static demo HTTP server on :4321
- `mesh-snapshot-anchor.ts` — periodic dry-run BSV anchor on :4401

Expected output (6 Pis):
```
  ✓ 6 tiles from real Pi mesh:
      (0,0) tick=1234
      (1,0) tick=1234
      (2,0) tick=1234
      (0,1) tick=1234
      (1,1) tick=1234
      (2,1) tick=1234

  ✓ Demo page:  http://localhost:4321/mnca-grid.html
  Press Ctrl+C to stop.
```

### Open the demo

**http://localhost:4321/mnca-grid.html**

- Status badge: `● live mesh · 6 tiles`
- Canvas: 3×2 composite grid, each tile 12×12 interior cells at 16 px/cell
- Tick counter advances at ~2 Hz (500 ms tile step)
- BSV anchor panel surfaces a dry-run txid + WoC link every ~30 s

### Upgrading to multitenant (N≈100, D-SRS-multitenant-spawn)

Deploy to each Pi (Armbian, via SSH):

```sh
# From semantos-core root on Mac:
for IP in 192.168.0.3 192.168.0.4 192.168.0.5 192.168.0.6 192.168.0.7 192.168.0.8; do
  scp docs/demo/mesh-tenant-gateway.py docs/demo/run-multitenant-pi.sh \
      pi@${IP}:/home/pi/semantos-demo/
done

# On each Pi (piIndex = 0..5, matching the IP→tile layout above):
ssh pi@192.168.0.3 "cd /home/pi/semantos-demo && \
  ./run-multitenant-pi.sh --pi-index 0 --count 16 --iface end0 &"
# … repeat for each Pi with the correct --pi-index
```

Then on Mac, use the `--multitenant` flag (SNS-derived group):

```sh
bun docs/demo/run-real-mesh.ts --iface en8 --multitenant
```

Expected: `● live mesh · 96 tiles` (24×8 composite grid, 23,040 MNCA cells).

### Recovering Pi .2

192.168.0.2 is reachable on the network but credentials are unknown and
fail2ban has banned most of the sibling Pi IPs. To add it as tile (3,0):

1. **Console access** (keyboard + HDMI on Pi .2), or mount the SD card on another
   machine, and inject `~/.ssh/authorized_keys` with the Mac's `id_ed25519.pub`.
2. Or `sudo fail2ban-client set sshd unbanip 192.168.0.X` for each Pi IP that
   got banned, then SSH in once you know the password.
3. Once in, deploy the tile drop-in:
   ```sh
   sudo mkdir -p /etc/systemd/system/mesh-node.service.d
   sudo tee /etc/systemd/system/mesh-node.service.d/tile.conf > /dev/null << 'EOF'
   [Service]
   ExecStart=
   ExecStart=/usr/local/bin/mesh-node --config /etc/semantos/mesh.json --heartbeat-ms 2000 --iface end0 --tile-ms 500 --tile-x 3 --tile-y 0
   EOF
   sudo systemctl daemon-reload && sudo systemctl restart mesh-node
   ```

---

## Run — full local demo (all 5 slices)

### Prerequisites

```sh
# 1. Build mesh-node (once, or after Zig source changes)
cd runtime/semantos-brain && zig build mesh-node
cd -

# 2. bun installed (bridge + demo server + anchor service are Bun scripts)
bun --version   # 1.x
```

### Start everything

```sh
# default: 4 nodes in a 2×2 grid, tile step every 500ms, loopback iface lo0
bun docs/demo/run-local-mesh.ts

# custom count or speed:
bun docs/demo/run-local-mesh.ts --count 9 --tile-ms 300

# On Linux (loopback iface may be named differently):
bun docs/demo/run-local-mesh.ts --iface lo
```

The script:
1. Generates N node configs in `/tmp/mnca-mesh-local/`
2. Spawns N `mesh-node` processes (tile coords arranged in a grid)
3. Launches `mesh-bridge.ts` on `:4400` (multicast → SSE)
4. Launches `serve.ts` on `:4321` (static demo HTTP)
5. Launches `mesh-snapshot-anchor.ts` on `:4401` (periodic dry-run anchor)
6. Polls `/tiles` and prints when tiles are flowing

Expected output (4 nodes):
```
  ✓ Tiles flowing — 4 tile(s) in bridge:
      (0,0) tick=1
      (1,0) tick=1
      (0,1) tick=1
      (1,1) tick=1

  ✓ Bridge SSE:      http://localhost:4400/events
  ✓ Anchor preview:  http://localhost:4401/anchor-preview  (dry-run)
  ✓ Demo page:       http://localhost:4321/mnca-grid.html
  Press Ctrl+C to stop all processes.
```

### Open the demo

**http://localhost:4321/mnca-grid.html**

- Canvas switches to the live 2×2 mesh within ~1 s (bridge SSE)
- Status badge: `● live mesh · 4 tiles`
- Tick counter: `tick N  ·  2×2 tiles  ·  12×12 interior/tile  ·  LIVE MESH`
- BSV anchor panel (bottom): `● DRY-RUN tick N · WoC link` — active once the
  anchor service builds its first preview (~5 s after start)

### Verify tiles + anchor from the CLI

```sh
# Live tile snapshots:
curl http://localhost:4400/tiles | python3 -m json.tool

# Latest anchor preview (dry-run txid + WoC URL):
curl http://localhost:4401/anchor-preview | python3 -m json.tool
```

### On-chain broadcast (operator only)

The anchor tx is built but not broadcast. To anchor for real:
1. Open `wallet.html` (Metanet Desktop wallet)
2. Use the "MNCA snapshot anchor" panel → click dry-run → inspect → broadcast

## Standalone components

```sh
# Bridge only (join real Pi mesh multicast):
MCAST_IFACE=en0 bun docs/demo/mesh-bridge.ts

# Demo server only:
bun docs/demo/serve.ts

# Anchor service only (needs bridge running):
bun docs/demo/mesh-snapshot-anchor.ts

# Type-path fuzzer only (needs data-cell source on :4402):
bun docs/demo/mesh-typepath-fuzzer.ts
#   → novel paths: http://localhost:4403/events
#   → coverage:    http://localhost:4403/stats

# Single mesh-node (step + broadcast):
zig-out/bin/mesh-node --config node-XX.json --tile-ms 500 --tile-x 0 --tile-y 0
```
