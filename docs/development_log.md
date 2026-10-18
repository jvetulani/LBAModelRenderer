# Development log

## 2026-10-18 — first character path

- Inspected the supplied Godot project. It contained a `main.tscn`, not `main.trscene`; the existing scene was kept and given a script. The pre-existing Compatibility renderer setting was retained.
- Downloaded the original LBA1 and LBA2 source releases and TwinEngine into `/home/asia/Projekty/LBA/LBAModelVIewer/`, as requested. No source checkout or game archive was added to the Godot project.
- Confirmed Godot `4.8.beta1.official.4d10419ca`, local Ollama, and installed `llama3.1:8b` and `deepseek-r1:7b`. A narrow `llama3.1:8b` parser-review prompt suggested bounds checks; no unverified model output was incorporated. Source code, fixture decoding and Godot runtime results determined the implementation.
- Implemented bounded HQR extraction, static LBA1 animated-body parsing, an original-palette texture, native geometry and a spatial shader. Added a local-directory picker, archive entry control, orbit and zoom, and a display block.
- Ran the headless archive/body fixture and a GPU Compatibility scene capture with the user's local game archives. The capture is held in `/tmp/lba-body0-front-lit.png` for inspection and is not bundled in the project.

At this initial checkpoint, the first-action proof of concept worked. Phase 1 was partial; LBA2 models, full editor controls and fidelity comparison remained. Later sections record subsequent work.

## Correction after visual review

The initial screenshot was not a valid static pose. It rendered group-local point coordinates directly, which collapsed body parts around the origin. Tracing `P_OB_ISO.ASM` `RotateGroupe` and TwinEngine `processRotatedElement` showed that each group's points must be placed relative to a previously transformed pivot. The decoder now constructs that pose and checks group ranges and parents; the fixture verifies raw versus posed coordinates. The preview camera now frames the transformed height. Arbitrary Godot ambient light was removed and the UI labels the shader as preview lighting with no authentic dithering. The front-angle Compatibility capture is `/tmp/lba-body0-pose-corrected.png`. Historical shading, dither and matched-game comparison are still pending.

## Source-index shading and dither follow-up

- Replaced the arbitrary 0–11 lighting ramp with source-normal/divisor shading in palette-index space. Converted the palette to six-bit VGA DAC values and corrected the Godot light pass. The default source light vector is still approximate.
- Added Off, Source faces, and Full model dither modes. Source faces follows type-10 material tags. Full model also covers Twinsen's Gouraud robe, as requested; it is a clearly labelled visual option.
- A two-phase checker left visible broad bands. Replaced it with a short-block analytic fractional-carry pattern. It blends the bands more effectively at HD and native 4K, but does not exactly reproduce the original rotating low-byte scanline routine. The user's LBA1 screenshot is the visual reference; a matched pose and pixel comparison are still needed.
- Surveyed LBA1 BODY entries 0–39: Twinsen entry 0 has only 2 dither faces, while entries 9–12 and 17–36 often contain dozens or hundreds. Entry 9 has 86; a Source faces capture shows the effect across the light coat.
- Moved `DisplayBlock` from startup code into saved `main.tscn`. `CharacterStandPoint` is an editable marker for positioning the character after the platform mesh is replaced.
- Changed the capture test to render through an offscreen `SubViewport`. An ordinary 4K window request was capped at 2560×1380 by the desktop; the offscreen test produced 3840×2160 and the revised shader compiled in the supplied Compatibility renderer.

## Source shadow, scene separation and animation playback

