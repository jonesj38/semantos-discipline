---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/web/src/three/cube-scene.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.431545+00:00
---

# cartridges/chess/web/src/three/cube-scene.ts

```ts
/**
 * Doubling-cube renderer.
 *
 * Wraps `@semantos/cube-object`'s `CubeMesh` in a stand-alone Three.js
 * scene so a `<canvas>` slot in the Svelte UI can show the live cube.
 * The cube's linearity drives its colour — see
 * `chess/types.ts::multiplierToLinearity`. The numeric multiplier (1, 2,
 * 4, 8, …) and the cube owner (white, black, centred) are drawn as a
 * sprite label on the cube body.
 */

import * as THREE from 'three';
import { CubeMesh, type Linearity, linearityName } from '@semantos/cube-object';
import type { Color } from '../chess/types.js';

export interface CubeView {
  multiplier: number;
  linearity: Linearity;
  owner: Color | null;
  pending: boolean;
}

export class CubeScene {
  private readonly renderer: THREE.WebGLRenderer;
  private readonly scene = new THREE.Scene();
  private readonly camera = new THREE.PerspectiveCamera(35, 1, 0.1, 100);
  private cube: CubeMesh;
  private rafHandle = 0;
  private lastTickMs = performance.now();
  private rotating = true;

  constructor(canvas: HTMLCanvasElement, init: CubeView) {
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
    this.renderer.setPixelRatio(window.devicePixelRatio ?? 1);
    this.renderer.setSize(canvas.clientWidth || 240, canvas.clientHeight || 240, false);

    this.scene.background = null;
    this.camera.position.set(2.2, 1.8, 2.6);
    this.camera.lookAt(0, 0.5, 0);

    const ambient = new THREE.AmbientLight(0xffffff, 0.45);
    const key = new THREE.DirectionalLight(0xffffff, 0.9);
    key.position.set(4, 6, 3);
    this.scene.add(ambient, key);

    this.cube = new CubeMesh({
      id: 'doubling-cube',
      linearity: init.linearity,
      position: [0, 0.5, 0],
      label: cubeLabel(init),
    });
    this.scene.add(this.cube.mesh);

    this.loop();
  }

  /** Rebuild the cube when the wire-state shape changes. */
  update(next: CubeView): void {
    const labelChanged = nextLabel(this.cube, next);
    if (this.cube.linearity !== next.linearity || labelChanged) {
      this.scene.remove(this.cube.mesh);
      this.cube.dispose();
      this.cube = new CubeMesh({
        id: 'doubling-cube',
        linearity: next.linearity,
        position: [0, 0.5, 0],
        label: cubeLabel(next),
      });
      this.scene.add(this.cube.mesh);
    }
    // Pending offer = brief shake to draw the eye to it.
    if (next.pending) {
      this.cube.rejectFlash();
    }
  }

  setRotating(on: boolean): void {
    this.rotating = on;
  }

  resize(width: number, height: number): void {
    this.renderer.setSize(width, height, false);
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
  }

  dispose(): void {
    cancelAnimationFrame(this.rafHandle);
    this.cube.dispose();
    this.renderer.dispose();
  }

  private loop = (): void => {
    this.rafHandle = requestAnimationFrame(this.loop);
    const now = performance.now();
    const dt = now - this.lastTickMs;
    this.lastTickMs = now;
    if (this.rotating) {
      this.cube.mesh.rotation.y += dt / 2400;
      this.cube.mesh.rotation.x += dt / 7200;
    }
    this.cube.tick(dt);
    this.renderer.render(this.scene, this.camera);
  };
}

function cubeLabel(v: CubeView): string {
  const own = v.owner === null ? 'centred' : v.owner;
  return `×${v.multiplier} · ${own} · ${linearityName(v.linearity)}`;
}

// CubeMesh doesn't expose its current label, so this is a coarse "if
// anything visible changed, rebuild" gate. Cheap — only happens on
// cube-state transitions, not per frame.
function nextLabel(cube: CubeMesh, next: CubeView): boolean {
  const expected = cubeLabel(next);
  const current = (cube as unknown as { readonly mesh: THREE.Mesh }).mesh.children[0];
  if (!current || !('material' in current)) return true;
  // The CubeMesh regenerates its label texture every construction, so the
  // only reliable signal here is a tag we attach the first time.
  const tag = (cube as unknown as { _labelTag?: string })._labelTag;
  if (tag === expected) return false;
  (cube as unknown as { _labelTag?: string })._labelTag = expected;
  return true;
}

```
