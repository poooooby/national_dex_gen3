"""Builds a test copy of the mod into dist/: the same .zip the release workflow publishes
(modkit pack), named national_dex_gen3-<version>.zip.

dist/ is never part of the mod. .gitignore ignores the folder. modkit's .modkitignore only
matches exact relative paths (tools/modkit.py mod_files), so a folder entry would not keep a
file in dist/ out of a package; this script therefore keeps a managed block in .modkitignore
that lists every file in dist/, rewritten on each run.

Usage (from this repo, with the gen1recomp checkout next to it):
    python tools/build_dist.py [--gen1recomp ../gen1recomp]
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
IGNORE = ROOT / ".modkitignore"
BEGIN = "# dist/ (managed by tools/build_dist.py; do not edit)"
END = "# end dist/"


def sync_modkitignore() -> None:
    """Lists every file under dist/ in a managed block of .modkitignore."""
    text = IGNORE.read_text(encoding="utf-8") if IGNORE.exists() else ""
    lines = text.splitlines()
    if BEGIN in lines:
        start = lines.index(BEGIN)
        stop = lines.index(END, start) if END in lines[start:] else len(lines) - 1
        lines = lines[:start] + lines[stop + 1:]
    while lines and lines[-1] == "":
        lines.pop()
    files = sorted(p.relative_to(ROOT).as_posix() for p in DIST.rglob("*") if p.is_file()) \
        if DIST.is_dir() else []
    lines += ["", BEGIN, *files, END, ""]
    IGNORE.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--gen1recomp", type=Path, default=ROOT.parent / "gen1recomp")
    args = ap.parse_args()
    modkit = args.gen1recomp / "tools" / "modkit.py"
    if not modkit.exists():
        print(f"modkit not found at {modkit}", file=sys.stderr)
        return 1
    version = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))["version"]
    DIST.mkdir(exist_ok=True)
    out = DIST / f"national_dex_gen3-{version}.zip"
    # dist/ itself must already be excluded when modkit lists the files to pack
    sync_modkitignore()
    result = subprocess.run([sys.executable, str(modkit), "pack", str(ROOT), "-o", str(out)],
                            cwd=args.gen1recomp)
    sync_modkitignore()
    if result.returncode != 0:
        return result.returncode
    print(f"built {out.relative_to(ROOT).as_posix()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
