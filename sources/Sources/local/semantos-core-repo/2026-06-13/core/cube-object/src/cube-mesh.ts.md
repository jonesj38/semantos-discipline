---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cube-object/src/cube-mesh.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.010833+00:00
---

# core/cube-object/src/cube-mesh.ts

```ts
/**
 * `CubeMesh` — the cube as a renderable semantic object.
 *
 * Three.js Mesh wrapper that:
 *   - holds a Linearity-typed cube (BoxGeometry, MeshStandardMaterial, label
 *     sprite, shake/flash effects)
 *   - looks up identity-bound color via `identityPort.get().getCert(certId)`
 *     when a `certId` is supplied, falling back to the Linearity hue when no
 *     cert is found (NPC path)
 *   - exposes `applyAuthoritative` / `predictMove` / `tick` lifecycle hooks
 *     so the world-client's prediction/reconciliation loop can drive it,
 *     while single-player consumers can call only `tick` and skip the
 *     authoritative path entirely
 *
 * Extracted from `apps/world-client/src/entity.ts:EntityMesh`. The world-client
 * version was specialized to the world-host wire format
 * (`EntityDelta.spatial.position`); this generalization accepts a minimal
 * `CubeInit` and exposes `applyAuthoritative` for consumers that have the
 * server frame.
 *
 * Identity coloring contract:
 *   - if `certId` is supplied AND the cert resolves AND it carries a color
 *     hint (currently via `email` hashed to a hue — the same scheme
 *     `runtime/world-beam/apps/world_host/lib/world_host/avatar.ex:starting_color/1` uses), that
 *     hue wins
 *   - otherwise the body is colored by `linearityColor(linearity)`
 *
 * The cube does NOT call `identityPort.get()` lazily on every render — that
 * would couple frame timing to port lookups. It resolves once at construction
 * (and again on `setCertId(...)` / `refreshIdentity()`), caches the result,
 * and re-evaluates only when explicitly asked.
 */

import * as THREE from 'three';
import { identityPort } from '@semantos/identity-ports';
import type { PlexusCert } from '@plexus/contracts';

import { type Linearity, linearityName } from './linearity.js';
import { pickCubeColor } from './color.js';

/** Minimal data required to construct a cube. */
export interface CubeInit {
  /** Stable identifier for this cube (e.g. `region-0001-avatar-...`). */
  id: string;
  /** Server-shape numeric linearity. */
  linearity: Linearity;
  /** World-space position. Defaults to the origin if omitted. */
  position?: readonly [number, number, number];
  /**
   * Optional explicit color override, takes precedence over both the
   * identity lookup and the linearity default. Useful when the server
   * supplies a per-entity color (avatars do).
   */
  color?: number | null;
  /**
   * Optional cert id this cube is bound to. When set, the constructor calls
   * `identityPort.get().getCert(certId)` and uses the result to compute a
   * color (identity-bound avatars). If the port is unbound or the cert is
   * missing, falls back to the linearity color.
   */
  certId?: string | null;
  /** Optional label override — defaults to `id · LINEARITYNAME`. */
  label?: string;
}

/**
 * A non-Linearity-keyed color hash applied per-cert. Mirrors
 * `runtime/world-beam/apps/world_host/lib/world_host/avatar.ex` so server-coloured avatars and
 * client-only (single-player) avatars look consistent when both are
 * cert-bound.
 */
function certColor(cert: PlexusCert): number {
  // Hash the public key (33-byte compressed hex). Same 12-color palette
  // as the world-host server, indexed by the first byte of SHA-ish input.
  // This is intentionally NOT cryptographically robust — it just needs
  // to spread cert ids across the palette deterministically.
  const palette = [
    0xe74c3c, 0xf39c12, 0xf1c40f, 0x9ccc65, 0x3498db, 0x9b59b6, 0xe91e63, 0xff6f61,
    0xffe66d, 0xc44569, 0xfb923c, 0x6366f1,
  ];
  let h = 0;
  for (let i = 0; i < cert.publicKey.length; i++) {
    h = (h * 31 + cert.publicKey.charCodeAt(i)) >>> 0;
  }
  return palette[h % palette.length]!;
}

export class CubeMesh {
  readonly id: string;
  readonly mesh: THREE.Mesh;
  readonly linearity: Linearity;

  /** Authoritative position from the server (or just `init.position` when single-player). */
  authoritativePosition: THREE.Vector3;
  /** Locally-predicted position; equal to authoritative until a `predictMove` runs. */
  predictedPosition: THREE.Vector3;
  /** Smoothly-interpolated render position. */
  displayPosition: THREE.Vector3;

  version = 0;
  lastStateHash = '';
  selected = false;

  /** Wall-clock timestamp (ms) until which the shake effect runs. */
  shakeUntil = 0;
  /** Wall-clock timestamp (ms) until which the flash effect runs. */
  flashUntil = 0;
  flashColor = new THREE.Color(0xe74c3c);
  private flashDurationMs = 350;

  private readonly baseMaterial: THREE.MeshStandardMaterial;
  private readonly labelSprite: THREE.Sprite;
  private cachedCertId: string | null;
  private cachedCert: PlexusCert | null = null;

  constructor(init: CubeInit) {
    this.id = init.id;
    this.linearity = init.linearity;
    this.cachedCertId = init.certId ?? null;

    if (init.certId) {
      this.cachedCert = safeGetCert(init.certId);
    }

    const color = pickCubeColor({
      explicit: init.color ?? null,
      cert: this.cachedCert,
      linearity: this.linearity,
    });
    const geom = new THREE.BoxGeometry(0.9, 0.9, 0.9);
    this.baseMaterial = new THREE.MeshStandardMaterial({
      color,
      roughness: 0.35,
      metalness: 0.15,
      emissive: new THREE.Color(color).multiplyScalar(0.12),
    });
    this.mesh = new THREE.Mesh(geom, this.baseMaterial);
    this.mesh.castShadow = true;
    this.mesh.receiveShadow = true;
    this.mesh.userData.entityId = this.id;

    const [x, y, z] = init.position ?? [0, 0.5, 0];
    this.authoritativePosition = new THREE.Vector3(x, y, z);
    this.predictedPosition = this.authoritativePosition.clone();
    this.displayPosition = this.authoritativePosition.clone();
    this.mesh.position.copy(this.displayPosition);

    const labelText = init.label ?? `${this.id} · ${linearityName(this.linearity)}`;
    this.labelSprite = makeLabel(labelText);
    this.labelSprite.position.set(0, 0.9, 0);
    this.mesh.add(this.labelSprite);
  }

  /**
   * Apply an authoritative position+state from the server. Triggers a
   * yellow flash when local prediction has drifted, snapping the predicted
   * position back to authoritative.
   */
  applyAuthoritative(input: {
    position: readonly [number, number, number];
    version?: number;
    state_hash?: string;
  }): void {
    const [x, y, z] = input.position;
    this.authoritativePosition.set(x, y, z);
    if (input.version !== undefined) this.version = input.version;
    if (input.state_hash !== undefined) this.lastStateHash = input.state_hash;

    const drift = this.predictedPosition.distanceTo(this.authoritativePosition);
    if (drift > 0.001) {
      this.predictedPosition.copy(this.authoritativePosition);
      this.flash(0xf1c40f, 250);
    }
  }

  /** Move the predicted position by a delta vector (client prediction step). */
  predictMove(delta: readonly [number, number, number]): void {
    this.predictedPosition.x += delta[0];
    this.predictedPosition.y += delta[1];
    this.predictedPosition.z += delta[2];
  }

  /** Trigger the LINEAR-violation red flash + shake. */
  rejectFlash(): void {
    this.flash(0xe74c3c, 350);
    this.shakeUntil = performance.now() + 350;
  }

  setSelected(sel: boolean): void {
    this.selected = sel;
  }

  /**
   * Update the bound cert id and re-resolve color from the identityPort.
   * Use when the cube's identity changes mid-flight (rare; mostly for tests).
   */
  setCertId(certId: string | null): void {
    this.cachedCertId = certId;
    this.cachedCert = certId ? safeGetCert(certId) : null;
    this.refreshBodyColor();
  }

  /**
   * Re-query `identityPort` for the cached cert. Use when you've registered
   * a new identity AFTER constructing the cube and want the color updated.
   */
  refreshIdentity(): void {
    if (!this.cachedCertId) return;
    this.cachedCert = safeGetCert(this.cachedCertId);
    this.refreshBodyColor();
  }

  /**
   * Per-frame update. `dtMs` is the elapsed wall time since the last tick.
   * Smoothly interpolates `displayPosition → predictedPosition`, applies
   * shake offsets, and runs the flash decay.
   */
  tick(dtMs: number): void {
    const smooth = 1 - Math.pow(0.002, dtMs / 1000);
    this.displayPosition.lerp(this.predictedPosition, smooth);

    const now = performance.now();
    if (now < this.shakeUntil) {
      const amp = 0.06;
      this.mesh.position.set(
        this.displayPosition.x + (Math.random() - 0.5) * amp,
        this.displayPosition.y + (Math.random() - 0.5) * amp,
        this.displayPosition.z + (Math.random() - 0.5) * amp,
      );
    } else {
      this.mesh.position.copy(this.displayPosition);
    }

    if (now < this.flashUntil) {
      const t = 1 - (this.flashUntil - now) / this.flashDurationMs;
      this.baseMaterial.emissive.copy(this.flashColor).multiplyScalar(0.8 * (1 - t));
    } else if (this.selected) {
      this.baseMaterial.emissive.copy(new THREE.Color(0x5b9fff)).multiplyScalar(0.35);
    } else {
      const base = this.currentColor();
      this.baseMaterial.emissive.copy(new THREE.Color(base)).multiplyScalar(0.12);
    }
  }

  /** Free THREE GPU resources. Call on despawn. */
  dispose(): void {
    this.mesh.geometry.dispose();
    this.baseMaterial.dispose();
    if (this.labelSprite.material instanceof THREE.SpriteMaterial) {
      this.labelSprite.material.map?.dispose();
      this.labelSprite.material.dispose();
    }
  }

  private flash(color: number, ms: number): void {
    this.flashColor.setHex(color);
    this.flashDurationMs = ms;
    this.flashUntil = performance.now() + ms;
  }

  private currentColor(): number {
    return pickCubeColor({
      explicit: null,
      cert: this.cachedCert,
      linearity: this.linearity,
    });
  }

  private refreshBodyColor(): void {
    const c = this.currentColor();
    this.baseMaterial.color.setHex(c);
  }
}

// ─── helpers ──────────────────────────────────────────────────────────────

function safeGetCert(certId: string): PlexusCert | null {
  // The port may be unbound (no boot-time wiring yet, e.g. early test
  // harness paths). Guard explicitly so the cube doesn't blow up the
  // first frame; consumers can call `refreshIdentity()` after binding.
  try {
    if (!identityPort.isBound()) return null;
    return identityPort.get().getCert(certId);
  } catch {
    return null;
  }
}

function makeLabel(text: string): THREE.Sprite {
  const canvas = document.createElement('canvas');
  canvas.width = 512;
  canvas.height = 128;
  const ctx = canvas.getContext('2d')!;
  ctx.font = '500 44px ui-monospace, monospace';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = 'rgba(200,220,255,0.95)';
  ctx.fillText(text, canvas.width / 2, canvas.height / 2);

  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.minFilter = THREE.LinearFilter;

  const mat = new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false });
  const sprite = new THREE.Sprite(mat);
  sprite.scale.set(2, 0.5, 1);
  return sprite;
}

```
