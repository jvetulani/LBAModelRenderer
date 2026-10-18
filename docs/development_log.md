# Development log

## 2026-10-18 — first character path

- Inspected the supplied Godot project. It contained a `main.tscn`, not `main.trscene`; the existing scene was kept and given a script. The pre-existing Compatibility renderer setting was retained.
- Downloaded the original LBA1 and LBA2 source releases and TwinEngine into `/home/asia/Projekty/LBA/LBAModelVIewer/`, as requested. No source checkout or game archive was added to the Godot project.
- Confirmed Godot `4.8.beta1.official.4d10419ca`, local Ollama, and installed `llama3.1:8b` and `deepseek-r1:7b`. A narrow `llama3.1:8b` parser-review prompt suggested bounds checks; no unverified model output was incorporated. Source code, fixture decoding and Godot runtime results determined the implementation.
- Implemented bounded HQR extraction, static LBA1 animated-body parsing, an original-palette texture, native geometry and a spatial shader. Added a local-directory picker, archive entry control, orbit and zoom, and a display block.
- Ran the headless archive/body fixture and a GPU Compatibility scene capture with the user's local game archives. The capture is held in `/tmp/lba-body0-front-lit.png` for inspection and is not bundled in the project.

The first-action proof of concept from the brief is working. Phase 1 is partial: there is no source-library browser or version detection. Phase 2 is partial: one LBA1 body is rendered; LBA2 bodies and fidelity comparison remain. Phases 3–7 (animation, historical shading, editor, GLB export and web release) are not implemented.

## Correction after visual review

The initial screenshot was not a valid static pose. It rendered group-local point coordinates directly, which collapsed body parts around the origin. Tracing `P_OB_ISO.ASM` `RotateGroupe` and TwinEngine `processRotatedElement` showed that each group's points must be placed relative to a previously transformed pivot. The decoder now constructs that pose and checks group ranges and parents; the fixture verifies raw versus posed coordinates. The preview camera now frames the transformed height. Arbitrary Godot ambient light was removed and the UI labels the shader as preview lighting with no authentic dithering. The front-angle Compatibility capture is `/tmp/lba-body0-pose-corrected.png`. Historical shading, dither and matched-game comparison are still pending.

## Source-index shading and dither follow-up

- Replaced the arbitrary 0–11 lighting ramp with source-normal/divisor shading in palette-index space. Converted the palette to six-bit VGA DAC values and corrected the Godot light pass. The default source light vector is still approximate.
- Added Off, Source faces, and Full model dither modes. Source faces follows type-10 material tags. Full model also covers Twinsen's Gouraud robe, as requested; it is a clearly labelled visual option.
- A two-phase checker left visible broad bands. Replaced it with a short-block analytic fractional-carry pattern. It blends the bands more effectively at HD and native 4K, but does not exactly reproduce the original rotating low-byte scanline routine. The user's LBA1 screenshot is the visual reference; a matched pose and pixel comparison are still needed.
- Surveyed LBA1 BODY entries 0–39: Twinsen entry 0 has only 2 dither faces, while entries 9–12 and 17–36 often contain dozens or hundreds. Entry 9 has 86; a Source faces capture shows the effect across the light coat.
- Moved `DisplayBlock` from startup code into saved `main.tscn`. `CharacterStandPoint` is an editable marker for positioning the character after the platform mesh is replaced.
- Changed the capture test to render through an offscreen `SubViewport`. An ordinary 4K window request was capped at 2560×1380 by the desktop; the offscreen test produced 3840×2160 and the revised shader compiled in the supplied Compatibility renderer.
