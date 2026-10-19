# Skeleton and texture UV audit

Run the full association and UV scans with the supplied game archives:

```bash
GODOT=/Work/Programs/Godot/4.8-beta1/Godot_v4.8-beta1_linux.x86_64
PROJECT=/Work/Projekty/Godot/LBAModelRenderer
"$GODOT" --headless --path "$PROJECT" --script res://tests/audit_skeleton_associations.gd -- \
  --lba1=/home/asia/Games/LBAgog --lba2=/home/asia/Games/LBA2gog \
  --demo=/home/asia/Projekty/LBA/LBAModelVIewer/LBA2-96 \
  --report=/tmp/lba-skeleton-audit.tsv
"$GODOT" --headless --path "$PROJECT" --script res://tests/audit_texture_uvs.gd -- \
  --report=/tmp/lba-uv-audit.tsv
"$GODOT" --headless --path "$PROJECT" --script res://tests/audit_texture_uvs.gd -- \
  --effective --report=/tmp/lba-uv-effective-audit.tsv
```

The 2026-10-19 skeleton scan counted each unique FILE3D BODY/ANIM pairing once:

| Game | Pairings | Exact groups | Action shorter | Action longer | Shared ANIM resources |
| --- | ---: | ---: | ---: | ---: | ---: |
| LBA1 | 1,335 | 1,009 | 13 | 313 | 278 |
| LBA2 retail | 5,243 | 3,071 | 1,085 | 1,087 | 874 |
| LBA2 1996 demo | 1,048 | 734 | 96 | 218 | 174 |

The viewer allows shorter shared actions; bones without keys stay at rest. Differences greater than four groups **and** 25% of the body's group count receive a review warning. This is a diagnostic threshold, not a game-format rule: it flags 0 LBA1, 283 LBA2 retail, and 5 demo pairings. In the retail flags, 184 have a same-count alternate BODY in their FILE3D stream and 99 do not; 94 of the latter involve BODY #14/#15, which share a large action list despite having fewer groups. Three demo flags have an alternate and two do not. The TSV lists the compatible alternate BODY indices for each flagged pair. A group count alone cannot prove that two skeletons have the same hierarchy or proportions, so these are review leads rather than automatic switches. FILE3D's undergass family is handled explicitly: #321/#426 use 26 groups, #320/#427 use 29, and #322/#376 use 30. Selecting an action swaps to the matching BODY. The GLB exports all three required skins and their actions; the Blender conversion retains three meshes and the action-driven form changes.

The UV scan decoded every BODY and visited every textured triangle, skipping zero-area geometry when measuring distortion: 132/132 LBA1 bodies with no textured triangles; 469/469 LBA2 bodies with 15,560 triangles; and 116/116 demo bodies with 820 triangles. The broad anisotropy/density heuristic flagged 2,983 retail and 159 demo triangles. Of those, 2,274 retail and 150 demo triangles have effectively zero UV area, often an intentional single-texel fill. These counts are **review candidates**, not confirmed defects. Representative inspected outliers include the striped object #158, elongated effect #268, wavy creature #340, and dark creature #356; their shapes explain much of the metric. Do not apply a global UV remap from this score.

BODY #381 had 22 flagged source triangles, including a skirt face with a collapsed UV axis. Its per-body minimum-density repair reduces that count to zero and gives the skirt an even texture in a rendered capture. The monkey #388/#389 limb repair remains targeted to its four limb chains. Both repairs are applied before preview and export, so the GLB receives the same UVs.
