#!/usr/bin/env python3
"""Read-only Caudex development environment diagnostic."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
VERSIONS = json.loads((ROOT / "tools/support/versions.json").read_text())


def run(tool: str, *args: str) -> str | None:
    executable = shutil.which(tool)
    if executable is None:
        return None
    try:
        return subprocess.run(
            [executable, *args], capture_output=True, text=True, check=False
        ).stdout.strip()
    except OSError:
        return None


def major(value: str | None) -> int | None:
    if value is None:
        return None
    match = re.search(r"(\d+)", value)
    return int(match.group(1)) if match else None


def main() -> int:
    strict = "--strict" in sys.argv[1:]
    checks: list[tuple[str, bool, str]] = []

    zig = run("zig", "version")
    checks.append(("Zig", zig == VERSIONS["zig"], f"found {zig or 'missing'}; install Zig {VERSIONS['zig']}"))

    node = run("node", "--version")
    node_ok = major(node) == int(VERSIONS["node_ci"]) if strict else major(node) is not None and major(node) >= int(VERSIONS["node_min"])
    checks.append(("Node.js", node_ok, f"found {node or 'missing'}; use Node {VERSIONS['node_min']}+ (CI: {VERSIONS['node_ci']})"))

    python = run("python3", "--version") or run("python", "--version")
    python_ok = major(python) is not None and major(python) >= 3
    checks.append(("Python", python_ok, f"found {python or 'missing'}; install Python {VERSIONS['python']}"))

    sqlite = run("sqlite3", "--version")
    sqlite_ok = sqlite is not None
    checks.append(("SQLite", sqlite_ok, f"found {sqlite.split()[0] if sqlite else 'missing'}; install SQLite {VERSIONS['sqlite']}"))

    cc = shutil.which("cc") or shutil.which("clang") or shutil.which("gcc")
    checks.append(("C compiler", cc is not None, "install a C11 compiler and linker"))

    print("Caudex development environment")
    failed = False
    for name, ok, guidance in checks:
        status = "ok" if ok else ("warning" if name == "Node.js" and not strict else "missing/incompatible")
        print(f"- {name}: {status} ({guidance if not ok else 'ready'})")
        if not ok and (strict or name != "Node.js"):
            failed = True
    if failed:
        print("\nAction: install or select the versions above, then rerun ./tools/dev/doctor.")
        return 1
    print("\nEnvironment is suitable for the available local checks.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
