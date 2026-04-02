#!/usr/bin/env python3
"""
Reads GOOGLE_MAPS_API_KEY from repo-root .env and writes Zones/Generated/EnvSecrets.swift.
Run by Xcode before compiling (see Run Script build phase).
"""
from __future__ import annotations

import os
import re
from pathlib import Path


def main() -> None:
    srcroot = Path(os.environ.get("SRCROOT", ".")).resolve()
    env_file = srcroot / ".env"
    out = srcroot / "Zones" / "Generated" / "EnvSecrets.swift"
    key = ""

    if env_file.is_file():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            m = re.match(r"^\s*GOOGLE_MAPS_API_KEY\s*=\s*(.*)\s*$", line)
            if m and not line.lstrip().startswith("#"):
                key = m.group(1).strip().strip('"').strip("'")
                break

    out.parent.mkdir(parents=True, exist_ok=True)
    escaped = key.replace("\\", "\\\\").replace('"', '\\"')
    out.write_text(
        "// AUTO-GENERATED from .env by scripts/sync_env_to_swift.py — do not edit\n"
        "import Foundation\n"
        "enum EnvSecrets {\n"
        f'    static let googleMapsAPIKey: String = "{escaped}"\n'
        "}\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
