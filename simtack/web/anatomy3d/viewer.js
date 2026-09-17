// Real 3D BodyParts3D tap-to-region picking. This same file serves two
// purposes: (1) opened directly in a browser, it's a standalone validation
// harness — same test-first pattern this codebase already used for the 2D
// zoom kits (hand_tap.html, foot_tap.html, etc.); (2) embedded in an
// `<iframe>` by the Flutter app's Anatomy3DTapView, it's the real
// patient-facing 3D body.
//
// On a successful tap this posts a message to the PARENT window via
// `window.parent.postMessage` — `{type:'atomybridge-bodypart', part: <one
// of the 14 KB region strings>, partName, x, y}` — which
// web_interop_web.dart listens for via a `message` event.
//
// This matters specifically because of the iframe boundary: an earlier
// version of this file used `window.dispatchEvent(new CustomEvent(...))`,
// which only reaches listeners on the SAME window. An iframe has its own
// separate `window` object from the page embedding it, so that dispatch
// never reached the parent Flutter app at all — every tap resolved
// correctly inside this file (visible in the debug panel), but nothing
// outside the iframe ever found out. `postMessage` is the correct
// mechanism for crossing that boundary; a plain DOM event is not.
//
// `?embedded=1` (set automatically by Anatomy3DTapView) hides the debug
// panel (model dropdown, skin toggle, status/result text) — that's
// developer-facing UI for testing this file standalone, not something a
// patient should see once gender has already been chosen on the previous
// screen and postMessage is doing the real reporting.

import * as THREE from './vendor/three/three.module.js';
import { OrbitControls } from './vendor/three/addons/controls/OrbitControls.js';
import { resolveKbRegion } from './region-map.js';

// This is a general pain-triage app, not an anatomy course — reproductive
// organs and the pregnancy/placenta reference set (the latter hidden by
// default even in the upstream human-atlas viewer itself) have no
// corresponding KB region and aren't appropriate to surface by default, so
// they're skipped entirely rather than just hidden.
const EXCLUDED_SYSTEMS = new Set(['reproductive', 'pregnancy']);

// A few vessels/nerves that directly serve reproductive organs are tagged
// under their own system (e.g. "Deep dorsal vein of penis" is 'venous',
// not 'reproductive') rather than the organ's system, so the exclusion
// above alone still leaves them poking through the skin surface. Catch
// those by name instead, on top of the system-level exclusion.
const EXCLUDED_NAME_PATTERN = /\b(penis|scrotum|testis|testicle|epididymis|vas deferens|spermatic|prepuce|glans|seminal vesicle)\b/i;

const statusEl = document.getElementById('status');
const resultEl = document.getElementById('result');
const genderSelect = document.getElementById('gender');
const skinToggle = document.getElementById('skin-toggle');

// Anatomy3DTapView passes ?embedded=1 for the real patient-facing view —
// this debug panel (model dropdown, skin toggle, raw status/result text)
// is developer-facing, for testing this file standalone; a patient has
// already picked their gender on the previous screen and doesn't need or
// want to see internal picking debug output.
if (new URLSearchParams(location.search).get('embedded') === '1') {
  document.getElementById('panel').hidden = true;
}

const SYSTEM_COLORS = {
  skeletal: '#e2d9ba', muscular: '#a85b50', cardiac: '#b96760',
  sensory: '#b0c8ce', arterial: '#c05245', venous: '#527c9f',
  nervous: '#d8b565', respiratory: '#b98991', digestive: '#b8916b',
  urinary: '#b47961', lymphatic: '#879f7c', endocrine: '#c5a09a',
  reproductive: '#bda098', integumentary: '#e8c39e', connective: '#aec3bb',
  mammary: '#d8bd82', pregnancy: '#b88380',
};

const scene = new THREE.Scene();
scene.background = new THREE.Color('#f2f3f3');
const camera = new THREE.PerspectiveCamera(34, innerWidth / innerHeight, 0.01, 100);
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setSize(innerWidth, innerHeight);
renderer.outputColorSpace = THREE.SRGBColorSpace;
document.getElementById('canvas-host').appendChild(renderer.domElement);

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.target.set(0, 0.9, 0);
camera.position.set(1.2, 1.1, 2.6);
controls.update();

scene.add(new THREE.HemisphereLight(0xffffff, 0xa7acb2, 1.1));
const key = new THREE.DirectionalLight(0xfffaf4, 2.2);
key.position.set(-2, 4, 3);
scene.add(key);
const rim = new THREE.DirectionalLight(0xe9f0ff, 1.4);
rim.position.set(2, 2, -3);
scene.add(rim);

