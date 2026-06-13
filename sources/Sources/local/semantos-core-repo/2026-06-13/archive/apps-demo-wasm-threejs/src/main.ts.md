---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-demo-wasm-threejs/src/main.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.759319+00:00
---

# archive/apps-demo-wasm-threejs/src/main.ts

```ts
/**
 * Substructural linearity, animated in Three.js.
 *
 * Each cube is a cell with a linearity class (LINEAR / AFFINE / RELEVANT).
 * Clicking a cube runs a script that attempts an operation on that cell:
 *
 *   OP_PUSHDATA2 <packedCell>  OP_DUP | OP_DROP
 *
 * The kernel's K1 enforcement gate (pda.zig:sdup_enforced, sdrop_enforced)
 * decides legal vs illegal. The visual is just whatever the kernel returned:
 *
 *   success + DUP   → mitosis (cube splits)
 *   success + DROP  → silent fade (AFFINE only, by the rules)
 *   cannot_duplicate_* / cannot_discard_* → shatter (red flash + shake)
 *
 * The "conductor" cube uses OP_CALLHOST to invoke a host-side merge that
 * drives two other cubes' animations from inside its own script. That's the
 * same boundary phase 38's host.exec verb uses — bytecode reaching into the
 * host via a named, proof-covered opcode.
 */

// ── identity ports — bind once at boot ───────────────────────────────────
import { bindAllIdentityPorts } from '@semantos/identity-ports';
import { makeStubBindings, seedStubCapability } from '@semantos/identity-ports/stub';
import { mountIdentityPanel } from './identity-ui';

const { bundle, store } = makeStubBindings();
bindAllIdentityPorts(bundle);

const panelEl = document.getElementById('identity-panel');
if (panelEl) {
  mountIdentityPanel(panelEl, store, seedStubCapability);
}

import * as THREE from 'three';
import {
  loadCellEngine,
  pushCellScript,
  pushBytesScript,
  concatScript,
  OP_DUP,
  OP_DROP,
  OP_CALLHOST,
  type MinimalCellEngine,
  type LinearityClass,
  type ScriptResult,
} from './cell-engine';
import { CELL_RECIPES, type CellRecipe } from './cells';

// ── constants ────────────────────────────────────────────────────────

const CLASS_COLOR: Record<LinearityClass, number> = {
  linear: 0x4a9eff,
  affine: 0x888899,
  relevant: 0x6ad08a,
};

const SHATTER_COLOR = new THREE.Color(0xff4a4a);

// ── three.js scaffolding ─────────────────────────────────────────────

const canvas = document.getElementById('scene') as HTMLCanvasElement;
const readout = document.getElementById('readout') as HTMLDivElement;
const enforceToggle = document.getElementById('enforce-toggle') as HTMLInputElement;
const resetBtn = document.getElementById('reset-btn') as HTMLButtonElement;

const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x0a0a0f);

const camera = new THREE.PerspectiveCamera(42, window.innerWidth / window.innerHeight, 0.1, 100);
camera.position.set(0, 1.5, 9);
camera.lookAt(0, 0, 0);

scene.add(new THREE.AmbientLight(0xffffff, 0.42));
const key = new THREE.DirectionalLight(0xffffff, 0.9);
key.position.set(3, 5, 4);
scene.add(key);

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});

// ── cube state ───────────────────────────────────────────────────────

interface CubeState {
  mesh: THREE.Mesh;
  recipe: CellRecipe;
  homePosition: THREE.Vector3;
  baseColor: THREE.Color;
  /** 0..1 alpha; drives fadeOut / consume animation. */
  alpha: number;
  /** 0..1; 1 = fully shattered (red flash + shake), decays per frame. */
  shatterPhase: number;
  /** radians of spin remaining. */
  spin: number;
  /** Merge animation: the cube glides toward another position and shrinks. */
  mergeTarget: THREE.Vector3 | null;
  /** After a successful DUP, we spawn a transient clone that drifts away. */
  splitChild: THREE.Mesh | null;
  splitPhase: number;
  /** Has this cube already been successfully consumed/dropped? */
  extinguished: boolean;
}

const cubes: CubeState[] = [];
const idToIdx = new Map<string, number>();
const RAYCAST_TARGETS: THREE.Object3D[] = [];

const SPACING = 1.8;
const Y_OFFSET = 0;

function buildCubes(): void {
  // clear prior cubes if any (used by reset)
  for (const c of cubes) {
    scene.remove(c.mesh);
    if (c.splitChild) scene.remove(c.splitChild);
  }
  cubes.length = 0;
  idToIdx.clear();
  RAYCAST_TARGETS.length = 0;

  CELL_RECIPES.forEach((recipe, i) => {
    const geom = new THREE.BoxGeometry(0.9, 0.9, 0.9);
    const color = new THREE.Color(CLASS_COLOR[recipe.linearity]);
    const mat = new THREE.MeshStandardMaterial({
      color: color.clone(),
      roughness: 0.45,
      metalness: 0.15,
      transparent: true,
      opacity: 1,
    });
    const mesh = new THREE.Mesh(geom, mat);
    const xOffset = (i - (CELL_RECIPES.length - 1) / 2) * SPACING;
    const home = new THREE.Vector3(xOffset, Y_OFFSET, 0);
    mesh.position.copy(home);
    mesh.userData.idx = i;
    scene.add(mesh);
    RAYCAST_TARGETS.push(mesh);

    cubes.push({
      mesh,
      recipe,
      homePosition: home,
      baseColor: color,
      alpha: 1,
      shatterPhase: 0,
      spin: 0,
      mergeTarget: null,
      splitChild: null,
      splitPhase: 0,
      extinguished: false,
    });
    idToIdx.set(recipe.id, i);
  });
}

buildCubes();

// ── engine loading with real host imports ────────────────────────────

let engine: MinimalCellEngine | null = null;

/**
 * OP_CALLHOST dispatcher. The kernel pops a name-string from TOS and calls
 * us with it; we route by name into scene-side side effects and return a
 * u32 status (0 = ok, 0xFFFFFFFF = unknown name).
 */
function hostDispatch(name: string): number {
  switch (name) {
    case 'merge':
      mergeInProgress?.();
      return 0;
    case 'log':
      return 0;
    default:
      return 0xffffffff;
  }
}

/** Scratch closure populated just before running a conductor-merge script. */
let mergeInProgress: (() => void) | null = null;

async function initEngine(): Promise<void> {
  try {
    engine = await loadCellEngine('/cell-engine.wasm', hostDispatch);
    engine.setEnforcement(enforceToggle.checked);
    showReadout('kernel ready — click a cube');
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    showReadout(
      `kernel failed to load:\n${msg}\n\n` +
      `Build the WASM first:\n  cd core/cell-engine && zig build`,
      { violation: false },
    );
  }
}

// ── readout ──────────────────────────────────────────────────────────

function showReadout(text: string, opts?: { violation: boolean }): void {
  readout.textContent = text;
  readout.classList.add('visible');
  readout.classList.toggle('violation', !!opts?.violation);
}

/**
 * "Legal" means the kernel's K1 gate did not reject any operation. A script
 * that consumes everything off the stack (e.g. AFFINE·DROP) is legal but
 * still reports errorCode=6 (verify_failed) because Bitcoin-Script requires
 * a truthy TOS at the end. That's a script-verdict concern, not a linearity
 * concern — we don't surface it as a violation.
 */
function isLegal(result: ScriptResult): boolean {
  return result.linearityError === 'none';
}

function formatReadout(
  recipe: CellRecipe,
  result: ScriptResult,
  extra?: string,
): string {
  const legal = isLegal(result);
  const verdict = legal ? 'legal' : 'violation';
  const err = result.linearityError !== 'none'
    ? `\nerror:     ${result.linearityError}`
    : '';
  return (
    `${recipe.linearity.toUpperCase()}  op: ${recipe.op.toUpperCase()}\n` +
    `${recipe.description}\n\n` +
    `verdict:   ${verdict}\n` +
    `opcount:   ${result.opcodeCount}${err}` +
    (extra ? `\n${extra}` : '')
  );
}

// ── script builder ───────────────────────────────────────────────────

function buildScript(recipe: CellRecipe, eng: MinimalCellEngine): Uint8Array {
  const selfCell = eng.packCell(recipe.linearity);

  if (recipe.op === 'dup') return concatScript(pushCellScript(selfCell), new Uint8Array([OP_DUP]));
  if (recipe.op === 'drop') return concatScript(pushCellScript(selfCell), new Uint8Array([OP_DROP]));

  // merge: push self, push partner, push name "merge", OP_CALLHOST.
  // OP_CALLHOST pops the top as the host-function name (see hostcall.zig).
  const partnerId = recipe.mergeWith!;
  const partnerIdx = idToIdx.get(partnerId);
  const partnerRecipe = partnerIdx !== undefined ? CELL_RECIPES[partnerIdx] : recipe;
  const partnerCell = eng.packCell(partnerRecipe.linearity);
  const nameBytes = new TextEncoder().encode('merge');
  return concatScript(
    pushCellScript(selfCell),
    pushCellScript(partnerCell),
    pushBytesScript(nameBytes),
    new Uint8Array([OP_CALLHOST]),
  );
}

// ── click → execute → animate ────────────────────────────────────────

function executeCube(state: CubeState): void {
  if (!engine) return;
  if (state.extinguished) {
    showReadout(
      `${state.recipe.linearity.toUpperCase()} · already consumed\n\n` +
      `LINEAR/AFFINE cells are gone once used.\nHit "reset scene" to bring them back.`,
      { violation: false },
    );
    return;
  }

  // For a conductor merge, arm the callback the host fn will invoke.
  if (state.recipe.op === 'merge') {
    const partnerIdx = idToIdx.get(state.recipe.mergeWith!);
    mergeInProgress = () => {
      if (partnerIdx === undefined) return;
      const partner = cubes[partnerIdx];
      const midpoint = new THREE.Vector3()
        .addVectors(state.homePosition, partner.homePosition)
        .multiplyScalar(0.5);
      state.mergeTarget = midpoint.clone();
      partner.mergeTarget = midpoint.clone();
    };
  }

  let result: ScriptResult;
  try {
    engine.setEnforcement(enforceToggle.checked);
    const script = buildScript(state.recipe, engine);
    result = engine.executeScript(script);
  } catch (err) {
    showReadout(`error: ${err instanceof Error ? err.message : String(err)}`, { violation: true });
    mergeInProgress = null;
    return;
  } finally {
    // Clear the merge callback if the host fn didn't fire (e.g. on error).
    mergeInProgress = null;
  }

  playAnimation(state, result);
  showReadout(formatReadout(state.recipe, result), { violation: !isLegal(result) });
}

function playAnimation(state: CubeState, result: ScriptResult): void {
  if (result.linearityError !== 'none') {
    // Shatter: red flash + shake + remain at home. The cell is still on the
    // stack per K4 (failure atomicity) — we surface that by keeping the cube.
    state.shatterPhase = 1;
    state.spin = Math.PI * 0.35;
    return;
  }

  // Linearity-legal path: pick animation by operation.
  switch (state.recipe.op) {
    case 'dup':
      // Mitosis: spawn a transient clone that drifts off.
      spawnSplitChild(state);
      state.spin = Math.PI * 0.6;
      break;

    case 'drop':
      // Silent fade — AFFINE's defining legal move.
      state.alpha = Math.max(0, state.alpha - 0.001); // seed the anim in tick
      state.extinguished = true;
      state.spin = Math.PI * 0.12;
      break;

    case 'merge':
      // mergeTarget already set by the host.merge callback.
      state.spin = Math.PI * 1.0;
      break;
  }
}

function spawnSplitChild(state: CubeState): void {
  if (state.splitChild) {
    scene.remove(state.splitChild);
  }
  const mat = (state.mesh.material as THREE.MeshStandardMaterial).clone();
  const child = new THREE.Mesh(state.mesh.geometry, mat);
  child.position.copy(state.mesh.position);
  child.userData.isSplit = true;
  scene.add(child);
  state.splitChild = child;
  state.splitPhase = 1; // 1 → 0 in tick
}

// ── interaction ──────────────────────────────────────────────────────

const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2();

canvas.addEventListener('click', (ev) => {
  pointer.x = (ev.clientX / window.innerWidth) * 2 - 1;
  pointer.y = -(ev.clientY / window.innerHeight) * 2 + 1;
  raycaster.setFromCamera(pointer, camera);
  const hits = raycaster.intersectObjects(RAYCAST_TARGETS, false);
  if (hits.length > 0) {
    const idx = hits[0].object.userData.idx as number;
    executeCube(cubes[idx]);
  }
});

enforceToggle.addEventListener('change', () => {
  if (engine) engine.setEnforcement(enforceToggle.checked);
  showReadout(
    enforceToggle.checked
      ? 'K1 enforcement on — linearity rules apply'
      : 'K1 enforcement OFF — the kernel no longer rejects illegal moves.\nWatch DUP/DROP succeed where they shouldn\'t.',
    { violation: !enforceToggle.checked },
  );
});

resetBtn.addEventListener('click', () => {
  buildCubes();
  showReadout('scene reset', { violation: false });
});

// ── animation loop ───────────────────────────────────────────────────

const tmpColor = new THREE.Color();

function tick(): void {
  for (const c of cubes) {
    const mat = c.mesh.material as THREE.MeshStandardMaterial;

    // alpha → material opacity (for consume/drop fade-out)
    if (c.extinguished) {
      c.alpha += (0 - c.alpha) * 0.08;
    } else {
      c.alpha += (1 - c.alpha) * 0.12;
    }
    mat.opacity = c.alpha;
    mat.visible = c.alpha > 0.02;

    // shatter: flash red, shake, decay
    if (c.shatterPhase > 0) {
      tmpColor.copy(c.baseColor).lerp(SHATTER_COLOR, c.shatterPhase);
      mat.color.copy(tmpColor);
      const jitter = c.shatterPhase * 0.08;
      c.mesh.position.x = c.homePosition.x + (Math.random() - 0.5) * jitter;
      c.mesh.position.y = c.homePosition.y + (Math.random() - 0.5) * jitter;
      c.shatterPhase = Math.max(0, c.shatterPhase - 0.04);
      if (c.shatterPhase === 0) {
        c.mesh.position.copy(c.homePosition);
      }
    } else {
      mat.color.lerp(c.baseColor, 0.08);
    }

    // merge glide toward target
    if (c.mergeTarget) {
      c.mesh.position.lerp(c.mergeTarget, 0.06);
      c.mesh.scale.multiplyScalar(0.985);
      if (c.mesh.scale.x < 0.15) {
        // merge complete — mark this cube extinguished; partner will too.
        c.extinguished = true;
        c.mergeTarget = null;
        c.mesh.scale.set(1, 1, 1);
      }
    }

    // spin remaining
    if (c.spin > 0) {
      const step = Math.min(c.spin, 0.07);
      c.mesh.rotation.y += step;
      c.spin -= step;
    }

    // split child drifts up-and-away then fades
    if (c.splitChild && c.splitPhase > 0) {
      const dir = new THREE.Vector3(0.6, 0.9, 0);
      c.splitChild.position.addScaledVector(dir, 0.015);
      c.splitChild.rotation.y += 0.04;
      const childMat = c.splitChild.material as THREE.MeshStandardMaterial;
      childMat.opacity = c.splitPhase;
      c.splitPhase = Math.max(0, c.splitPhase - 0.012);
      if (c.splitPhase === 0) {
        scene.remove(c.splitChild);
        c.splitChild = null;
      }
    }
  }

  renderer.render(scene, camera);
  requestAnimationFrame(tick);
}

void initEngine();
tick();

```
