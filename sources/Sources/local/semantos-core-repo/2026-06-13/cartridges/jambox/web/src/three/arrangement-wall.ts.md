---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/three/arrangement-wall.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.615584+00:00
---

# cartridges/jambox/web/src/three/arrangement-wall.ts

```ts
/**
 * D-E.5 — Arrangement wall: back-wall blocks for jam.arrangement sections.
 *
 * Sections rendered as coloured blocks (one per arrangement section).
 * Each block carries:
 *   - Drag handle   → jam.arrangement.section.move
 *   - Stretch handle → jam.arrangement.section.resize
 *   - Promote button → jam.arrangement.take.promote
 *
 * Instanced rendering for the section blocks (one draw call).
 * Promote buttons are separate small meshes (sparse — typically < 16).
 *
 * No shadow maps; no post-processing (§E.6 hard rules).
 */

import * as THREE from 'three';

// ─── Types ────────────────────────────────────────────────────────────────────

export interface ArrangementSection {
  /** Stable semantic id. */
  id: string;
  arrangementId: string;
  /** Start position in bars. */
  startBar: number;
  /** Length in bars. */
  lengthBars: number;
  /** Scene colour (hex). */
  color: string | number;
}

// ─── Constants ────────────────────────────────────────────────────────────────

const BAR_WIDTH = 0.42;       // world units per bar
const SECTION_HEIGHT = 0.55;
const SECTION_DEPTH = 0.18;
const WALL_Y = 0.0;           // vertical centre on the back wall
const WALL_Z = -5.5;          // back wall Z position
const MAX_SECTIONS = 64;

const PROMOTE_BTN_SIZE = 0.12;
const STRETCH_SIZE = 0.08;

const _dummy = new THREE.Object3D();
const _color = new THREE.Color();

// ─── ArrangementWall ─────────────────────────────────────────────────────────

export class ArrangementWall {
  /** Primary section block mesh — add to scene. */
  readonly sectionMesh: THREE.InstancedMesh<THREE.BoxGeometry, THREE.MeshStandardMaterial>;
  /** Group holding all promote buttons and stretch handles. */
  readonly overlayGroup = new THREE.Group();

  private sections: ArrangementSection[] = [];
  private idToIndex = new Map<string, number>();

  constructor() {
    const geo = new THREE.BoxGeometry(1, SECTION_HEIGHT, SECTION_DEPTH);
    const mat = new THREE.MeshStandardMaterial({
      roughness: 0.55,
      metalness: 0.25,
    });
    this.sectionMesh = new THREE.InstancedMesh(geo, mat, MAX_SECTIONS);
    this.sectionMesh.name = 'arrangement-block-instanced';
    this.sectionMesh.userData.objectKind = 'arrangement-block';
    this.sectionMesh.count = 0;
    this.sectionMesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);

    this.overlayGroup.name = 'arrangement-overlay';
  }

  /** Replace sections (call when arrangement state changes). */
  setSections(sections: ArrangementSection[]): void {
    this.sections = sections.slice(0, MAX_SECTIONS);
    this.idToIndex.clear();
    for (let i = 0; i < this.sections.length; i++) {
      this.idToIndex.set(this.sections[i]!.id, i);
    }
    this.syncInstances();
    this.syncOverlay();
  }

  /** Resolve instance index → section. */
  resolveInstance(instanceId: number): ArrangementSection | null {
    return this.sections[instanceId] ?? null;
  }

  dispose(): void {
    this.sectionMesh.geometry.dispose();
    (this.sectionMesh.material as THREE.MeshStandardMaterial).dispose();
    for (const child of this.overlayGroup.children) {
      const m = child as THREE.Mesh<THREE.BufferGeometry, THREE.MeshStandardMaterial>;
      m.geometry?.dispose();
      m.material?.dispose();
    }
  }

  // ── private ──────────────────────────────────────────────────────────────

  private syncInstances(): void {
    const count = this.sections.length;
    this.sectionMesh.count = count;

    for (let i = 0; i < count; i++) {
      const sec = this.sections[i]!;
      const w = sec.lengthBars * BAR_WIDTH;
      const cx = (sec.startBar + sec.lengthBars / 2) * BAR_WIDTH - 4.0;

      _dummy.position.set(cx, WALL_Y, WALL_Z);
      _dummy.scale.set(w, 1, 1);
      _dummy.updateMatrix();
      this.sectionMesh.setMatrixAt(i, _dummy.matrix);

      _color.set(sec.color as THREE.ColorRepresentation);
      this.sectionMesh.setColorAt(i, _color);

      // Store metadata on userData via a side-channel (instance userData not
      // natively supported; we set on the mesh once and resolve by index).
    }

    this.sectionMesh.instanceMatrix.needsUpdate = true;
    if (this.sectionMesh.instanceColor) this.sectionMesh.instanceColor.needsUpdate = true;
  }

  private syncOverlay(): void {
    // Remove old overlay children
    while (this.overlayGroup.children.length > 0) {
      const child = this.overlayGroup.children[0]!;
      const m = child as THREE.Mesh<THREE.BufferGeometry, THREE.MeshStandardMaterial>;
      m.geometry?.dispose();
      m.material?.dispose();
      this.overlayGroup.remove(child);
    }

    for (const sec of this.sections) {
      const w = sec.lengthBars * BAR_WIDTH;
      const cx = (sec.startBar + sec.lengthBars / 2) * BAR_WIDTH - 4.0;
      const rightEdge = cx + w / 2;

      // Promote button — small gold sphere at the top-right of each block
      const promoteGeo = new THREE.SphereGeometry(PROMOTE_BTN_SIZE, 8, 6);
      const promoteMat = new THREE.MeshStandardMaterial({
        color: 0xffd166,
        emissive: 0x332800,
        roughness: 0.35,
        metalness: 0.5,
      });
      const promoteBtn = new THREE.Mesh(promoteGeo, promoteMat);
      promoteBtn.name = sec.id;
      promoteBtn.userData.objectKind = 'arrangement-block';
      promoteBtn.userData.action = 'promote';
      promoteBtn.userData.arrangementId = sec.arrangementId;
      promoteBtn.userData.semanticId = sec.id;
      promoteBtn.position.set(
        rightEdge - 0.08,
        WALL_Y + SECTION_HEIGHT / 2 + PROMOTE_BTN_SIZE,
        WALL_Z,
      );
      this.overlayGroup.add(promoteBtn);

      // Stretch handle — flat disc at right edge
      const stretchGeo = new THREE.CylinderGeometry(
        STRETCH_SIZE, STRETCH_SIZE, SECTION_DEPTH * 1.2, 8,
      );
      const stretchMat = new THREE.MeshStandardMaterial({
        color: 0x65d6f5,
        roughness: 0.4,
        metalness: 0.3,
      });
      const stretchHandle = new THREE.Mesh(stretchGeo, stretchMat);
      stretchHandle.name = `${sec.id}:stretch`;
      stretchHandle.userData.objectKind = 'arrangement-block';
      stretchHandle.userData.action = 'resize';
      stretchHandle.userData.arrangementId = sec.arrangementId;
      stretchHandle.userData.semanticId = sec.id;
      stretchHandle.userData.startBar = sec.startBar;
      stretchHandle.userData.lengthBars = sec.lengthBars;
      stretchHandle.position.set(rightEdge, WALL_Y, WALL_Z);
      stretchHandle.rotation.x = Math.PI / 2;
      this.overlayGroup.add(stretchHandle);
    }
  }
}

```
