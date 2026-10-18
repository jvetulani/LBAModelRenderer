# LBA1 rendering research and current result

The viewer uses native Godot meshes, a spatial shader, and a custom `light()` function on Godot 4.8 beta1's Compatibility renderer. It does not upscale a low-resolution framebuffer. The capture test rendered a true 3840×2160 image through an offscreen `SubViewport`.

## Lighting and palette

`lba1-classic/LIB386/LIB_3D/P_OB_ISO.ASM`, `ComputeAnimNormal` computes a light response for each source normal using its stored divisor. `polygouraud` adds that response to the polygon's base palette index at each vertex. `lba1-classic/LIB386/LIB_SVGA/S_FILLV.ASM`, `SVGAPolyGouraud` interpolates 8.8 fixed-point indices across scanlines and emits their high byte. The viewer carries source normals and divisors in mesh custom data, computes a palette-index offset in `vertex()`, interpolates it into `fragment()`, and samples `RESS.HQR` entry 0. It does not clamp the offset to an invented 16-colour ramp.

`lba1-classic/LIB386/LIB_SVGA/S_PAL.ASM`, `Palette` shifts source RGB bytes right by two for the six-bit VGA DAC. The palette texture applies that conversion. Godot ambient energy is zero. One white light and `light()` pass the palette colour without modern specular highlights, compensating for Godot's `LIGHT_COLOR` PI factor. The fixed source-light vector approximates the game's default `SetLightVector(896, 950, 0)`; original integer trig, group rotations, and raster interpolation remain unmatched.

## Dither and the supplied LBA1 screenshot

`SVGAPolyDith` is a dedicated LBA1 scanline routine with fractional carry and low-byte rotation. Body material tags matter: Twinsen BODY entry 0 contains 204 Gouraud faces, 18 flat faces, and only 2 dither faces, neither on his robe. A survey of entries 0–39 found many other characters with 80–200 type-10 dither faces. BODY entry 9 has 86; its source-face capture shows dither across a light coat. This is consistent with the user's LBA1 screenshot showing a dithered cast, while explaining why source-face mode barely affects Twinsen's robe.

The viewer offers **Dither off**, **Source faces**, and **Full model**. Source faces follows original type-10 material tags. Full model is the default visual option and extends dither to Gouraud faces, including Twinsen's robe, as requested. It must not be mistaken for an original material assignment.

The first two-phase checker left broad palette bands. The current shader instead quantizes the interpolated palette index to 8.8, then analytically distributes fractional index carry along short output-space row blocks. It runs in constant time per fragment at HD and 4K. Source faces uses one output pixel; Full model scales the display cell with viewport height so the pattern remains legible on high-density screens. The user's LBA1 screenshot is a visual reference, not a matched-pose comparison. The current result blends bands more effectively, but its row phase, polygon-edge rounding, and carry rotation are **not byte-exact** to `SVGAPolyDith`; the model should not yet be called pixel-authentic.

The polygon builder fans source faces without changing point order. Lines are thin four-sided cylinders and spheres are low-poly Godot spheres. Original screen-space line width, sphere raster behaviour, depth ordering, animation, and LBA2 lighting remain open. WebGL2 compilation has not been tested.

Next fidelity work is a matched original-game capture, integer light-vector reconstruction, and representative palette-index comparisons along Gouraud and dither scanlines at multiple output resolutions.
