// Exhaustive coverage test for region-map.js: every single part in both the
// male and female BodyParts3D atlases must resolve to one of the app's
// fixed KB region strings (29 as of the joint-based arm/leg split — see
// KB_REGIONS), with no exceptions and no unmapped output — the same
// guarantee the approved implementation plan's verification step called
// for originally, at the smaller 14-region scope.
//
// Run: node region-map.test.mjs

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { resolveKbRegion, KB_REGIONS } from './region-map.js';

const here = dirname(fileURLToPath(import.meta.url));
const VALID_REGIONS = new Set(Object.values(KB_REGIONS));

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

function centerOf(part) {
  return [
    (part.bounds[0][0] + part.bounds[1][0]) / 2,
    (part.bounds[0][1] + part.bounds[1][1]) / 2,
    (part.bounds[0][2] + part.bounds[1][2]) / 2,
  ];
}

// Also probe the whole-body skin part (a single mesh spanning the entire
// figure) at many different points across its own bounding box, not just
// its own center — this is the exact scenario that produced the original
// bug (every skin tap resolving to the same region regardless of where it
// was actually tapped), so coverage here matters more than for any single
// small named part.
function sampleSkinGrid(overallBounds, steps = 12) {
  const [min, max] = overallBounds;
  const points = [];
  for (let iy = 0; iy <= steps; iy++) {
    for (let ix = 0; ix <= steps; ix++) {
      for (const iz of [0, 0.5, 1]) {
        points.push([
          min[0] + ((max[0] - min[0]) * ix) / steps,
          min[1] + ((max[1] - min[1]) * iy) / steps,
          min[2] + ((max[2] - min[2]) * iz),
        ]);
      }
    }
  }
  return points;
}

let failures = 0;
let checked = 0;
const distribution = new Map();

function record(region) {
  distribution.set(region, (distribution.get(region) ?? 0) + 1);
}

// Targeted regression case: "axillary" (real BodyParts3D name for the
// armpit vessels) must resolve to Armpit, and "maxilla" (the jaw bone,
// which contains "axilla" as a literal substring — m|AXILLA) must NOT.
// Caught once already by a naive fix; worth pinning down explicitly.
{
  const fakeBounds = [[0, 0, 0], [1, 1, 1]];
  const axillary = resolveKbRegion({ name: 'Left axillary artery' }, [0, 0, 0], fakeBounds);
  const maxilla = resolveKbRegion({ name: 'Left maxilla' }, [0, 0, 0], fakeBounds);
  checked += 2;
  if (axillary !== KB_REGIONS.ARMPIT_LEFT) {
    failures++;
    console.error(`FAIL: "Left axillary artery" resolved to "${axillary}", expected "${KB_REGIONS.ARMPIT_LEFT}"`);
  }
  if (maxilla !== KB_REGIONS.HEAD) {
    failures++;
    console.error(`FAIL: "Left maxilla" resolved to "${maxilla}", expected "${KB_REGIONS.HEAD}" (must NOT be misread as armpit via the "axilla" substring)`);
  }
}

for (const [label, file] of [['male', 'atlas.json'], ['female', 'atlas-female.json']]) {
  const atlas = JSON.parse(readFileSync(join(here, 'models', file), 'utf8'));
  const overallBounds = computeOverallBounds(atlas.parts);

  // 1. Every named part, at its own bounds center.
  for (const part of atlas.parts) {
    const region = resolveKbRegion(part, centerOf(part), overallBounds);
    checked++;
    record(region);
    if (!VALID_REGIONS.has(region)) {
      failures++;
      console.error(`[${label}] FAIL: part "${part.name}" (system=${part.system}) resolved to invalid region "${region}"`);
    }
  }

  // 2. The whole-body skin part specifically, sampled across a grid of real
  // tap points, not just its own center — the regression case that matters.
  const skinPart = atlas.parts.find((p) => p.system === 'integumentary' && p.name.toLowerCase().includes('body') || p.name.toLowerCase() === 'skin');
  const skinLike = skinPart ?? atlas.parts.find((p) => p.system === 'integumentary');
  if (!skinLike) {
    failures++;
    console.error(`[${label}] FAIL: no integumentary (skin) part found to grid-test`);
  } else {
    const gridRegions = new Set();
    for (const point of sampleSkinGrid(overallBounds)) {
      const region = resolveKbRegion(skinLike, point, overallBounds);
      checked++;
      record(region);
      gridRegions.add(region);
      if (!VALID_REGIONS.has(region)) {
        failures++;
        console.error(`[${label}] FAIL: skin grid point ${JSON.stringify(point)} resolved to invalid region "${region}"`);
      }
    }
    // A real skin surface covering the whole body should resolve to a
    // healthy spread of different regions across the grid, not collapse to
    // one value everywhere — that collapse was exactly the original bug.
    if (gridRegions.size < 6) {
      failures++;
      console.error(`[${label}] FAIL: skin grid only produced ${gridRegions.size} distinct region(s) — expected a wide spread across the body: ${[...gridRegions].join(', ')}`);
    } else {
      console.log(`[${label}] skin grid produced ${gridRegions.size} distinct regions (good — not collapsed to one value)`);
    }
  }
}

console.log(`\nChecked ${checked} resolutions across both atlases.`);
console.log('Region distribution:');
for (const [region, count] of [...distribution.entries()].sort((a, b) => b[1] - a[1])) {
  console.log(`  ${String(count).padStart(6)}  ${region}`);
}

if (failures > 0) {
  console.error(`\n${failures} FAILURE(S).`);
  process.exit(1);
} else {
  console.log(`\nAll ${checked} resolutions returned a valid KB region. PASS.`);
}
