---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/esp32-hackkit/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.325544+00:00
---

# Semantos ESP32 Hack-Kit

A tiny distribution built around the Semantos cell-engine's embedded WASM
profile — a **29 KB** dual-stack PDA that executes Bitcoin Script extended
with linear-type opcodes, packaged as a plug-and-play ESP-IDF component.

This repo is deliberately rough. It exists so a handful of ESP32 hobbyists
at a meetup can grab the wasm blob, wire up four small adapter callbacks,
and see what cool things they can build on top. It is not a product, not a
library release, and not polished. Think "loaner bike," not "rental car."

## What's in the box

```
esp32-hackkit/
├── components/semantos/
│   ├── wasm/
│   │   └── cell-engine-embedded.wasm     (29,613 bytes)
│   ├── include/
│   │   ├── semantos.h                    public API
│   │   ├── semantos_adapters.h           the four adapter callback types
│   │   └── semantos_internal.h           (implementation-only)
│   ├── src/
│   │   ├── semantos.c                    lifecycle + kernel wrappers
│   │   ├── host_crypto_mbedtls.c         sha256 / hash160 / checksig / ...
│   │   ├── host_utility.c                log, blocktime, sequence, ...
│   │   ├── adapters_noop.c               no-op table for all 4 adapters
│   │   ├── runtime_wasm3.c               wasm3 backend
│   │   └── runtime_wamr.c                WAMR backend
│   ├── CMakeLists.txt
│   ├── Kconfig
│   └── idf_component.yml
├── examples/hello_cell/                  minimal demo app
└── docs/
    ├── ADAPTERS.md
    ├── HOST_IMPORTS.md
    └── CHALLENGE.md
```

## What you can do with this

The cell-engine executes scripts inside a pure sandbox: no I/O, no time,
no async, no side effects. Everything the kernel wants from the outside
world arrives through one of ten host imports (five crypto, three
utility, one named dispatch, one octave fetch) plus seven adapter
callbacks grouped into four patterns.

The hack-kit implements all ten host imports. mbedTLS (which ESP-IDF
already ships) covers all five crypto imports natively. The four adapter
patterns are **left for you to implement** — that's where the fun lives.

## The four adapter patterns

| Pattern | What it does | Example ESP32 bindings |
| --- | --- | --- |
| **Storage** | Read and write named blobs | NVS, SPIFFS, LittleFS, SD card, PSRAM ring buffer |
| **Identity** | Resolve and derive certificates | Flash-stored cert store, BLE-provisioned identity, Wi-Fi Manager integration |
| **Anchor** | Submit a 32-byte state hash for durable record | HTTP POST to a gateway, LoRa uplink, ESP-NOW broadcast, append to an SD-card log |
| **Network** | Publish and query semantic objects | MQTT, ESP-NOW, BLE advertisement, mDNS |

The no-op table (`semantos_adapters_noop`) is wired in by default so you
can prove the wasm module loads and the kernel runs before touching any
real I/O. See `docs/ADAPTERS.md` for the exact signatures and `docs/
CHALLENGE.md` for ideas.

## Getting the hello_cell demo running

Assuming you already have ESP-IDF 5.x installed and an ESP32 board plugged
in:

```bash
cd esp32-hackkit/examples/hello_cell
idf.py set-target esp32          # or esp32s3, esp32c3, etc.
idf.py build flash monitor
```

You should see something like:

```
I (523) hello_cell: starting...
I (530) semantos: init: loading cell-engine-embedded.wasm (29613 bytes), stack=16384
I (540) hello_cell: semantos_init ok
I (542) hello_cell: kernel_init rc=0
I (544) hello_cell: load_script rc=0
I (546) hello_cell: execute rc=0 opcount=3 stack_depth=1 top=1 err=0x00000000
I (548) hello_cell: === hello cell: success ===
```

If you see that, you have a 2-PDA Bitcoin-Script-with-linear-types engine
running on a microcontroller.

## Runtime choice (wasm3 vs WAMR)

Both backends are in the box. Pick one via `idf.py menuconfig` under
`Component config → Semantos cell-engine → WASM runtime backend`:

- **wasm3** — default. Tiny (~64 KB code), no PSRAM needed. Runs on plain
  ESP32, S2, C3, and S3. Classic interpreter only. Fine for the meetup
  demos.
- **WAMR** — `espressif/wamr`. Bigger but faster. Recommended for ESP32-S3
  with PSRAM. Supports AOT in addition to interpreter mode, though the
  hack-kit only wires the interpreter path.

You need to install exactly one of them via the component manager:

```bash
idf.py add-dependency "espressif/wasm3^0.5.0"
# or
idf.py add-dependency "espressif/wamr^2.0.0"
```

## Caveats, gotchas, disclaimers

- This is pre-alpha scaffolding. The host imports compile and the hello
  world runs, but nothing in this kit is tested at any serious scale. If
  something blows up on your board, it's expected, and your cycle time
  chasing it down is part of the point.
- The checksig / checkmultisig implementations in
  `host_crypto_mbedtls.c` are minimal — they parse keys in SEC format
  and signatures in DER but do not implement the full Bitcoin sighash
  machinery.  If you feed the kernel pre-hashed 32-byte messages
  (which the embedded profile is supposed to do), they work; if you
  feed it raw tx data you're on your own.
- `host_fetch_cell` returns 0 (failure) until you wire in real
  multi-octave storage. Scripts that only use local octave-0 cells don't
  care.
- The four adapter stubs all return `SEMANTOS_ERR_DENIED` (-2). The
  kernel propagates this as "feature not available" errors on any
  operation that would have touched them.
- `host_call_by_name` returns `0xFFFFFFFF` (unknown) for every name.
  This is the hook where you add your own `gpio.toggle`,
  `led.set_pixel`, `dht22.read` etc. Grep for `call_by_name` in
  `host_utility.c` to see where to plug in.
- The kernel does not currently expose an API for streaming large cells
  across multiple WASM calls, so keep your payloads under the 1KB
  octave-0 cell size.
- No warranty, no guarantees, this may literally not build on your
  specific ESP-IDF version. Patches welcome, confusion expected, beer
  encouraged.

## Where this came from

The embedded WASM blob is produced by the main Semantos repo at
`packages/cell-engine/build.zig` with `-Dprofile=embedded`. The source
of truth for host import signatures lives in
`packages/cell-engine/src/host.zig`. If you want to regenerate the blob
yourself:

```bash
cd packages/cell-engine
zig build -Dembedded=true
cp zig-out/bin/cell-engine-embedded.wasm ../../esp32-hackkit/components/semantos/wasm/
```

## What to do next

Read `docs/CHALLENGE.md` — that's the "fun ideas for a Sunday" list. Pick
one, implement the relevant adapter, show it off at the next meetup.