- Traced Grobo BODY #17's ear artifacts to coincident reverse-wound source faces plus the viewer's disabled culling. Reversed mesh triangle winding for Godot and enabled backface culling. The Grobo capture no longer shows the ear depth fight.
- Decoded LBA1 `RESS.HQR` entry 4, sprite 2 as the actor shadow: 27×17, 182 checker-pattern pixels of palette index 16. It now appears as a native textured plane on the saved display block. Its placement is a 3D approximation of the original screen-space sprite.
- Moved the camera to an editable `OrbitCamera` node with its own script; left drag orbits, middle/right drag pans, and the wheel zooms. Moved all controls to `mainui.tscn` and `scripts/ui/main_ui.gd`. `main.gd` now only connects the UI, viewer and camera. Godot requires the `.tscn` scene extension; `.trscene` is not a loadable text scene.
- Parsed FILE3D body-to-animation references and ANIM keyframes from the original formats. The animation dropdown lists source-associated clips with archive indices. Play/pause, speed and frame scrubbing work; the source group hierarchy drives polygons, normals, lines and spheres. Root movement stays on the platform. Grobo BODY #17 exposes 12 distinct source-associated resources.
- Rechecked local Ollama at `/Work/Programs/Ollama`: `llama3.1:8b` and `deepseek-r1:7b` are installed. A short `llama3.1:8b` animation-format cross-check was too vague to use. Original assembly, TwinEngine as a cross-check, fixture bytes and Godot results determined the implementation.
- The LBA1 body/shadow fixture, Grobo association/animation fixture and Compatibility captures passed. Grobo and Twinsen walk poses were visually inspected at 1280×720, and Grobo's animated source-shadow capture completed at true 3840×2160. Exact source fixed-point rounding, matched game animation reference, LBA2, browser and GLB work remain.

## GLB, Blender and browser follow-up

- Added a skinned LBA1 GLB exporter driven by the same decoded body and animation records as the viewer. It converts polygons, low-poly spheres and rectangular-prism lines to one weighted mesh, adds the source actor-shadow image, embeds the 256-colour palette, and exports all source-associated clips with separate loop segments when needed. The display block and camera stay outside the GLB.
- Verified Godot GLB reimport for Grobo BODY #17 (12 source actions, 14 GLB clips) and Twinsen BODY #0 (60 source actions, 81 GLB clips), each with one skin and both palette and shadow images. Blender 5.0.1 imported Grobo's GLB with 21 bones, 14 actions and packed images; the walk action deformed all 2709 mesh vertices between sampled frames.
- Added a desktop **Export Blender** workflow. A Blender Python converter rebuilds an Eevee palette material with packed 4×4 screen-space ordered dither, preserves the armature/actions and shadow, adds a preview camera and replaceable platform, and saves `.blend`. This is a portable approximation of the LBA1 scanline pattern; it is not an exact shader translation. The platform uses the same palette material as the character in Blender.
- The saved Godot `DisplayBlock` now has its own `lba_character.gdshader` material and editable palette index. It uses a neutral preview texture in the editor, then receives the loaded character's actual palette in the running viewer. A scene test checked this handoff and both export controls.
- Simplified the shading dropdown to **Dither off**, **Dithered model** (default) and **Modern smooth**. Source-tag-only dithering stayed as a diagnostic in the capture fixture; it looked indistinguishable from off on Twinsen's robe because only two source faces are tagged. Modern smooth calculates lighting per pixel and blends palette colours; both modern and default modes compiled and were captured on the supplied Compatibility GPU.
- Built a single-threaded Godot Web export and tested it through local HTTP in a browser. The four HQR archives loaded through an in-page picker without server upload, Twinsen animated, and a browser-generated GLB was checked on disk: 1,149,263 bytes, 81 clips, one skin and two embedded images. GitHub Pages deployment is recorded separately once verified.
- After user review, the platform gained a separate mesh-normal lighting path in the same palette shader. Its source grayscale ramp shades the top and cylinder sides, including in the Blender conversion. Lowered the saved platform 0.005 scene units, leaving the character stand marker in place. Added Blender Cycles modifiers to every imported action channel; a fresh reopen verified 14 Grobo actions and 2058 repeating channels.
- Blender exports now select the source Idle action as the opening active clip when present. A fresh `.blend` reopen confirmed this and the cyclic channels.
