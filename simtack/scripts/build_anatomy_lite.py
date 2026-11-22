"""Build the fast first-paint atlases for the embedded 3D body viewer.

The full BodyParts3D atlas is ~33 MB (male) / ~24 MB (female) of compressed
geometry. Streaming that before a patient can see a body is the reason the
viewer felt slow. The full atlas already contains a small set of skin
(`integumentary`) meshes, and those meshes are all the viewer needs for its
first useful frame: taps on skin are resolved by 3D position in
`region-map.js`, not by the mesh name.

This script pulls just those skin meshes out of the existing compressed
chunks, repacks them into one small chunk, and writes a manifest in exactly
the same shape the viewer already understands. No geometry is invented, no
rule is changed, and the full atlases are left untouched — the viewer shows
the lite atlas first and then upgrades to the full one in the background.

Run from the repo root:

    python3 simtack/scripts/build_anatomy_lite.py

Outputs (both tracked):

    simtack/web/anatomy3d/models/atlas-lite-male.json
    simtack/web/anatomy3d/models/skin-male.bin.gz
    simtack/web/anatomy3d/models/atlas-lite-female.json
    simtack/web/anatomy3d/models/skin-female.bin.gz
"""

from __future__ import annotations

import gzip
import json
from pathlib import Path

MODELS = Path(__file__).resolve().parent.parent / "web" / "anatomy3d" / "models"

SOURCES = (
    ("male", "atlas.json", "atlas-lite-male.json", "skin-male.bin.gz"),
    ("female", "atlas-female.json", "atlas-lite-female.json", "skin-female.bin.gz"),
)

# Same pattern viewer.js uses to keep reproductive anatomy out of the
# patient-facing view. Kept here so a regenerated lite atlas cannot
# accidentally add geometry the full viewer deliberately excludes.
EXCLUDED_NAME_PATTERN = (
    "penis|scrotum|testis|testicle|epididymis|vas deferens|"
    "spermatic|prepuce|glans|seminal vesicle"
)


def _excluded(name: str) -> bool:
    lowered = name.lower()
    return any(word in lowered for word in EXCLUDED_NAME_PATTERN.split("|"))


def build(label: str, source_name: str, manifest_name: str, chunk_name: str) -> None:
    atlas = json.loads((MODELS / source_name).read_text())
    candidates = [
        part
        for part in atlas["parts"]
        if part.get("system") == "integumentary" and not _excluded(part.get("name", ""))
    ]
    if not candidates:
        raise RuntimeError(f"{source_name} has no integumentary parts")
    # One silhouette is enough for the first frame. The female atlas has
    # seventeen integumentary parts (mostly breast detail); carrying all of
    # them would more than double the first-paint payload for no gain in tap
    # accuracy, because the viewer resolves skin taps by 3D position. The full
    # atlas still loads in the background and restores every part.
    selected = [max(candidates, key=lambda part: part["vertexCount"])]

    # Chunks may be shared by several parts; decompress each only once.
    buffers: dict[int, bytes] = {}
    for part in selected:
        index = part["chunk"]
        if index in buffers:
            continue
        chunk = atlas["chunks"][index]
        path = MODELS.parent / chunk["gzip"]
        buffers[index] = gzip.decompress(path.read_bytes())

    # A part's geometry is one contiguous byte range: positions, normals and
    # indices laid end to end. Copying whole ranges keeps the strict
    # Float32/Int16/Uint32 alignment the viewer relies on; only the offsets in
    # the manifest change.
    pieces: list[tuple[int, bytes]] = []
    for part in selected:
        start = part["positions"]
        end = part["indices"] + part["indexCount"] * 4
        source = buffers[part["chunk"]]
        if start < 0 or end > len(source):
            raise RuntimeError(f"part {part['name']} has out-of-range offsets")
        pieces.append((part["chunk"], start, source[start:end]))

    pieces.sort(key=lambda item: (item[0], item[1]))
    packed = bytearray()
    remap: dict[tuple[int, int, int], int] = {}
    for (chunk_index, start, payload) in pieces:
        remap[(chunk_index, start, len(payload))] = len(packed)
        packed.extend(payload)

    parts = []
    for part in selected:
        start = part["positions"]
        end = part["indices"] + part["indexCount"] * 4
        offset = remap[(part["chunk"], start, end - start)]
        copy = dict(part)
        copy["chunk"] = 0
        copy["positions"] = offset + (part["positions"] - start)
        copy["normals"] = offset + (part["normals"] - start)
        copy["indices"] = offset + (part["indices"] - start)
        parts.append(copy)

    compressed = gzip.compress(bytes(packed), compresslevel=9)
    chunk_path = MODELS / chunk_name
    chunk_path.write_bytes(compressed)

    lite = {key: value for key, value in atlas.items() if key not in {"parts", "chunks", "triangles"}}
    lite["parts"] = parts
    lite["chunks"] = [
        {
            "url": f"models/{chunk_name[:-3]}",
            "bytes": len(packed),
            "gzip": f"models/{chunk_name}",
            "gzipBytes": len(compressed),
        }
    ]
    lite["triangles"] = sum(part["indexCount"] // 3 for part in parts)
    (MODELS / manifest_name).write_text(json.dumps(lite, separators=(",", ":")))

    source_mb = sum(c["gzipBytes"] for c in atlas["chunks"]) / 1024 / 1024
    print(
        f"{label}: {len(parts)} skin parts, "
        f"{source_mb:.1f} MB -> {len(compressed) / 1024:.0f} KB "
        f"({manifest_name}, {chunk_name})"
    )


def main() -> None:
    for args in SOURCES:
        build(*args)


if __name__ == "__main__":
    main()
