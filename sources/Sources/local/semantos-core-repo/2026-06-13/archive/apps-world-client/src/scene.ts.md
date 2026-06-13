---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/scene.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.819396+00:00
---

# archive/apps-world-client/src/scene.ts

```ts
import * as THREE from "three";

export interface SceneHandles {
  renderer: THREE.WebGLRenderer;
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  raycaster: THREE.Raycaster;
  pointer: THREE.Vector2;
  render(): void;
}

export function buildScene(canvas: HTMLCanvasElement): SceneHandles {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setPixelRatio(window.devicePixelRatio);
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.setClearColor(0x0a0a0b, 1);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;

  const scene = new THREE.Scene();
  scene.fog = new THREE.Fog(0x0a0a0b, 20, 60);

  const camera = new THREE.PerspectiveCamera(
    48,
    window.innerWidth / window.innerHeight,
    0.1,
    200,
  );
  camera.position.set(8, 9, 12);
  camera.lookAt(0, 0, 0);

  const ambient = new THREE.AmbientLight(0x223344, 0.6);
  scene.add(ambient);

  const key = new THREE.DirectionalLight(0xffffff, 1.1);
  key.position.set(6, 12, 6);
  key.castShadow = true;
  key.shadow.mapSize.set(1024, 1024);
  key.shadow.camera.top = 12;
  key.shadow.camera.bottom = -12;
  key.shadow.camera.left = -12;
  key.shadow.camera.right = 12;
  scene.add(key);

  const fill = new THREE.DirectionalLight(0x6688aa, 0.35);
  fill.position.set(-6, 4, -4);
  scene.add(fill);

  const grid = new THREE.GridHelper(40, 40, 0x223040, 0x141820);
  grid.position.y = 0;
  scene.add(grid);

  const ground = new THREE.Mesh(
    new THREE.PlaneGeometry(40, 40),
    new THREE.MeshStandardMaterial({ color: 0x0d1014, roughness: 0.95, metalness: 0 }),
  );
  ground.rotation.x = -Math.PI / 2;
  ground.receiveShadow = true;
  scene.add(ground);

  const axes = new THREE.AxesHelper(1.2);
  (axes.material as THREE.Material).transparent = true;
  (axes.material as THREE.Material).opacity = 0.35;
  scene.add(axes);

  const raycaster = new THREE.Raycaster();
  const pointer = new THREE.Vector2();

  window.addEventListener("resize", () => {
    renderer.setSize(window.innerWidth, window.innerHeight);
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
  });

  function render() {
    renderer.render(scene, camera);
  }

  return { renderer, scene, camera, raycaster, pointer, render };
}

```
