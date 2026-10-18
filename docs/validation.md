# Validation

Run the fixture with the supplied Godot 4.8 beta1 binary:

```bash
GODOT=/Work/Programs/Godot/4.8-beta1/Godot_v4.8-beta1_linux.x86_64
PROJECT=/Work/Projekty/Godot/LBAModelRenderer
"$GODOT" --headless --path "$PROJECT" --script res://tests/validate_lba1.gd -- \
  --lba1=/home/asia/Games/LBAgog --lba2=/home/asia/Games/LBA2gog
```

The 2026-10-18 fixture passed. LBA1 BODY entry 0 is mode 1 and 6660 bytes unpacked: 161 points, 224 polygons, 19 lines, and 5 spheres. It checks group-pivot placement, the first source normal and divisor, two type-10 dither polygons, the 768-byte palette, LBA2 BODY entry 0's mode-2 archive and offset-based header, and rejection of malformed inputs.

The fixture also checks LBA1's actor shadow from `RESS.HQR` entry 4: sprite 2 is 27×17 with 182 checker-pattern pixels, all palette index 16. Run the animation fixture with `--script res://tests/validate_animation.gd -- --lba1=/home/asia/Games/LBAgog`. It checks Grobo BODY #17's FILE3D #11 associations, ANIM #109's five frames and loop/timing fields, group movement, intermediate poses, timed viewer playback, scrubbing, source-shadow loading and truncated-input rejection.

The Compatibility scene loaded with 732 triangle vertices and 25 character children. The saved `main.tscn` now contains `DisplayBlock` and `CharacterStandPoint`; replace the platform mesh and move the marker to set the model's foot height. The capture script uses `SubViewport` to avoid desktop-window size caps. A true 3840×2160 Full model capture was generated and visually inspected at `/tmp/lba-carry-true4k.png`. A source-face capture of dither-heavy BODY entry 9 was inspected at `/tmp/lba-body9-source-dither.png`.

To reproduce a clean native-resolution capture:

```bash
"$GODOT" --path "$PROJECT" --rendering-method gl_compatibility \
  --script res://tests/capture_viewer.gd -- \
  --lba1=/home/asia/Games/LBAgog --body-index=0 \
  --output=/tmp/lba-4k.png --yaw=20 --size=3840x2160 --hide-ui
```

Add `--dither=off` or `--dither=source` to compare modes, plus `--anim-index=109 --anim-frame=2` to capture a particular Grobo walk keyframe. In the interactive viewer, choose a local LBA1 folder, select a `BODY.HQR` entry and press **Load**. The animation dropdown then shows the associated ANIM.HQR resources. Left drag orbits, middle/right drag pans, and the wheel zooms. The saved scene contains an editable `OrbitCamera`, `DisplayBlock`, `CharacterStandPoint`, `CharacterViewer` and instanced `mainui.tscn`.

The Grobo frame-2 source-shadow capture at `/tmp/lba-grobo-walk-4k.png` is a verified 3840×2160 PNG. These checks establish desktop compilation, source-fixture parsing and native 4K rendering of an animated pose. They do not establish byte-exact original dithering, matched-game colour or animation fidelity, all other characters' correct poses, or LBA2 body support. The original screen-space shadow placement and truck transparency modes remain incomplete.

Run `tests/validate_export.gd` with `--lba1=/home/asia/Games/LBAgog` to export and reimport Grobo and Twinsen GLBs. It checks every generated clip count, a glTF skin and successful Godot reimport. `tests/validate_ui_export.gd` loads the saved scene and checks the platform's runtime palette handoff plus desktop GLB and Blender file exports. Blender 5.0.1 reopened `/tmp/lba1-grobo.blend`: it contains 14 clips, 21 bones, packed palette and dither images, the shadow and the shared-shader platform. Applying `Walk_ANIM_109` moved 2709/2709 evaluated character mesh vertices between frames. An Eevee preview was rendered at `/tmp/lba1-grobo-blender.png`.

The **Dithered model** default and **Modern smooth** mode were GPU captured at 1280×720 in `/tmp/lba-dithered-default.png` and `/tmp/lba-modern-smooth.png`. Modern smooth showed a continuous gradient without the default pixel pattern. The Godot Web preset exported successfully using the supplied 4.8 beta1 single-threaded template. A local browser loaded BODY/ANIM/FILE3D/RESS, played Twinsen, and saved `/home/asia/Downloads/lba1-body-000.glb`; its GLB JSON has 81 animations, one skin and two embedded images. GitHub Pages published the viewer from the `gh-pages` branch at https://jvetulani.github.io/LBAModelViewer/; the hosted page loaded all four local archives and animated Twinsen in the browser.

After the platform lighting and cyclic-action changes, the scene integration fixture passed again. A Compatibility GPU capture at `/tmp/lba-lit-platform.png` visibly separates the platform's lighter top from its darker sides. The saved platform centre is 0.005 scene units lower than before. Blender reopened the desktop-exported `/tmp/lba1-ui-grobo.blend`; `tests/validate_blender_export.py` checked Idle as the selected action, its shared palette material, varied platform shade UVs, packed images, and exactly one repeating Cycles modifier before and after every action channel. Grobo has 14 cyclic actions and 2058 repeating channels.

The web picker was changed to select the LBA1 folder once. A browser selected `/home/asia/Games/LBAgog`, loaded Twinsen with no console errors, and displayed the selected folder name. The same **Modern smooth** choice now reaches both character and display-platform materials. The integration fixture checked both shader parameters, and browser captures at `/tmp/lba-platform-dithered-web.png` and `/tmp/lba-platform-smooth-web.png` show the platform's dithered side changing to a smooth palette gradient.
