---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/three/scene-tile.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.615874+00:00
---

# cartridges/jambox/web/src/three/scene-tile.ts

```ts
/**
 * D-E.4 — Scene tile floor: instanced 8×4 grid of scene tiles.
 *
 * Default layout: 8 columns × 4 rows = 32 tiles (§E.5 front floor).
 *
 * Interactions (via InteractionRouter):
 *   Step-on → jam.scene.launch { sceneId, quantum, ts }
 *   Tile flashes on receiving jam.scene.launch via cell-relay subscription.
 *
 * Instanced rendering — one draw call for all tiles.
 * No shadow maps, no post-processing (§E.6).
 */

import * as THREE from 'three';

// ─── Types ────────────────────────────────────────────────────────────────────

export interface SceneTileData {
  /** Stable scene id (jam.scene:...). */
  id: string;
  /** Column index 0-7. */
  col: number;
  /** Row index 0-3. */
  row: number;
  /** Base colour hex. */
  color: string | number;
  /** Whether this scene is currently playing. */
  playing: boolean;
}

// ─── Constants ────────────────────────────────────────────────────────────────

const COLS = 8;
const ROWS = 4;
const MAX_TILES = COLS * ROWS;   // 32
const TILE_W = 1.1;
const TILE_D = 1.1;
const TILE_H = 0.06;
const TILE_GAP = 0.08;
const FLASH_DURATION = 0.35;    // seconds

const _dummy = new THREE.Object3D();
const _color = new THREE.Color();

// ─── SceneTileFloor ───────────────────────────────────────────────────────────

export class SceneTileFloor {
  /** Add to scene. */
  readonly mesh: THREE.InstancedMesh<THREE.BoxGeometry, THREE.MeshStandardMaterial>;

  private tiles: SceneTileData[] = [];
  private flashTimers = new Map<string, number>(); // sceneId → remaining seconds
  /** Map sceneId → instance index for O(1) flash lookup. */
  private idToIndex = new Map<string, number>();

  /** World-space origin of the tile grid (bottom-left corner). */
  private readonly origin: THREE.Vector3;

  constructor(origin: THREE.Vector3 = new THREE.Vector3(-4.2, -1.15, -1.0)) {
    this.origin = origin;

    const geo = new THREE.BoxGeometry(TILE_W, TILE_H, TILE_D);
    const mat = new THREE.MeshStandardMaterial({
      roughness: 0.72,
      metalness: 0.1,
    });
    this.mesh = new THREE.InstancedMesh(geo, mat, MAX_TILES);
    this.mesh.name = 'scene-tile-instanced';
    this.mesh.userData.objectKind = 'scene-tile';
    this.mesh.count = 0;
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
  }

  /** Replace tiles (call when jam.scene state changes). */
  setTiles(tiles: SceneTileData[]): void {
    this.tiles = tiles.slice(0, MAX_TILES);
    this.idToIndex.clear();
    for (let i = 0; i < this.tiles.length; i++) {
      this.idToIndex.set(this.tiles[i]!.id, i);
    }
    this.syncInstances();
  }

  /**
   * Trigger a flash on a tile (call when jam.scene.launch cell arrives).
   */
  flashTile(sceneId: string): void {
    this.flashTimers.set(sceneId, FLASH_DURATION);
  }

  /** Animate flashes. Call from render loop. */
  tick(dt: number): void {
    if (this.flashTimers.size === 0) return;
    let changed = false;
    for (const [id, remaining] of this.flashTimers) {
      const next = remaining - dt;
      if (next <= 0) {
        this.flashTimers.delete(id);
      } else {
        this.flashTimers.set(id, next);
      }
      changed = true;
    }
    if (changed) this.syncInstances();
  }

  /**
   * Resolve which tile (if any) was hit by an instance intersection.
   */
  resolveInstance(instanceId: number): SceneTileData | null {
    return this.tiles[instanceId] ?? null;
  }

  /**
   * Return the world-space centre position of a tile (for camera dolly, etc).
   */
  tileWorldPosition(col: number, row: number): THREE.Vector3 {
    return new THREE.Vector3(
      this.origin.x + col * (TILE_W + TILE_GAP) + TILE_W / 2,
      this.origin.y + TILE_H / 2,
      this.origin.z + row * (TILE_D + TILE_GAP) + TILE_D / 2,
    );
  }

  dispose(): void {
    this.mesh.geometry.dispose();
    (this.mesh.material as THREE.MeshStandardMaterial).dispose();
  }

  // ── private ──────────────────────────────────────────────────────────────

  private syncInstances(): void {
    const count = this.tiles.length;
    this.mesh.count = count;

    for (let i = 0; i < count; i++) {
      const tile = this.tiles[i]!;
      const worldPos = this.tileWorldPosition(tile.col, tile.row);
      _dummy.position.copy(worldPos);
      _dummy.scale.setScalar(1);
      _dummy.updateMatrix();
      this.mesh.setMatrixAt(i, _dummy.matrix);

      const flashRemaining = this.flashTimers.get(tile.id) ?? 0;
      const flashT = flashRemaining / FLASH_DURATION; // 1→0
      if (flashT > 0) {
        // Flash: lerp toward white
        _color.set(tile.color as THREE.ColorRepresentation);
        _color.lerp(new THREE.Color(0xffffff), flashT * 0.85);
      } else if (tile.playing) {
        // Playing: bright version of the colour
        _color.set(tile.color as THREE.ColorRepresentation);
        _color.multiplyScalar(1.6);
      } else {
        _color.set(tile.color as THREE.ColorRepresentation);
        _color.multiplyScalar(0.55);
      }
      this.mesh.setColorAt(i, _color);
    }

    this.mesh.instanceMatrix.needsUpdate = true;
    if (this.mesh.instanceColor) this.mesh.instanceColor.needsUpdate = true;
  }
}

// ─── Factory helper ───────────────────────────────────────────────────────────

/**
 * Create default 8×4 tile data from scene ids.
 * Assigns columns left-to-right, rows front-to-back.
 */
export function createDefaultTiles(
  sceneIds: string[],
  colors: Array<string | number>,
): SceneTileData[] {
  const tiles: SceneTileData[] = [];
  for (let row = 0; row < ROWS; row++) {
    for (let col = 0; col < COLS; col++) {
      const idx = row * COLS + col;
      const id = sceneIds[idx] ?? `scene-${idx}`;
      const color = colors[idx % colors.length] ?? 0x2a3a4a;
      tiles.push({ id, col, row, color, playing: false });
    }
  }
  return tiles;
}

```
