# Format research map

This is a map of evidence for the first, static LBA1 character prototype. The source clones are kept in `/home/asia/Projekty/LBA/LBAModelVIewer/`; game archives are read from the user's installations at runtime and are not part of this project.

| Source | Revision | Relevant code |
| --- | --- | --- |
| [Original LBA1 release](https://github.com/2point21/lba1-classic) | `f73f457317f0b75975e6009f2d0bd89c18c9e3ce` | `LIB386/LIB_SYS/HQ_RESS.C`, `LIB386/LIB_SYS/EXPAND.ASM`, `LIB386/LIB_3D/P_OB_ISO.ASM`, `SOURCES/COMMON.H`, `SOURCES/PERSO.C` |
| [Original LBA2 release](https://github.com/2point21/lba2-classic) | `a256b0c0117ec59fa6b4655d9ad6e19348573109` | `LIB386/SYSTEM/HQRRESS.CPP`, `LIB386/H/OBJECT/AFF_OBJ.H`, `LIB386/OBJECT/AFF_OBJ.ASM`, `SOURCES/OBJECT.CPP` are next research targets |
| [TwinEngine cross-check](https://github.com/LBALab/twin-e) | `2e2de9be9f2bf477e426f5e88175847da4c43e6e` | `src/hqr.c`, `src/renderer.c` |

The original engine repositories carry GPL source licenses. The GDScript in this project was written independently from the observed file layouts and behavior; no game archive or original engine source is copied into this Godot project. License review is required before reusing engine code in a future release.

## HQR archive

`HQ_RESS.C` reads a leading 32-bit byte length for the offset table. It contains 32-bit entry offsets. A nonempty entry starts with unpacked size (`u32`), packed size (`u32`), and compression mode (`u16`), then the payload. `EXPAND.ASM` supplies the LSB-first token stream: a set bit means a literal byte, and a clear bit means a 16-bit back-reference with 12-bit distance and 4-bit length. Mode 1 yields length `low_nibble + 2`; TwinEngine's `src/hqr.c` confirms mode 2 yields `low_nibble + 3`. Mode 0 is stored data.

`scripts/import/hqr_reader.gd` checks table shape, offsets, payload bounds, mode, output size and bad references. Its 32 MiB per-entry limit is a project safety cap, not an original format limit. A verified LBA1 `BODY.HQR` entry 0 decodes in mode 1; an LBA2 `BODY.HQR` entry 0 decodes in mode 2. This confirms archive handling only, not the LBA2 body format. LBA2's `T_BODY_HEADER` in `LIB386/H/OBJECT/AFF_OBJ.H` is an offset-based header distinct from the LBA1 layout.

For the user's LBA2 entry 0, the 96-byte header reports 19 groups, 193 points, 193 normals, 6 face normals, 281 polygons, 0 lines, 5 spheres and 2 textures. These are header values checked against the decompressed bytes, not yet verified decoded geometry.

## LBA1 animated body, static pose

`P_OB_ISO.ASM` and TwinEngine `src/renderer.c` establish the body record order used here: header, point table, 38-byte groups, 8-byte normals, variable-size polygons, 8-byte lines, and 8-byte spheres. Point coordinates are signed 16-bit triples. The polygon header carries render type, point count, and color; type 7–8 has one face normal reference, while type 9+ has a normal reference at each vertex. Polygon point references are byte offsets into the six-byte point table. Lines and spheres also reference points by byte offset.

For the user's LBA1 `BODY.HQR` entry 0, the independently decoded counts are 161 points, 19 groups, 144 normals, 224 polygons, 19 lines and 5 spheres. All referenced point and normal indices pass bounds checks. Two trailing bytes remain after the sphere table; their purpose has not been established. `RESS.HQR` entry 0 is the 768-byte palette (`RESS_PAL` in `SOURCES/COMMON.H`, loaded in `SOURCES/PERSO.C`).

The decoder retains raw points and group records and constructs a static pose from each group's parent point. `P_OB_ISO.ASM` `RotateGroupe` and TwinEngine `processRotatedElement` show that group points are local to a pivot. Nonzero stored rest transforms remain unsupported. The decoded group parent, point range, pivot and per-point group assignment now feed animated poses. LBA2 bodies remain unsupported.

## LBA1 animation and association

`LIB386/LIB_3D/P_ANIM.ASM` `GetNbFramesAnim`, `GetBouclageAnim`, `SetAnimObjet` and `SetInterAnimObjet` establish an eight-byte header: frame count (`u16`), group count (`u16`), loop keyframe (`u16`), then two further bytes. Each frame is eight bytes of duration in 50 Hz ticks and signed root X/Y/Z steps, followed by eight bytes per group: transform type and three signed values. `P_TRIGO.ASM` `RotMatIndex2` applies group Alpha about X, Gamma about Z, then Beta about Y to the parent matrix. `P_OB_ISO.ASM` uses each parent group's transformed pivot. Type 0 is rotation in 1024 units per turn; type 1 translates local points before the parent transform. The preview interpolates transform values toward the destination keyframe using that keyframe's duration. Root steps are decoded but deliberately not applied, keeping the model on its block.

`SOURCES/FICHE.C` `SearchBody` and `SearchAnim` look up BODY and ANIM archive indices through an actor's `FILE3D.HQR` record. Records have command byte, generic ID, then a size-prefixed payload whose size includes the size byte. Commands 1 and 3 contain BODY and ANIM references. This is why matching BODY and ANIM archive indices is wrong. Grobo BODY #17 appears in FILE3D #11, with 17 generic animation records referring to 12 distinct ANIM resources. ANIM #109 is its five-frame walk with loop frame 1. Twinsen BODY #0 is present in several behavior files, yielding 60 distinct associated ANIM resources in this installation. The UI shows generic names and archive indices, preserving that provenance.

The pose code follows the original rigid group hierarchy, updates polygon source normals with the group matrix, and moves attached lines and spheres. It accepts type 0/1 keyframes; type 2 zoom is rejected. Exact fixed-point trigonometric rounding, source animation transition edge cases, root turns, and a matched game-pose comparison remain open. The runtime currently rebuilds a small native triangle mesh while playing; no CPU rasterization is involved.

## Next source questions

1. Decode LBA2 body and animation records from the original LBA2 source and sample resources; do not reuse the LBA1 layout by assumption.
2. Compare representative LBA1 animation poses and timing against original-game captures, including rotation sign, translated groups and root motion.
3. Confirm lighting scale, palette overflow behavior and original primitive rendering from both engines before labeling a shader profile authentic.
