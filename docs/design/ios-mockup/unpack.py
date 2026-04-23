#!/usr/bin/env python3
"""Unpack a Claude artifact `__bundler` HTML into source files.

Reads /Users/dixoncider/slabbist/docs/design/ios-mockup/Slabbist-iOS.html
and writes the decoded assets into ./unpacked/ alongside a manifest.json.
"""

from __future__ import annotations

import base64
import gzip
import json
import mimetypes
import re
from pathlib import Path

HERE = Path(__file__).parent
SRC = HERE / "Slabbist-iOS.html"
OUT = HERE / "unpacked"

# extension hints beyond the stdlib mimetypes table
EXT_OVERRIDES = {
    "application/javascript": ".jsx",  # artifacts author JSX that babel transforms
    "text/jsx": ".jsx",
    "text/babel": ".jsx",
    "text/html": ".html",
    "text/css": ".css",
    "image/svg+xml": ".svg",
}


def extension_for(mime: str) -> str:
    if mime in EXT_OVERRIDES:
        return EXT_OVERRIDES[mime]
    return mimetypes.guess_extension(mime) or ".bin"


def main() -> None:
    html = SRC.read_text()
    OUT.mkdir(exist_ok=True)

    def extract(tag: str) -> str | None:
        pattern = re.compile(
            rf'<script type="__bundler/{tag}">(.*?)</script>',
            re.DOTALL,
        )
        m = pattern.search(html)
        return m.group(1) if m else None

    manifest_raw = extract("manifest")
    template_raw = extract("template")
    ext_raw = extract("ext_resources")

    if manifest_raw is None or template_raw is None:
        raise SystemExit("missing manifest/template scripts")

    manifest = json.loads(manifest_raw)
    template = json.loads(template_raw)
    ext_resources = json.loads(ext_raw) if ext_raw else []

    index: list[dict] = []
    for uuid, entry in manifest.items():
        mime = entry["mime"]
        compressed = entry.get("compressed", False)
        payload = base64.b64decode(entry["data"])
        if compressed:
            payload = gzip.decompress(payload)
        ext = extension_for(mime)
        fname = f"{uuid}{ext}"
        (OUT / fname).write_bytes(payload)
        index.append({"uuid": uuid, "mime": mime, "file": fname, "size": len(payload)})

    (OUT / "_template.html").write_text(template)
    (OUT / "_ext_resources.json").write_text(json.dumps(ext_resources, indent=2))
    (OUT / "_index.json").write_text(json.dumps(index, indent=2))
    print(f"wrote {len(index)} assets to {OUT}")


if __name__ == "__main__":
    main()
