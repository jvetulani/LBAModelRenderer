# Validation

Run the fixture with the supplied Godot 4.8 beta1 binary:

```bash
GODOT=/Work/Programs/Godot/4.8-beta1/Godot_v4.8-beta1_linux.x86_64
PROJECT=/Work/Projekty/Godot/LBAModelRenderer
"$GODOT" --headless --path "$PROJECT" --script res://tests/validate_lba1.gd -- \
  --lba1=/home/asia/Games/LBAgog --lba2=/home/asia/Games/LBA2gog
```

The 2026-10-18 fixture passed. LBA1 BODY entry 0 is mode 1 and 6660 bytes unpacked: 161 points, 224 polygons, 19 lines, and 5 spheres. It checks group-pivot placement, the first source normal and divisor, two type-10 dither polygons, the 768-byte palette, LBA2 BODY entry 0's mode-2 archive and offset-based header, and rejection of malformed inputs.

The Compatibility scene loaded with 732 triangle vertices and 25 character children. The saved `main.tscn` now contains `DisplayBlock` and `CharacterStandPoint`; replace the platform mesh and move the marker to set the model's foot height. The capture script uses `SubViewport` to avoid desktop-window size caps. A true 3840×2160 Full model capture was generated and visually inspected at `/tmp/lba-carry-true4k.png`. A source-face capture of dither-heavy BODY entry 9 was inspected at `/tmp/lba-body9-source-dither.png`.

To reproduce a clean native-resolution capture:

```bash
"$GODOT" --path "$PROJECT" --rendering-method gl_compatibility \
  --script res://tests/capture_viewer.gd -- \
  --lba1=/home/asia/Games/LBAgog --body-index=0 \
  --output=/tmp/lba-4k.png --yaw=20 --size=3840x2160 --hide-ui
```

Add `--dither=off` or `--dither=source` to compare modes. In the interactive viewer, choose a local LBA1 folder, select a `BODY.HQR` entry, press **Load**, and choose a dither mode. Drag to orbit and use the wheel to zoom. Only static LBA1 animated-format bodies are supported.

These checks establish desktop compilation, source-fixture parsing, and native 4K shader operation. They do not establish byte-exact original dithering, matched-game colour fidelity, other characters' correct animation poses, LBA2 body support, GLB output, or browser operation.
