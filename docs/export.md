# LBA1 character export

The viewer exports the loaded **LBA1** body, its source-associated animations and the actor shadow. The display platform, camera and UI are excluded from GLB. LBA2 export is not implemented.

## In the viewer

On desktop, choose **Export GLB** or **Export Blender** after loading a character. The Blender button runs an installed `blender` executable; set `LBA_BLENDER` to a different executable path if needed. On the web, select BODY.HQR, ANIM.HQR, FILE3D.HQR and RESS.HQR together, then use **Export GLB**. The archives stay in browser memory and are not sent to the host.

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