let currentMeshes = [];
let currentParts = [];
let overallBounds = null;
let modestyPatch = null;

// The male model's genital anatomy is sculpted directly into the skin
// surface mesh itself (confirmed: excluding the reproductive-system organs
// and their vessels, above, left it fully visible — it isn't a separate
// mesh poking through, it's part of "Skin" itself). That can't be excluded
// the way separate organs can, so instead this covers that exact spot with
// a plain skin-toned patch.
//
// The real anatomy's own measured bounding box (organs + pubic hair,
// unioned directly from atlas.json) is x:[-0.0618,0.0600]
// y:[0.7679,0.9070] z:[-0.0451,0.1009] — note the z range: to hide the
// front-most point (z=0.1009) the patch's own front face must reach at
// least that far forward, or the real geometry simply pokes out past it
// and stays fully visible (this is exactly what happened when depth was
// cut to 0.07 centered near z=0.02 — its front face only reached z=0.055,
// short of 0.1009, so it sat fully hidden inside the body with no visible
// effect at all). Depth is therefore kept close to the real z-span. Width
// and height, which had generous padding before, are tightened down to a
// small margin over the measured footprint instead — that's the axis
// where an earlier attempt was genuinely oversized.
const MODESTY_PATCH_BOUNDS = {
  center: [-0.0009, 0.8375, 0.028],
  size: [0.10, 0.145, 0.15],
};

function addModestyPatch(skinColor) {
  const geometry = new THREE.SphereGeometry(0.5, 24, 16);
  const material = new THREE.MeshStandardMaterial({ color: skinColor, metalness: 0.05, roughness: 0.6 });
  const mesh = new THREE.Mesh(geometry, material);
  mesh.scale.set(...MODESTY_PATCH_BOUNDS.size);
  mesh.position.set(...MODESTY_PATCH_BOUNDS.center);
  // Deliberately not pushed into currentMeshes — it must stay untappable
  // (invisible to the raycaster) so a tap there passes through to the real
  // skin surface underneath and resolves via the normal region logic.
  scene.add(mesh);
  modestyPatch = mesh;
}

async function decodeChunk(chunk) {
  const requestedUrl = chunk.gzip || chunk.url;
  const res = await fetch(requestedUrl);
  // Report the URL actually requested, not always chunk.url — this
  // previously showed "Failed to fetch .../body-0.bin" even when the real
  // (gzip) request was what failed, which sent debugging in the wrong
  // direction once.
  if (!res.ok) throw new Error(`Failed to fetch ${requestedUrl} (${res.status})`);
  const payload = await res.arrayBuffer();
  const sig = new Uint8Array(payload, 0, 2);
  const isGzip = sig[0] === 0x1f && sig[1] === 0x8b;
  if (!isGzip) return payload;
  const stream = new Blob([payload]).stream().pipeThrough(new DecompressionStream('gzip'));
  return await new Response(stream).arrayBuffer();
}

function computeOverallBounds(parts) {
  const min = [Infinity, Infinity, Infinity];
  const max = [-Infinity, -Infinity, -Infinity];
  for (const p of parts) {
    for (let i = 0; i < 3; i++) {
      min[i] = Math.min(min[i], p.bounds[0][i]);
      max[i] = Math.max(max[i], p.bounds[1][i]);
    }
  }
  return [min, max];
}

function clearScene() {
  for (const m of currentMeshes) {
    m.geometry.dispose();
    m.material.dispose();
    scene.remove(m);
  }
  currentMeshes = [];
  currentParts = [];
  if (modestyPatch) {
    modestyPatch.geometry.dispose();
    modestyPatch.material.dispose();
    scene.remove(modestyPatch);
    modestyPatch = null;
  }
}

