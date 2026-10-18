"""Prepare a Godot web export for GitHub Pages with a versioned game pack."""

import hashlib
import json
from pathlib import Path
import re
import shutil
import sys


PROJECT_ROOT = Path(__file__).resolve().parents[1]
BRANDING = PROJECT_ROOT / "assets" / "branding"
FONT = PROJECT_ROOT / "assets" / "ui" / "fonts" / "ShortStack-Regular.ttf"


def add_loading_brand(html: str) -> str:
    splash = (
        '<div id="lba-brand">'
        '<img id="status-splash" src="lba-umbrella-wireframe.png" alt="">'
        '<strong id="lba-brand-title">LBA MODEL RENDERER</strong>'
        '</div>'
    )
    html, image_count = re.subn(r'<img id="status-splash"[^>]*>', splash, html, count=1)
    if image_count != 1 or "</style>" not in html:
        raise SystemExit("Could not find Godot's loading splash in index.html")
    style = """
@font-face {
    font-family: 'Short Stack';
    src: url('lba-short-stack.ttf') format('truetype');
    font-display: swap;
}
body, #status { background-color: #1c2430; }
#lba-brand {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: clamp(8px, 2vh, 20px);
    max-width: 90vw;
}
#status-splash {
    position: static;
    width: min(62vw, 430px);
    height: auto;
    max-width: 100%;
    max-height: min(60vh, 430px);
    margin: 0;
    object-fit: contain;
}
#lba-brand-title {
    color: #faad13;
    font-family: 'Short Stack', sans-serif;
    font-size: clamp(18px, 3vw, 38px);
    font-weight: 700;
    line-height: 1.2;
    letter-spacing: 0.03em;
    text-align: center;
    -webkit-text-stroke: 0.4px currentColor;
}
#status-progress {
    bottom: 7%;
    width: min(420px, 70vw);
    accent-color: #faad13;
}
"""
    return html.replace("</style>", style + "\n</style>", 1)


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
    shutil.copy2(BRANDING / "umbrella-wireframe.png", destination / "lba-umbrella-wireframe.png")
    shutil.copy2(BRANDING / "umbrella.png", destination / "index.icon.png")
    shutil.copy2(BRANDING / "umbrella.png", destination / "index.apple-touch-icon.png")
    shutil.copy2(FONT, destination / "lba-short-stack.ttf")

    html = (source / "index.html").read_text(encoding="utf-8")
    match = re.search(r"const GODOT_CONFIG = (\{[^\n]+\});", html)
    if match is None:
        raise SystemExit("Could not find Godot's web configuration in index.html")
    config = json.loads(match.group(1))
    pack_size = config["fileSizes"].pop("index.pck")
    config["fileSizes"][pack_name] = pack_size
    config["mainPack"] = pack_name
    html = html[: match.start(1)] + json.dumps(config, separators=(",", ":")) + html[match.end(1) :]
    html = add_loading_brand(html)
    # Godot creates the WebGL context after loading index.js. Keep the canvas
    # alpha channel when a host page requests a transparent model embed.
    transparent_embed = """<script>
if (new URL(location.href).searchParams.get('transparent') === '1') {
    document.documentElement.style.background = 'transparent';
    document.body.style.background = 'transparent';
    const canvas = document.getElementById('canvas');
    if (canvas) canvas.style.background = 'transparent';
    const originalGetContext = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function (type, attributes) {
        if (this.id === 'canvas' && (type === 'webgl' || type === 'webgl2')) {
            attributes = {...attributes, alpha: true};
        }
        return originalGetContext.call(this, type, attributes);
    };
}
</script>
"""
    if '<script src="index.js"></script>' not in html:
        raise SystemExit("Could not find Godot's script in index.html")
    html = html.replace('<script src="index.js"></script>', transparent_embed + '<script src="index.js"></script>', 1)
    (destination / "index.html").write_text(html, encoding="utf-8")
    # GitHub Pages serves this for /link=<encoded-url>, allowing path-style links.
    (destination / "404.html").write_text(html, encoding="utf-8")
    (destination / ".nojekyll").touch()
    print(f"Prepared {destination} with {pack_name}")


if __name__ == "__main__":
    main()
