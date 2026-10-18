# Character export

The viewer exports the loaded **LBA1, LBA2, or 1996 LBA2 demo** body and its associated animations. Retail LBA2 exports use the scene palette currently selected in the viewer; Citadel clear/indoors is the default, and rain or island palettes can be selected before export. LBA1's actor shadow is exported only while its Shadow toggle is on. The display platform, camera, wireframe overlay, and UI are excluded from GLB.

## In the viewer

On desktop, choose **Export GLB** or **Export Blender** after loading a character. The Blender button runs an installed `blender` executable; set `LBA_BLENDER` to a different executable path if needed. On the web, choose an LBA1 or LBA2 game folder containing BODY.HQR, ANIM.HQR and RESS.HQR; FILE3D.HQR is also needed for LBA1 and the 1996 LBA2 demo. Then use **Export GLB**. The archives stay in browser memory and are not sent to the host. The hosted viewer is at https://jvetulani.github.io/LBAModelRenderer/.

Portable Windows and Linux builds, with setup instructions, are described in [desktop_builds.md](desktop_builds.md).

For a Pages release, run `python3 tools/prepare_pages.py WEB_EXPORT_DIR EMPTY_OUTPUT_DIR` after the Godot web export, then publish the prepared directory at the root of `gh-pages`. The script gives the `.pck` a content-based filename so a browser cannot reuse an older cached game pack after the page updates.

The web build cannot create `.blend` files directly because Blender is a desktop application. To turn a downloaded GLB into an editable Eevee scene, run:

```bash
blender -b --factory-startup --python tools/import_lba1_glb.py -- character.glb character.blend
```

## What is preserved

- A 256-colour source VGA palette is embedded as a nearest-filtered texture. Fractional palette coordinates are retained in UVs for Blender's reconstructed material.
- Polygons, sphere triangles and capped rectangular-prism lines share one skinned mesh. Each point is weighted to its original LBA1 group, including polygons that span groups.
- Every distinct associated ANIM resource is exported. Clips with a nonzero source loop frame also get a `*_loop` clip. A GLB therefore may have more clips than source actions.
- The actor shadow is a separate alpha-masked mesh with its source sprite image embedded.

The standard GLB uses a portable unlit palette material and shows stepped palette shading. glTF does not carry Godot's custom shader. The Blender conversion replaces the material with an Eevee node graph that uses the packed palette plus a resolution-aware 4×4 screen-space dither texture. It is an approximation: the original LBA1 scanline carry and low-byte rotation are not reproduced by Eevee's node graph. Every imported action channel gets a repeating Cycles modifier; source `*_loop` actions retain their dedicated loop segment. Idle is selected as the active Blender action when the source provides it. The Blender file also has a replaceable, palette-lit platform using the same character material and a preview camera. Both `.glb` and `.blend` files contain character data from the user's game installation; keep them out of the public site repository.