async function loadAtlas(name) {
  statusEl.textContent = `Loading ${name} atlas…`;
  clearScene();
  resultEl.textContent = '(no tap yet)';

  const atlas = await (await fetch(`models/${name === 'female' ? 'atlas-female.json' : 'atlas.json'}`)).json();
  currentParts = atlas.parts;
  overallBounds = computeOverallBounds(atlas.parts);

  // Build a lookup once instead of scanning all parts per chunk (O(parts)
  // per chunk was fine at this scale, but grouping up front keeps chunk
  // processing strictly proportional to that chunk's own part count).
  const partsByChunk = new Map();
  atlas.parts.forEach((p, i) => {
    const list = partsByChunk.get(p.chunk) ?? [];
    list.push(i);
    partsByChunk.set(p.chunk, list);
  });

  let loaded = 0;
  const addChunkGeometry = (chunkIndex, buffer) => {
    for (const i of partsByChunk.get(chunkIndex) ?? []) {
      const p = atlas.parts[i];
      if (EXCLUDED_SYSTEMS.has(p.system) || EXCLUDED_NAME_PATTERN.test(p.name)) continue;
      const geometry = new THREE.BufferGeometry();
      geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(buffer, p.positions, p.vertexCount * 3), 3));
      geometry.setAttribute('normal', new THREE.BufferAttribute(new Int16Array(buffer, p.normals, p.vertexCount * 3), 3, true));
      geometry.setIndex(new THREE.BufferAttribute(new Uint32Array(buffer, p.indices, p.indexCount), 1));
      const isSkin = p.system === 'integumentary';
      // Skin renders fully opaque by default — this is the patient-facing
      // surface view (like the existing 2D body map), not an x-ray. The
      // "Show skin" checkbox fully hides the skin mesh (see the change
      // listener below) when someone wants to inspect organs underneath;
      // it does not partially fade it, which previously made every part
      // look see-through regardless of the checkbox.
      const material = new THREE.MeshStandardMaterial({
        color: SYSTEM_COLORS[p.system] || '#c9b7a6',
        metalness: 0.05,
        roughness: 0.6,
        side: THREE.DoubleSide,
      });
      const mesh = new THREE.Mesh(geometry, material);
      mesh.userData.partIndex = i;
      mesh.visible = !isSkin || skinToggle.checked;
      scene.add(mesh);
      currentMeshes.push(mesh);
    }
    loaded++;
    statusEl.textContent = `Loading ${name} atlas… chunk ${loaded}/${atlas.chunks.length}`;
  };

  // Three concurrent fetch/decode workers, matching the proven upstream
  // loader — sequential one-at-a-time loading (the first version of this
  // harness) measurably serializes network + DecompressionStream + geometry
  // build time per chunk instead of overlapping them.
  let cursor = 0;
  await Promise.all(Array.from({ length: 3 }, async () => {
    while (cursor < atlas.chunks.length) {
      const chunkIndex = cursor++;
      const buffer = await decodeChunk(atlas.chunks[chunkIndex]);
      addChunkGeometry(chunkIndex, buffer);
    }
  }));
  if (name !== 'female') addModestyPatch(SYSTEM_COLORS.integumentary);
  statusEl.textContent = `${name} atlas loaded — ${currentParts.length} parts, ${currentMeshes.length} meshes.`;
}

skinToggle.addEventListener('change', () => {
  for (const m of currentMeshes) {
    const part = currentParts[m.userData.partIndex];
    if (part.system === 'integumentary') m.visible = skinToggle.checked;
  }
  if (modestyPatch) modestyPatch.visible = skinToggle.checked;
});

genderSelect.addEventListener('change', () => loadAtlas(genderSelect.value));

// The embedding app (Flutter's Anatomy3DTapView) passes the current
// patient's gender via ?gender=male|female so the right atlas loads
// immediately, instead of always starting on male and requiring a manual
// dropdown change every time.
const initialGender = new URLSearchParams(location.search).get('gender') === 'female' ? 'female' : 'male';
genderSelect.value = initialGender;
loadAtlas(initialGender);

const raycaster = new THREE.Raycaster();
const pointerNDC = new THREE.Vector2();
const projected = new THREE.Vector3();
let downPos = null;

// Fallback for when the exact ray misses everything — ported from the
// same technique the upstream human-atlas viewer uses (its own `findTarget`
// in app/scene.tsx), because several real structures here are only a
// centimeter or two across (a cornea is ~1.4cm, a toe bone under 1.3cm).
// At normal zoom that's a handful of screen pixels, so triangle-exact
// raycasting reliably misses even a well-aimed click — this was reported
// directly: taps on eyes/ears/nose/mouth/toes were registering as nothing
// at all, not as the wrong region. This scans every rendered part's own
// bounds-center in screen space and snaps to the nearest one within a
// small pixel radius, the same "near enough counts" behavior the proven
// upstream picker relies on for exactly these small structures.
function findNearestPartByScreen(clientX, clientY, rect, maxPixelDist) {
  let best = -1;
  let bestDist = maxPixelDist;
  for (const mesh of currentMeshes) {
    if (!mesh.visible) continue;
    const part = currentParts[mesh.userData.partIndex];
    const cx = (part.bounds[0][0] + part.bounds[1][0]) / 2;
    const cy = (part.bounds[0][1] + part.bounds[1][1]) / 2;
    const cz = (part.bounds[0][2] + part.bounds[1][2]) / 2;
    projected.set(cx, cy, cz).project(camera);
    if (projected.z < -1 || projected.z > 1) continue; // behind the camera / clipped
    const sx = ((projected.x + 1) / 2) * rect.width + rect.left;
    const sy = ((1 - projected.y) / 2) * rect.height + rect.top;
    const dist = Math.hypot(sx - clientX, sy - clientY);
    if (dist < bestDist) {
      bestDist = dist;
      best = mesh.userData.partIndex;
    }
  }
  return best;
}

