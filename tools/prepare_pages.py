"""Prepare a Godot web export for GitHub Pages with a versioned game pack."""

import hashlib
import json
from pathlib import Path
import re
import shutil
import sys


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: prepare_pages.py WEB_EXPORT_DIR EMPTY_OUTPUT_DIR")
    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    if not source.is_dir() or not (source / "index.html").is_file() or not (source / "index.pck").is_file():
        raise SystemExit("Expected a Godot web export with index.html and index.pck")
    if destination.exists() and any(destination.iterdir()):
        raise SystemExit("Output directory must be empty")
    destination.mkdir(parents=True, exist_ok=True)

    pack = source / "index.pck"
    pack_name = f"index-{hashlib.sha256(pack.read_bytes()).hexdigest()[:12]}.pck"
    for file in source.iterdir():
        if file.is_file() and file.name != "index.pck" and file.name != "index.html" and file.suffix != ".import":
            shutil.copy2(file, destination / file.name)
    shutil.copy2(pack, destination / pack_name)

    html = (source / "index.html").read_text(encoding="utf-8")
    match = re.search(r"const GODOT_CONFIG = (\{[^\n]+\});", html)
    if match is None:
        raise SystemExit("Could not find Godot's web configuration in index.html")
    config = json.loads(match.group(1))
    pack_size = config["fileSizes"].pop("index.pck")
    config["fileSizes"][pack_name] = pack_size
    config["mainPack"] = pack_name
    html = html[: match.start(1)] + json.dumps(config, separators=(",", ":")) + html[match.end(1) :]
    (destination / "index.html").write_text(html, encoding="utf-8")
    (destination / ".nojekyll").touch()
    print(f"Prepared {destination} with {pack_name}")


if __name__ == "__main__":
    main()
