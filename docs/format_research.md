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

The decoder now retains raw points and group records and also constructs a world-space static pose from each group's parent point. `P_OB_ISO.ASM` `RotateGroupe` and TwinEngine `processRotatedElement` show that group points are local to a pivot; rendering the raw points directly was a concrete error in the first capture. Entry 0 has zero stored group rotations and translations, so pivot addition is sufficient for its rest pose. Other nonzero rest transforms are rejected until their matrix handling is implemented. Normal divisors remain available, but animation and group-specific normal rotation are not implemented. The decoder accepts animated LBA1 bodies only; it does not decode LBA2 bodies, animation records, or body-animation associations.

## Next source questions

1. Establish LBA1/LBA2 group hierarchy, pivots, point ranges and transform order from original animation code before implementing motion.
2. Trace how `SOURCES/OBJECT.CPP` and the LBA1 object/animation logic associate body and animation entries. Matching archive indices is not an established association rule.
3. Decode LBA2 body records from `LIB386/H/OBJECT/AFF_OBJ.H`, `LIB386/OBJECT/AFF_OBJ.ASM` and sample bodies independently; do not reuse the LBA1 decoder by assumption.
4. Confirm lighting scale, palette overflow behavior and original primitive rendering from both engines before labeling a shader profile authentic.