renderer.domElement.addEventListener('pointerdown', (e) => {
  downPos = { x: e.clientX, y: e.clientY };
});

renderer.domElement.addEventListener('pointerup', (e) => {
  if (!downPos) return;
  const moved = Math.hypot(e.clientX - downPos.x, e.clientY - downPos.y);
  downPos = null;
  if (moved > 6) return; // treat as an orbit drag, not a tap

  const rect = renderer.domElement.getBoundingClientRect();
  pointerNDC.set(
    ((e.clientX - rect.left) / rect.width) * 2 - 1,
    -((e.clientY - rect.top) / rect.height) * 2 + 1
  );
  raycaster.setFromCamera(pointerNDC, camera);
  const visibleMeshes = currentMeshes.filter((m) => m.visible);
  const hits = raycaster.intersectObjects(visibleMeshes, false);

  let part, hitPoint, snapped = false;
  if (hits.length > 0) {
    const hit = hits[0];
    part = currentParts[hit.object.userData.partIndex];
    // hit.point is the actual 3D point the ray struck, in the same
    // coordinate space as part.bounds (meshes here carry no extra
    // transform). This matters most for the whole-body skin mesh, which
    // spans the entire figure — using the part's own aggregate bounds
    // instead of the real tap point was the original bug (every skin tap
    // resolved to the same region). See region-map.js for the full
    // explanation.
    hitPoint = [hit.point.x, hit.point.y, hit.point.z];
  } else {
    // The exact ray hit nothing — likely a natural opening in the skin
    // mesh (eye socket, nostril, ear canal, mouth) or a very small
    // structure (a cornea, a toe bone) that a pixel-exact ray easily
    // slips past. Snap to the nearest part's own center within a small
    // screen-space radius instead of reporting no result at all.
    const nearestIndex = findNearestPartByScreen(e.clientX, e.clientY, rect, 22);
    if (nearestIndex < 0) return;
    part = currentParts[nearestIndex];
    hitPoint = [
      (part.bounds[0][0] + part.bounds[1][0]) / 2,
      (part.bounds[0][1] + part.bounds[1][1]) / 2,
      (part.bounds[0][2] + part.bounds[1][2]) / 2,
    ];
    snapped = true;
  }

  const region = resolveKbRegion(part, hitPoint, overallBounds);

  const normX = (e.clientX - rect.left) / rect.width;
  const normY = (e.clientY - rect.top) / rect.height;

  resultEl.innerHTML = `<strong>${part.name}</strong> <span class="muted">(${part.system}${snapped ? ', snapped to nearest' : ''})</span><br>resolved region: <strong>${region}</strong>`;

  // `part` stays the resolved KB region (one of the 14 strings the backend
  // understands, unchanged contract) — `partName` carries the precise
  // anatomical structure that was actually tapped (e.g. "Distal phalanx of
  // left index finger"), for the app to show the patient a more specific
  // label than the coarse region alone, without changing what gets sent to
  // /anatomy/ask.
  //
  // postMessage, not a same-window CustomEvent: when this page is embedded
  // in an iframe (the real, patient-facing case), `window` here is the
  // IFRAME's own window, not the Flutter app's — a dispatchEvent on it
  // never reaches anything outside the iframe. window.parent is always
  // reachable and resolves to the embedding page (or to this same window
  // when not embedded at all, i.e. the standalone harness use case, where
  // it's a harmless no-op since nothing listens for it there).
  window.parent.postMessage({
    type: 'atomybridge-bodypart',
    part: region,
    partName: part.name,
    x: normX,
    y: normY,
  }, '*');
});

function resize() {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
}
addEventListener('resize', resize);

function animate() {
  requestAnimationFrame(animate);
  controls.update();
  renderer.render(scene, camera);
}
animate();
