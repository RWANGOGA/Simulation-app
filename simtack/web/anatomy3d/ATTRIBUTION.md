# Anatomy data attribution

The 3D anatomy geometry in this directory (`models/atlas.json`, `models/atlas-female.json`,
and their `.bin`/`.bin.gz` chunk files) is derived from:

## BodyParts3D (male reference model)

BodyParts3D, © The Database Center for Life Science, licensed under
**CC Attribution 4.0 International**.

- License: https://dbarchive.biosciencedbc.jp/en/bodyparts3d/lic.html
- Dataset: https://dbarchive.biosciencedbc.jp/en/bodyparts3d/download.html
- License terms: https://creativecommons.org/licenses/by/4.0/
- Source geometry: `isa_BP3D_4.0_obj_99.zip`, BodyParts3D 4.0.
- Publication: Mitsuhashi et al. (2009), *BodyParts3D: 3D structure database
  for anatomical concepts*. https://doi.org/10.1093/nar/gkn613

BodyParts3D represents an adult male reference anatomy. It is not a complete
model of every human structure or variation, and this app's 3D view is an
aid for locating pain, not a diagnostic or clinical reference.

## Female model

The female geometry (`atlas-female.json`) additionally uses:

Kristen Browne and Heidi Schlehlein, Human Reference Atlas / HuBMAP,
*3D Reference Organ Set for Female v1.5* (2023). **CC BY 4.0**.

- Source DOI: https://doi.org/10.48539/HBM352.BTSQ.586
- License: https://creativecommons.org/licenses/by/4.0/

## Packaging / conversion tooling

Geometry compression (meshoptimizer simplification, normal quantization,
binary chunk packing) and the browser-loading approach were adapted from the
open-source **human-atlas** project (MIT License):

- https://github.com/wiiiimm/human-atlas

This app's own tap-to-region resolution (`region-map.js`), 3D viewer harness
(`viewer.html`/`viewer.js`), and the Flutter integration around them are
original to this project and are not part of human-atlas.

## Requirement

CC BY 4.0 requires attribution to remain reachable wherever this data ships.
This file must stay bundled with `models/`, and its content (or a link to it)
must be reachable from the app's About/Licenses screen before this 3D view
ships to users.
