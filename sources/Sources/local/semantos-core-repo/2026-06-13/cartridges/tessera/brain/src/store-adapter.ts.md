---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/src/store-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.639078+00:00
---

# cartridges/tessera/brain/src/store-adapter.ts

```ts
/**
 * tessera/brain/src/store-adapter — provenance-cell persistence for the
 * tessera care-chain cartridge, consuming ONLY the substrate
 * `StorageAdapter` interface from `@semantos/protocol-types`.
 *
 * Reference:
 *   docs/prd/TESSERA-CARTRIDGE.md §0.1 (greenfield discipline #2)
 *   docs/canon/commissions/wave-tessera.md §8 (B-Storage / D-sub → V0.5)
 *   core/protocol-types/src/storage.ts (the consumed contract)
 *
 * Greenfield discipline (the whole point of this module): tessera's
 * stores consume `StorageAdapter` — never `@bsv/sdk`, never
 * `@semantos/wallet-toolbox`, never an LMDB binding, never a
 * `runtime/` import. This is the greenfield-correct alternative to
 * oddjobz's pre-DLO.3 `*_store_lmdb.zig` (which DLO.3 is migrating
 * onto this same interface). Brain-core provides the concrete
 * LMDB/FS-backed `StorageAdapter` impl at boot; tessera only ever
 * sees this interface. CI gate
 * `tests/gates/tessera-adapter-consumption.test.ts` enforces it.
 *
 * Status — V0.5 pre-boot: this is the persistence *contract*. The
 * concrete adapter is injected at brain boot (the shared-boot-path
 * step deferred for user review, chess parity). No anchoring here.
 */

import type { StorageAdapter } from "@semantos/protocol-types";

/** The ten tessera cell-type names (mirror cartridge.json `cellTypes`). */
export type TesseraCellType =
  | "tessera.grape-lot"
  | "tessera.barrel"
  | "tessera.bottle"
  | "tessera.case"
  | "tessera.pallet"
  | "tessera.shipment"
  | "tessera.care-event"
  | "tessera.scan-event"
  | "tessera.tamper-event"
  | "tessera.tasting-note";

/**
 * Key layout under the adapter's namespace:
 *   tessera/<cellType>/<id>
 * `list(prefix)` returns ids (relative keys, prefix-stripped) so a hat
 * view can enumerate a type without scanning unrelated cartridges.
 */
function cellKey(t: TesseraCellType, id: string): string {
  if (!id) throw new Error("tessera.store: empty cell id");
  return `tessera/${t}/${id}`;
}

function typePrefix(t: TesseraCellType): string {
  return `tessera/${t}/`;
}

const enc = new TextEncoder();
const dec = new TextDecoder();

/**
 * Provenance-cell store. A thin, typed projection over `StorageAdapter`
 * — the only substrate seam tessera's TS surface touches. Records are
 * the canonical-JSON cell bodies; the LINEAR/AFFINE/RELEVANT/DEBUG
 * guarantees are the kernel's (tessera_cells.zig), not re-implemented
 * here. This layer is deliberately mechanism-free: persistence only.
 */
export class TesseraCellStore {
  constructor(private readonly storage: StorageAdapter) {}

  async put(t: TesseraCellType, id: string, body: unknown): Promise<void> {
    await this.storage.write(cellKey(t, id), enc.encode(JSON.stringify(body)));
  }

  async get<T = unknown>(t: TesseraCellType, id: string): Promise<T | null> {
    const raw = await this.storage.read(cellKey(t, id));
    return raw === null ? null : (JSON.parse(dec.decode(raw)) as T);
  }

  async has(t: TesseraCellType, id: string): Promise<boolean> {
    return this.storage.exists(cellKey(t, id));
  }

  /** Enumerate cell ids of a given type (relative keys per the contract). */
  async ids(t: TesseraCellType): Promise<string[]> {
    return this.storage.list(typePrefix(t));
  }

  /**
   * Delete a cell record. NOTE: this is storage hygiene only — it does
   * NOT model linearity consumption (a LINEAR cell being "spent" is a
   * kernel state transition, not a row deletion). Callers must not use
   * this to fake a consume; the kernel owns linearity.
   */
  async remove(t: TesseraCellType, id: string): Promise<boolean> {
    return this.storage.delete(cellKey(t, id));
  }
}

```
