#!/usr/bin/env python3
"""Create and smoke-test one deterministic Caudex CLI release archive."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import zipfile
import gzip
import io


VERSION = "0.1.0"
FIXED_MTIME = 1_767_225_600  # 2026-01-01T00:00:00Z


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(command, cwd: Path, env=None) -> str:
    result = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True)
    if result.returncode:
        raise SystemExit(
            f"command failed ({result.returncode}): {' '.join(map(str, command))}\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
    return result.stdout


def add_tar_entry(archive: tarfile.TarFile, path: Path, relative: str) -> None:
    data = path.read_bytes()
    info = tarfile.TarInfo(relative)
    info.size = len(data)
    info.mtime = FIXED_MTIME
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    info.mode = 0o755 if relative.endswith("/caudex") else 0o644
    archive.addfile(info, io.BytesIO(data))


def write_tar_gz(stage: Path, output: Path, stem: str) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", mtime=0, filename="") as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for path in sorted(stage.rglob("*")):
                    if path.is_file():
                        relative = f"{stem}/{str(path.relative_to(stage)).replace(os.sep, '/')}"
                        add_tar_entry(archive, path, relative)


def write_zip(stage: Path, output: Path, stem: str) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(stage.rglob("*")):
            if path.is_file():
                relative = str(path.relative_to(stage)).replace(os.sep, "/")
                info = zipfile.ZipInfo(relative, date_time=(2026, 1, 1, 0, 0, 0))
                info.filename = f"{stem}/{relative}"
                info.create_system = 3
                info.external_attr = (0o755 if relative.endswith("/caudex.exe") else 0o644) << 16
                archive.writestr(info, path.read_bytes())


def extract(archive: Path, destination: Path, is_windows: bool) -> Path:
    destination.mkdir(parents=True, exist_ok=True)
    if is_windows:
        with zipfile.ZipFile(archive) as source:
            source.extractall(destination)
    else:
        with tarfile.open(archive, "r:gz") as source:
            source.extractall(destination)
    roots = [path for path in destination.iterdir() if path.is_dir()]
    if len(roots) != 1:
        raise SystemExit(f"archive must contain one top-level directory: {roots}")
    return roots[0]


def smoke(root: Path, target: str) -> None:
    executable = root / ("caudex.exe" if target == "x86_64-windows-gnu" else "caudex")
    if not executable.is_file():
        raise SystemExit(f"missing executable: {executable}")
    if target == "x86_64-windows-gnu" and os.name != "nt":
        # Makes fixture tests on Unix hosts exercise archive contents too.
        executable.chmod(0o755)
    if target == "x86_64-windows-gnu" and not (root / "sqlite3.dll").is_file():
        raise SystemExit("Windows archive is missing sqlite3.dll")

    environment = os.environ.copy()
    if target == "x86_64-windows-gnu":
        # The executable directory is the only user-controlled DLL search path.
        environment["PATH"] = str(root)
    version_output = run([str(executable), "version"], root, environment)
    if not version_output.startswith("caudex 0.1.0\n"):
        raise SystemExit(f"unexpected CLI version output: {version_output}")
    help_text = run([str(executable), "--help"], root, environment)
    if "database backup" not in help_text or "history last" not in help_text:
        raise SystemExit("extracted executable returned incomplete help")

    database = root / "smoke.sqlite"
    check = run([str(executable), "--database", str(database), "--format", "json", "database", "check"], root, environment)
    if '"integrity":"ok"' not in check:
        raise SystemExit(f"SQLite smoke check failed: {check}")
    started = run(
        [
            str(executable), "--database", str(database), "--format", "json",
            "workout", "start", "--command-id", "release-smoke-start",
            "--workout", "release-smoke-workout", "--started-at", "2026-01-01T00:00:00Z",
            "--occurred-at", "2026-01-01T00:00:00Z",
        ],
        root,
        environment,
    )
    if '"workoutId":"release-smoke-workout"' not in started:
        raise SystemExit(f"workout smoke start failed: {started}")
    shown = run(
        [str(executable), "--database", str(database), "--format", "json", "workout", "show", "--workout", "release-smoke-workout"],
        root,
        environment,
    )
    if '"workoutId":"release-smoke-workout"' not in shown:
        raise SystemExit(f"workout smoke read failed: {shown}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True)
    parser.add_argument("--archive", choices=("tar.gz", "zip"), required=True)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sqlite-version", required=True)
    parser.add_argument("--sqlite-linkage", required=True)
    parser.add_argument("--sqlite-source", required=True)
    parser.add_argument("--sqlite-library", type=Path)
    parser.add_argument("--sqlite-dll", type=Path)
    parser.add_argument("--sqlite-checksum")
    args = parser.parse_args()

    stem = args.output.name.removesuffix(".tar.gz").removesuffix(".zip")
    with tempfile.TemporaryDirectory(prefix="caudex-cli-package-") as temporary:
        stage_root = Path(temporary) / stem
        stage_root.mkdir()
        executable_name = "caudex.exe" if args.target == "x86_64-windows-gnu" else "caudex"
        shutil.copyfile(args.binary, stage_root / executable_name)
        shutil.copyfile("LICENSE", stage_root / "LICENSE")
        shutil.copyfile("NOTICE", stage_root / "NOTICE")
        shutil.copyfile("apps/caudex-cli/README.md", stage_root / "README.md")
        if args.sqlite_dll:
            shutil.copyfile(args.sqlite_dll, stage_root / "sqlite3.dll")

        sqlite_file = args.sqlite_library or args.sqlite_dll
        if sqlite_file is None or not sqlite_file.is_file():
            raise SystemExit("a SQLite library or DLL is required to record a checksum")
        metadata = {
            "schemaVersion": 1,
            "version": VERSION,
            "target": args.target,
            "optimize": "ReleaseSafe",
            "archiveStem": stem,
            "platformCodeSigned": False,
            "sqlite": {
                "version": args.sqlite_version,
                "linkage": args.sqlite_linkage,
                "source": args.sqlite_source,
                "checksum": {"algorithm": "sha256", "value": args.sqlite_checksum or sha256(sqlite_file)},
            },
        }
        (stage_root / "build-metadata.json").write_text(json.dumps(metadata, sort_keys=True, indent=2) + "\n")

        if args.archive == "zip":
            write_zip(stage_root, args.output, stem)
        else:
            write_tar_gz(stage_root, args.output, stem)

        with tempfile.TemporaryDirectory(prefix="caudex-cli-extract-") as extracted:
            extracted_root = extract(args.output, Path(extracted), args.archive == "zip")
            if extracted_root.name != stem:
                raise SystemExit(f"unexpected archive root: {extracted_root.name}")
            smoke(extracted_root, args.target)

    print(f"packaged and smoke-tested {args.output}")


if __name__ == "__main__":
    main()
