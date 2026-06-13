---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/predictor.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.819137+00:00
---

# archive/apps-world-client/src/predictor.ts

```ts
/**
 * Client-side cell-engine predictor. Loads the same WASM kernel the server
 * runs; produces byte-identical rc codes for substructural ops.
 */

export type Linearity = "linear" | "affine" | "relevant";
export type SubstructuralOp = "dup" | "drop";

export interface PredictionResult {
  rc: number;
  accepted: boolean;
}

const IO_BASE = 0x300000;
const IO_SCRIPT = IO_BASE + 0x1000;
const CELL_SIZE = 1024;

const MAGIC = [0xdeadbeef, 0xcafebabe, 0x13371337, 0x42424242];

const OP_PUSHDATA2 = 0x4d;
const OP_DROP = 0x75;
const OP_DUP = 0x76;
const OP_TRUE = 0x51;

interface KernelExports {
  memory: WebAssembly.Memory;
  kernel_init: () => number;
  kernel_reset: () => void;
  kernel_set_enforcement: (enabled: number) => void;
  kernel_load_script: (ptr: number, len: number) => number;
  kernel_execute: () => number;
}

export class Predictor {
  private constructor(private readonly exports: KernelExports) {}

  static async init(wasmBytes: Uint8Array | ArrayBuffer): Promise<Predictor> {
    const imports: WebAssembly.Imports = {
      host: {
        host_call_by_name: (_ptr: number, _len: number) => 0xffffffff,
        host_fetch_cell: (_o: number, _s: number, _off: number, _out: number) => 0,
      },
    };
    const { instance } = await WebAssembly.instantiate(wasmBytes as any, imports);
    const e = instance.exports as unknown as KernelExports;
    e.kernel_init();
    e.kernel_set_enforcement(1);
    return new Predictor(e);
  }

  predictSubstructural(linearity: Linearity, op: SubstructuralOp): PredictionResult {
    this.exports.kernel_reset();
    this.exports.kernel_set_enforcement(1);

    const script = buildSubstructuralScript(linearity, op);
    const mem = new Uint8Array(this.exports.memory.buffer);
    mem.set(script, IO_SCRIPT);

    const loadRc = this.exports.kernel_load_script(IO_SCRIPT, script.length);
    if (loadRc !== 0) return { rc: loadRc, accepted: false };

    const rc = this.exports.kernel_execute();
    return { rc, accepted: rc === 0 };
  }
}

function buildSubstructuralScript(linearity: Linearity, op: SubstructuralOp): Uint8Array {
  const cell = buildCell(linearity);
  const opByte = op === "dup" ? OP_DUP : OP_DROP;
  const lenLo = CELL_SIZE & 0xff;
  const lenHi = (CELL_SIZE >>> 8) & 0xff;
  const tail = op === "drop" ? [opByte, OP_TRUE] : [opByte];

  const script = new Uint8Array(3 + cell.length + tail.length);
  let i = 0;
  script[i++] = OP_PUSHDATA2;
  script[i++] = lenLo;
  script[i++] = lenHi;
  script.set(cell, i);
  i += cell.length;
  for (const b of tail) script[i++] = b;
  return script;
}

function buildCell(linearity: Linearity): Uint8Array {
  const cell = new Uint8Array(CELL_SIZE);
  const dv = new DataView(cell.buffer);

  for (let i = 0; i < 4; i++) dv.setUint32(i * 4, MAGIC[i], true);
  dv.setUint32(16, linearityValue(linearity), true);
  dv.setUint32(20, 1, true);
  dv.setUint32(24, 1, true);

  for (let i = 30; i < 62; i++) cell[i] = 0xaa;
  for (let i = 62; i < 78; i++) cell[i] = 0xbb;

  return cell;
}

function linearityValue(l: Linearity): number {
  switch (l) {
    case "linear": return 1;
    case "affine": return 2;
    case "relevant": return 3;
  }
}

```
