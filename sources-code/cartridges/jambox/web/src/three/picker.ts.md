---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/three/picker.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.616937+00:00
---

# cartridges/jambox/web/src/three/picker.ts

```ts
/**
 * D-E.1 — Picker: raycast picker over the existing scene graph.
 *
 * Maps Three.js intersection hits to semantic object ids.
 * Hit-targets are enlarged 1.5× on touch input; primary visual stays
 * the same size (spec §risks).
 *
 * Object naming convention (set by each sub-module):
 *   mesh.name = semanticId              (any object)
 *   mesh.userData.semanticId = string   (override if name is used for something else)
 *   mesh.userData.objectKind = string   ('loop-orb' | 'scene-tile' | 'instrument-pod' |
 *                                        'arrangement-block' | 'player-avatar' |
 *                                        'mixer-fader' | 'effect-fader')
 */

import * as THREE from 'three';

export type PickObjectKind =
  | 'loop-orb'
  | 'scene-tile'
  | 'instrument-pod'
  | 'arrangement-block'
  | 'player-avatar'
  | 'mixer-fader'
  | 'effect-fader'
  | 'unknown';

export interface PickHit {
  /** Semantic id of the object (stable across frames). */
  semanticId: string;
  /** What kind of 3D object was hit. */
  kind: PickObjectKind;
  /** Distance from camera to hit point. */
  distance: number;
  /** Hit point in world space. */
  point: THREE.Vector3;
  /** The Three.js object that was hit. */
  object: THREE.Object3D;
}

/**
 * Picker — wraps THREE.Raycaster with semantic id resolution.
 *
 * Usage:
 *   const picker = new Picker(camera);
 *   picker.setPickableObjects([...meshes]);
 *   const hit = picker.pick(e, canvas, isTouchInput);
 */
export class Picker {
  private readonly raycaster = new THREE.Raycaster();
  private readonly pointer = new THREE.Vector2();
  private pickableObjects: THREE.Object3D[] = [];

  constructor(private readonly camera: THREE.Camera) {}

  /** Replace the pickable object list (call from render loop when scene changes). */
  setPickableObjects(objects: THREE.Object3D[]): void {
    this.pickableObjects = objects;
  }

  /**
   * Pick against the scene for a mouse/touch event.
   *
   * @param clientX  - event.clientX
   * @param clientY  - event.clientY
   * @param canvas   - the WebGL canvas
   * @param isTouch  - enlarges hit spheres 1.5× when true
   */
  pick(
    clientX: number,
    clientY: number,
    canvas: HTMLCanvasElement,
    isTouch = false,
  ): PickHit | null {
    const rect = canvas.getBoundingClientRect();
    this.pointer.set(
      ((clientX - rect.left) / rect.width) * 2 - 1,
      -((clientY - rect.top) / rect.height) * 2 + 1,
    );

    this.raycaster.setFromCamera(this.pointer, this.camera);

    // On touch, use a larger near threshold to compensate for finger area.
    if (isTouch) {
      this.raycaster.params.Points = { threshold: 0.3 };
      this.raycaster.params.Line = { threshold: 0.15 };
    } else {
      this.raycaster.params.Points = { threshold: 0.1 };
      this.raycaster.params.Line = { threshold: 0.05 };
    }

    const hits = this.raycaster.intersectObjects(this.pickableObjects, true);
    if (hits.length === 0) return null;

    const first = hits[0];
    return this.resolveHit(first);
  }

  /**
   * Pick and return ALL hits, sorted by distance (nearest first).
   * Useful for drag-over detection (e.g. orb over tile).
   */
  pickAll(
    clientX: number,
    clientY: number,
    canvas: HTMLCanvasElement,
    isTouch = false,
  ): PickHit[] {
    const rect = canvas.getBoundingClientRect();
    this.pointer.set(
      ((clientX - rect.left) / rect.width) * 2 - 1,
      -((clientY - rect.top) / rect.height) * 2 + 1,
    );
    this.raycaster.setFromCamera(this.pointer, this.camera);
    if (isTouch) {
      this.raycaster.params.Points = { threshold: 0.3 };
    }
    const hits = this.raycaster.intersectObjects(this.pickableObjects, true);
    return hits.map((h) => this.resolveHit(h)).filter(Boolean) as PickHit[];
  }

  // ── private ──────────────────────────────────────────────────────────────────

  private resolveHit(intersection: THREE.Intersection): PickHit | null {
    const obj = intersection.object;
    const semanticId = this.resolveSemanticId(obj);
    if (!semanticId) return null;

    const kind = this.resolveKind(obj);
    return {
      semanticId,
      kind,
      distance: intersection.distance,
      point: intersection.point.clone(),
      object: obj,
    };
  }

  private resolveSemanticId(obj: THREE.Object3D): string | null {
    // Walk up the object hierarchy looking for a semantic id.
    let current: THREE.Object3D | null = obj;
    while (current) {
      const override = current.userData.semanticId as string | undefined;
      if (override) return override;
      if (current.name && current.name !== '') return current.name;
      current = current.parent;
    }
    return null;
  }

  private resolveKind(obj: THREE.Object3D): PickObjectKind {
    let current: THREE.Object3D | null = obj;
    while (current) {
      const kind = current.userData.objectKind as PickObjectKind | undefined;
      if (kind) return kind;
      current = current.parent;
    }
    return 'unknown';
  }
}

```
