#!/usr/bin/env python3
"""
Background.qml Patcher for Qt Quick Image Quality
Patches sourceSize to preserve full wallpaper resolution.
"""

import re
import sys
from pathlib import Path


def patch_background_qml(content: str) -> str:
    """
    Patch sourceSize in Background.qml.

    Changes:
        sourceSize {
            width: bgRoot.screen.width * bgRoot.effectiveWallpaperScale * bgRoot.monitor.scale
            height: bgRoot.screen.height * bgRoot.effectiveWallpaperScale * bgRoot.monitor.scale
        }

    To:
        sourceSize { width: -1, height: -1 } /* PATCHED: Full resolution for quality */
    """

    original_pattern = r"""sourceSize\s*\{
\s*width:\s*bgRoot\.screen\.width\s*\*\s*bgRoot\.effectiveWallpaperScale\s*\*\s*bgRoot\.monitor\.scale
\s*height:\s*bgRoot\.screen\.height\s*\*\s*bgRoot\.effectiveWallpaperScale\s*\*\s*bgRoot\.monitor\.scale
\s*\}"""

    replacement = "sourceSize { width: -1, height: -1 } /* PATCHED: Full resolution for quality */"

    patched = re.sub(original_pattern, replacement, content, flags=re.MULTILINE)

    if patched == content:
        lines = content.split("\n")
        new_lines = []
        skip_until_close = False

        for line in lines:
            if "sourceSize {" in line and "width:" not in line:
                indent_match = re.match(r"^(\s*)", line)
                indent = indent_match.group(1) if indent_match else ""
                new_lines.append(
                    f"{indent}sourceSize {{ width: -1, height: -1 }} /* PATCHED: Full resolution for quality */"
                )
                skip_until_close = True
                continue

            if skip_until_close:
                if "}" in line and not line.strip().startswith(("*", "//")):
                    skip_until_close = False
                continue

            new_lines.append(line)

        patched = "\n".join(new_lines)

    return patched


def main():
    if len(sys.argv) < 3:
        print("Usage: patch_background_qml.py <input> <output>")
        sys.exit(1)

    input_file = Path(sys.argv[1])
    output_file = Path(sys.argv[2])

    if not input_file.exists():
        print(f"Error: Input file not found: {input_file}")
        sys.exit(1)

    content = input_file.read_text()
    patched_content = patch_background_qml(content)

    if patched_content == content:
        print("Warning: No changes made")
    else:
        print("Patch applied successfully!")

    output_file.write_text(patched_content)


if __name__ == "__main__":
    main()
