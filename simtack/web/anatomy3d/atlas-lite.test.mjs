// Verifies the fast first-paint atlases are faithful extracts of the full
// BodyParts3D data. Run: node atlas-lite.test.mjs
//
// The viewer trusts these manifests to point at aligned Float32/Int16/Uint32
// ranges inside one compressed chunk. A stale or hand-edited manifest could
// point past the end of the buffer and abort the whole 3D body, so this test
// checks the offsets, the geometry counts, and that taps still resolve.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { resolveKbRegion, KB_REGIONS } from './region-map.js';

const here = dirname(fileURLToPath(import.meta.url));
const read = (name) => readFileSync(join(here, name));
const json = (name) => JSON.parse(read(name).toString());

const VALID = new Set(Object.values(KB_REGIONS));

for (const [label, fullName, liteName] of [
  ['male', 'models/atlas.json', 'models/atlas-lite-male.json'],
  ['female', 'models/atlas-female.json', 'models/atlas-lite-female.json'],
]) {
  const full = json(fullName);
  const lite = json(liteName);
  assert.equal(lite.parts.length, 1, `${label}: one silhouette for first paint`);
  assert.equal(lite.chunks.length, 1, `${label}: one compressed chunk`);

  const part = lite.parts[0];
  const original = full.parts.find((p) => p.name === part.name);
  assert.ok(original, `${label}: skin mesh comes from the full atlas`);
  assert.equal(part.system, 'integumentary');
  assert.equal(part.vertexCount, original.vertexCount);
  assert.equal(part.indexCount, original.indexCount);
  assert.deepEqual(part.bounds, original.bounds);

  const buffer = gunzipSync(read(lite.chunks[0].gzip));
  assert.equal(buffer.length, lite.chunks[0].bytes, `${label}: byte count matches`);
  const end = part.indices + part.indexCount * 4;
  assert.ok(end <= buffer.length, `${label}: geometry fits inside the chunk`);
  assert.equal(part.positions, 0);
  assert.equal(part.normals % 4, 0, `${label}: Int16 normals stay aligned`);
  assert.equal(part.indices % 4, 0, `${label}: Uint32 indices stay aligned`);
  assert.ok(part.normals >= part.positions + part.vertexCount * 3 * 4);
  assert.ok(part.indices >= part.normals + part.vertexCount * 3 * 2);

  const bounds = lite.parts.map((p) => p.bounds);
  const min = [0, 1, 2].map((i) => Math.min(...bounds.map((b) => b[0][i])));
  const max = [0, 1, 2].map((i) => Math.max(...bounds.map((b) => b[1][i])));
  for (const fx of [0.2, 0.5, 0.8]) {
    for (const fy of [0.2, 0.5, 0.8]) {
      for (const fz of [0.2, 0.5]) {
        const point = [0, 1, 2].map((i) => min[i] + (max[i] - min[i]) * [fx, fy, fz][i]);
        const region = resolveKbRegion(part, point, [min, max]);
        assert.ok(VALID.has(region), `${label}: resolved ${region} is a KB region`);
      }
    }
  }

  const kb = read(lite.chunks[0].gzip).length / 1024;
  console.log(`${label}: ${part.name}, ${kb.toFixed(0)} KB, offsets and taps OK`);
}
