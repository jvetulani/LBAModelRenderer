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

Add `--dither=off`, `--dither=soft`, or `--shading=smooth` to compare product modes, plus `--anim-index=109 --anim-frame=2` to capture a particular Grobo walk keyframe. `--dither=source` remains a diagnostic for source-tagged dither faces. `--soft-strength=0.7` controls the anchored pattern strength in captures. The default is soft model-anchored dithering. In the interactive viewer, choose a local game folder and select a `BODY.HQR` entry; the model loads when its entry changes. The animation dropdown then shows the associated ANIM.HQR resources. Left drag orbits, middle/right drag pans, and the wheel zooms. The saved scene contains an editable `OrbitCamera`, `DisplayBlock`, `CharacterStandPoint`, `CharacterViewer` and instanced `mainui.tscn`.

Run `tests/validate_boat_sail.gd` with `--lba1=/home/asia/Games/LBAgog` to check BODY #49 and pirate-flag variant #50's sail repair, distinct left/right root movement, the motion-grid toggle, and GLB reimport. The original ANIM #232–234 joint keys are identical, but their root steps move backward, left, and right. The grid scrolls while the model stays centered and fades at its edge.

The Grobo frame-2 source-shadow capture at `/tmp/lba-grobo-walk-4k.png` is a verified 3840×2160 PNG. These checks establish desktop compilation, source-fixture parsing and native 4K rendering of an animated pose. They do not establish byte-exact original dithering, matched-game colour or animation fidelity for every character.

Run `tests/validate_export.gd` with `--lba1=/home/asia/Games/LBAgog` to export and reimport Grobo and Twinsen GLBs. It checks every generated clip count, a glTF skin and successful Godot reimport. `tests/validate_ui_export.gd` loads the saved scene and checks the platform's runtime palette handoff plus desktop GLB and Blender file exports. Blender 5.0.1 reopened `/tmp/lba1-grobo.blend`: it contains 14 clips, 21 bones, packed palette and dither images, the shadow and the shared-shader platform. Applying `Walk_ANIM_109` moved 2709/2709 evaluated character mesh vertices between frames. An Eevee preview was rendered at `/tmp/lba1-grobo-blender.png`.

The previous **Dithered model** default and **Modern smooth** mode were GPU captured at 1280×720 in `/tmp/lba-dithered-default.png` and `/tmp/lba-modern-smooth.png`. The newer soft model-anchored default and the retained strong screen-space mode were GPU captured at 2560×1440 in `/tmp/lba-soft-1440.png` and `/tmp/lba-strong-1440.png`. The soft mode showed much less visible grain; `validate_navigation.gd` also checked that the anchor data remains fixed while an LBA2 model animates. The Godot Web preset exported successfully using the supplied 4.8 beta1 single-threaded template. A local browser loaded BODY/ANIM/FILE3D/RESS, played Twinsen, and saved `/home/asia/Downloads/lba1-body-000.glb`; its GLB JSON has 81 animations, one skin and two embedded images. GitHub Pages published the viewer from the `gh-pages` branch at https://jvetulani.github.io/LBAModelRenderer/; the hosted page loaded all four local archives and animated Twinsen in the browser.

After the platform lighting and cyclic-action changes, the scene integration fixture passed again. A Compatibility GPU capture at `/tmp/lba-lit-platform.png` visibly separates the platform's lighter top from its darker sides. The saved platform centre is 0.005 scene units lower than before. Blender reopened the desktop-exported `/tmp/lba1-ui-grobo.blend`; `tests/validate_blender_export.py` checked Idle as the selected action, its shared palette material, varied platform shade UVs, packed images, and exactly one repeating Cycles modifier before and after every action channel. Grobo has 14 cyclic actions and 2058 repeating channels.

The web picker was changed to select the LBA1 folder once. A browser selected `/home/asia/Games/LBAgog`, loaded Twinsen with no console errors, and displayed the selected folder name. The same **Modern smooth** choice now reaches both character and display-platform materials. The integration fixture checked both shader parameters, and browser captures at `/tmp/lba-platform-dithered-web.png` and `/tmp/lba-platform-smooth-web.png` show the platform's dithered side changing to a smooth palette gradient.
The Pages package prepared by `tools/prepare_pages.py` started in a local browser with its content-versioned `.pck` and no console errors.

The current fixtures also include `validate_lba2.gd`, `validate_demo.gd`, `validate_turn_actions.gd`, and `validate_navigation.gd`. They cover the retail and demo bodies, the demo's 50 Hz timing and shade table, source palette selection, translucent and spectral materials, zero-duration keyframe normalization, GLB reimport, entry wrapping, and shadow/wireframe toggles. The turn fixture checks that LBA1, LBA2, and demo actor master yaw rotates the model and GLB root instead of lifting it. Source-associated animations with fewer groups than a BODY remain selectable; absent group transforms use the body rest pose. Retail shark variants BODY #320–322 share one actor action list but have distinct skeleton sizes, so their model overrides select only actions with matching group counts. The LBA2 fixture also checks the monkey BODY #388–389 arm UV correction without changing face UVs.

The 2026-10-18 web build was opened through HTTP folder links on localhost for all three games: LBA1 BODY #4 and ANIM #0, LBA2 BODY #14 and ANIM #0, and demo BODY #0 and ANIM #0. Production links require an HTTPS source. A Pages-style `404.html` fallback also opened `/link=<encoded-url>?body=16&anim=103` at LBA1 truck BODY #16. The Copy link button reported a successful clipboard write. Browser captures of the updated demo BODY #0 show white eyes with blue pupils under Soft dither; retail LBA2 BODY #0 retained its eye colours. The `validate_lba1.gd`, `validate_lba2.gd`, `validate_demo.gd`, and `validate_navigation.gd` fixtures all exited successfully after the shader change.

`audit_all_bodies.gd -- --source=GAME_FOLDER` rendered 132/132 LBA1, 469/469 LBA2, and 116/116 demo entries into visual review sheets with no load or empty-geometry failures. `audit_all_animations.gd -- --source=GAME_FOLDER` sampled the start, midpoint, and end of every associated action on every BODY: 1,335 LBA1 actions/4,005 poses, 5,243 LBA2 actions/15,729 poses, and 1,048 demo actions/3,144 poses, all without parse or non-finite-pose failures. Representative sheets and the LBA1 BODY #4 before/after captures were inspected. This is a broad import and visual sanity check, not proof that every pose or effect exactly matches gameplay.

`validate_all_exports.gd` exercises the desktop GLB and Blender export controller for one animated BODY from each version: LBA1 #17, LBA2 #0, and textured 1996 demo #1. Each GLB reimported with one skin and at least as many animations as source actions. The respective exports contained 12/14, 104/145, and 58/83 source actions/GLB clips. Blender 5.0.1 reopened every `.blend`; `validate_blender_export.py` confirmed packed palette and texture images, cyclic action channels, and an evaluated Walk pose that changes over time. Run the Blender check with `--python-exit-code 1` so script assertions fail the command.
