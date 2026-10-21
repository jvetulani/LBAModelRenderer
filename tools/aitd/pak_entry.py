#!/usr/bin/env python3
"""Extract one AITD PAK entry for the local Godot viewer.

The bundled UnPAK source is from tigrouind/AITD-tools (MIT license). It is
compiled into the OS temporary directory on first use; game data stays local.
"""

import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zlib


HERE = Path(__file__).resolve().parent


def read_entry(path: Path, index: int) -> tuple[bytes, int]:
    blob = path.read_bytes()
    if len(blob) < 8:
        raise ValueError("PAK header is truncated")
    first_offset = struct.unpack_from("<I", blob, 4)[0]
    count = first_offset // 4 - 2
    if first_offset > len(blob) or not 0 <= index < count:
        raise ValueError(f"PAK entry {index} is out of range (0..{count - 1})")
    offset = struct.unpack_from("<I", blob, (index + 1) * 4)[0]
    if offset + 16 > len(blob):
        raise ValueError("PAK entry header is truncated")
    descriptor = struct.unpack_from("<I", blob, offset)[0]
    info = offset + max(descriptor, 4)
    packed, unpacked, mode, flags, skip = struct.unpack_from("<IIBBH", blob, info)
    start = info + 12 + skip
    if start + packed > len(blob) or unpacked > 64_000_000:
        raise ValueError("PAK entry payload is invalid")
    data = blob[start:start + packed]
    if mode == 0:
        return data, count
    if mode == 4:
        result = zlib.decompress(data, -15)
    elif mode == 1:
        source = HERE / "unpak.c"
        digest = hashlib.sha256(source.read_bytes()).hexdigest()[:16]
        library = Path(tempfile.gettempdir()) / f"lba_aitd_unpak_{digest}.so"
        if not library.exists():
            subprocess.run(["cc", "-O2", "-fPIC", "-shared", str(source), "-o", str(library)], check=True, capture_output=True)
        unpacker = ctypes.CDLL(str(library)).PAK_explode
        unpacker.argtypes = [ctypes.POINTER(ctypes.c_ubyte), ctypes.POINTER(ctypes.c_ubyte), ctypes.c_uint, ctypes.c_uint, ctypes.c_ushort]
        packed_buffer = (ctypes.c_ubyte * len(data)).from_buffer_copy(data)
        output_buffer = (ctypes.c_ubyte * unpacked)()
        unpacker(packed_buffer, output_buffer, len(data), unpacked, flags)
        result = bytes(output_buffer)
    else:
        raise ValueError(f"Unsupported PAK compression mode {mode}")
    if len(result) != unpacked:
        raise ValueError("PAK decompression produced the wrong size")
    return result, count


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("entry", type=int, nargs="?")
    parser.add_argument("output", type=Path, nargs="?")
    parser.add_argument("--animation-catalog", action="store_true")
    parser.add_argument("--life-animation-map", action="store_true")
    args = parser.parse_args()
    try:
        if args.life_animation_map:
            from life_links import build_links
            links, failures, total = build_links(args.archive)
            print(json.dumps({"links": links, "parsed_scripts": total - failures, "total_scripts": total}))
            return 0
        if args.animation_catalog:
            _, count = read_entry(args.archive, 0)
            catalog = []
            for index in range(count):
                data, _ = read_entry(args.archive, index)
                if len(data) >= 4:
                    frames, groups = struct.unpack_from("<HH", data)
                    if frames and groups and len(data) in (4 + frames * (8 + groups * 8), 4 + frames * (8 + groups * 16)):
                        catalog.append([index, frames, groups])
            print(json.dumps(catalog))
            return 0
        if args.entry is None or args.output is None:
            parser.error("entry and output are required unless --animation-catalog is used")
        data, count = read_entry(args.archive, args.entry)
        args.output.write_bytes(data)
        print(count)
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
