#!/usr/bin/env python3
"""Verify the complete set of CWE-193 CLI release assets."""

import argparse
import hashlib
import json
from pathlib import Path
import tarfile
import zipfile


ASSETS = (
    "caudex-workout-cli-0.1.0-x86_64-linux-gnu.tar.gz",
    "caudex-workout-cli-0.1.0-aarch64-linux-gnu.tar.gz",
    "caudex-workout-cli-0.1.0-x86_64-macos.tar.gz",
    "caudex-workout-cli-0.1.0-aarch64-macos.tar.gz",
    "caudex-workout-cli-0.1.0-x86_64-windows-gnu.zip",
)
REQUIRED_COMMON = {"LICENSE", "NOTICE", "README.md", "build-metadata.json"}


def checksum(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def archive_entries(path: Path):
    if path.name.endswith(".zip"):
        with zipfile.ZipFile(path) as archive:
            return archive.namelist()
    with tarfile.open(path, "r:gz") as archive:
        return archive.getnames()


def verify_archive(directory: Path, name: str) -> None:
    path = directory / name
    if not path.is_file():
        raise SystemExit(f"missing release archive: {name}")
    stem = name.removesuffix(".tar.gz").removesuffix(".zip")
    entries = archive_entries(path)
    prefix = stem + "/"
    if any(not entry.startswith(prefix) or ".." in Path(entry).parts for entry in entries):
        raise SystemExit(f"unsafe archive path in {name}")
    files = {entry.removeprefix(prefix) for entry in entries if not entry.endswith("/")}
    required = REQUIRED_COMMON | ({"caudex.exe", "sqlite3.dll"} if name.endswith(".zip") else {"caudex"})
    if files != required:
        raise SystemExit(f"unexpected files in {name}: {sorted(files)}")

    if name.endswith(".zip"):
        import zipfile

        with zipfile.ZipFile(path) as archive:
            metadata = json.loads(archive.read(f"{stem}/build-metadata.json"))
    else:
        with tarfile.open(path, "r:gz") as archive:
            metadata = json.loads(archive.extractfile(f"{stem}/build-metadata.json").read())
    if metadata.get("version") != "0.1.0" or metadata.get("optimize") != "ReleaseSafe":
        raise SystemExit(f"invalid build metadata in {name}")
    target = name.removesuffix(".tar.gz").removesuffix(".zip").removeprefix("caudex-workout-cli-0.1.0-")
    if metadata.get("target") != target:
        raise SystemExit(f"target metadata does not match {name}")
    if metadata.get("archiveStem") != stem or metadata.get("platformCodeSigned") is not False:
        raise SystemExit(f"invalid provenance metadata in {name}")
    sqlite = metadata.get("sqlite", {})
    if not all(sqlite.get(key) for key in ("version", "linkage", "source")):
        raise SystemExit(f"incomplete SQLite metadata in {name}")
    if len(sqlite.get("checksum", {}).get("value", "")) != 64:
        raise SystemExit(f"missing SQLite checksum in {name}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    directory = args.directory
    sums = directory / "SHA256SUMS"
    if not sums.is_file():
        raise SystemExit("missing SHA256SUMS")
    expected = {}
    for line in sums.read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        expected[name.removeprefix("*")] = digest
    if set(expected) != set(ASSETS):
        raise SystemExit(f"SHA256SUMS does not cover exactly the release archives: {sorted(expected)}")
    for name in ASSETS:
        verify_archive(directory, name)
        if checksum(directory / name) != expected[name]:
            raise SystemExit(f"checksum mismatch: {name}")
    print("verified CLI release archives, metadata, and SHA256SUMS")


if __name__ == "__main__":
    main()
