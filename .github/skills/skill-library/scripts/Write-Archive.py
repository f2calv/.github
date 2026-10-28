#!/usr/bin/env python3
"""Internal isolated archive writer; importing this file never builds an archive."""

from __future__ import annotations

import io
import hashlib
import json
import os
import platform
import re
import stat
import sys
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, BinaryIO

_LIMITATIONS = [
    "Local artifact only; no installation or publication was performed.",
    "License and notice declarations do not establish redistribution approval.",
    "Digests establish integrity comparison, not publisher authenticity.",
    "Extension loading and native Windows behavior are not verified by this build.",
]


class ArchiveError(Exception):
    """A categorized local build failure safe to report without source content."""


def _checkpoint(name: str, output: _Output) -> None:
    """Internal fault-injection seam; never configured through the public CLI."""


def _open_directory(path: str) -> int:
    if path == "/":
        return os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    if not path.startswith("/") or any(
        part in ("", ".", "..") for part in path.split("/")[1:]
    ):
        raise ArchiveError("Output: Use an unambiguous absolute directory path.")
    descriptor = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in Path(path).parts[1:]:
            child = os.open(
                part,
                os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                dir_fd=descriptor,
            )
            os.close(descriptor)
            descriptor = child
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def _identity(info: os.stat_result) -> tuple[int, int, int, int]:
    return (info.st_dev, info.st_ino, stat.S_IFMT(info.st_mode), info.st_nlink)


@dataclass
class _OwnedFile:
    identity: tuple[int, int, int, int]
    content: bytearray = field(default_factory=bytearray)


class _TrackedFile(io.FileIO):
    def __init__(self, descriptor: int, record: _OwnedFile) -> None:
        super().__init__(descriptor, mode="r+", closefd=True)
        self._record = record

    def write(self, data: bytes | bytearray) -> int:
        position = self.tell()
        written = super().write(data)
        if written is None:
            raise ArchiveError("Output: Output write did not complete.")
        self._record.content[position : position + written] = data[:written]
        if written != len(data):
            raise ArchiveError("Output: Short output write.")
        return written


class _Output:
    def __init__(self, destination: str, boundaries: list[str]) -> None:
        if sys.platform != "linux" or platform.python_implementation() != "CPython":
            raise ArchiveError("Prerequisite: Archive construction requires Linux CPython.")
        if not destination.startswith("/") or any(
            part in ("", ".", "..") for part in destination.split("/")[1:]
        ):
            raise ArchiveError("Output: Use an unambiguous absolute destination.")
        self.path = Path(destination)
        for boundary in boundaries:
            if self.path.is_relative_to(Path(boundary).resolve(strict=True)):
                raise ArchiveError("Output: Destination is inside source or Git storage.")
        self.parent = _open_directory(str(self.path.parent))
        self.directory = -1
        self.created = False
        self.directory_identity: tuple[int, int, int, int] | None = None
        self.files: dict[str, _OwnedFile] = {}
        self.handles: list[BinaryIO] = []

    def reserve(self) -> None:
        os.mkdir(self.path.name, mode=0o700, dir_fd=self.parent)
        self.created = True
        self.directory_identity = _identity(
            os.stat(self.path.name, dir_fd=self.parent, follow_symlinks=False)
        )
        self.directory = os.open(
            self.path.name,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
            dir_fd=self.parent,
        )
        if _identity(os.fstat(self.directory)) != self.directory_identity:
            raise ArchiveError("Output: Reserved directory identity changed.")
        _checkpoint("reserved", self)
        with self.create(".incomplete") as marker:
            marker.write(b"skill-archive/1 incomplete\n")
            marker.flush()
            os.fsync(marker.fileno())
        os.fsync(self.directory)
        os.fsync(self.parent)
        _checkpoint("marker-created", self)

    def create(self, name: str) -> _TrackedFile:
        descriptor = os.open(
            name,
            os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
            dir_fd=self.directory,
        )
        record = _OwnedFile(_identity(os.fstat(descriptor)))
        self.files[name] = record
        stream = _TrackedFile(descriptor, record)
        self.handles.append(stream)
        _checkpoint(f"created:{name}", self)
        return stream

    def _matches(self, name: str) -> bool:
        record = self.files[name]
        try:
            info = os.stat(name, dir_fd=self.directory, follow_symlinks=False)
            if _identity(info) != record.identity or info.st_nlink != 1:
                return False
            descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=self.directory)
            with os.fdopen(descriptor, "rb") as stream:
                return (
                    _identity(os.fstat(stream.fileno())) == record.identity
                    and stream.read() == record.content
                )
        except OSError:
            return False

    def verify(self, names: set[str]) -> None:
        if not self._directory_matches() or set(os.listdir(self.directory)) != names:
            raise ArchiveError("Output: Output directory ownership or contents changed.")
        if any(not self._matches(name) for name in names):
            raise ArchiveError("Output: Output file ownership or content changed.")

    def _directory_matches(self) -> bool:
        return (
            self.directory >= 0
            and _identity(os.fstat(self.directory)) == self.directory_identity
            and _identity(
                os.stat(self.path.name, dir_fd=self.parent, follow_symlinks=False)
            )
            == self.directory_identity
        )

    def remove(self, name: str) -> None:
        if not self._directory_matches() or not self._matches(name):
            raise ArchiveError("Cleanup: Output identity or content changed; retained for recovery.")
        os.unlink(name, dir_fd=self.directory)
        del self.files[name]

    def close(self) -> None:
        for stream in self.handles:
            stream.close()
        if self.directory >= 0:
            descriptor, self.directory = self.directory, -1
            os.close(descriptor)
        if self.parent >= 0:
            descriptor, self.parent = self.parent, -1
            os.close(descriptor)

    def finalize(self, scratch: str) -> None:
        try:
            Path(scratch).lstat()
        except FileNotFoundError:
            pass
        else:
            raise ArchiveError("Cleanup: Scratch cleanup was not completed.")
        _checkpoint("scratch-acknowledged", self)
        self.verify({".incomplete", "package.zip", "package.zip.sha256"})
        self.remove(".incomplete")
        _checkpoint("marker-removed", self)
        self.verify({"package.zip", "package.zip.sha256"})
        os.fsync(self.directory)
        _checkpoint("directory-synced", self)
        os.fsync(self.parent)
        self.close()
        _checkpoint("handles-closed", self)

    def rollback(self) -> bool:
        clean = True
        try:
            for stream in self.handles:
                stream.close()
            if self.created:
                if not self._directory_matches():
                    return False
                for name in tuple(self.files):
                    if self._matches(name):
                        self.remove(name)
                    else:
                        clean = False
                if not os.listdir(self.directory) and self._directory_matches():
                    os.rmdir(self.path.name, dir_fd=self.parent)
                    os.fsync(self.parent)
                else:
                    clean = False
        except OSError:
            clean = False
        finally:
            try:
                self.close()
            except OSError:
                clean = False
        return clean


def _safe_path(value: str) -> None:
    if (
        not value
        or value.startswith("/")
        or any(part in ("", ".", "..") for part in value.split("/"))
        or any(character in value for character in "\\:\x00")
        or any(ord(character) < 32 for character in value)
    ):
        raise ArchiveError("Archive: Unsafe member or evidence path.")
    value.encode("utf-8", errors="strict")


def _canonical(value: Any) -> bytes:
    def validate(item: Any) -> None:
        if item is None or isinstance(item, (bool, int)):
            return
        if isinstance(item, str):
            item.encode("utf-8", errors="strict")
        elif isinstance(item, list):
            for child in item:
                validate(child)
        elif isinstance(item, dict) and all(isinstance(key, str) for key in item):
            for key, child in item.items():
                validate(key)
                validate(child)
        else:
            raise ArchiveError("Archive: Evidence must contain JSON values without floats.")

    validate(value)
    return (
        json.dumps(
            value, sort_keys=True, ensure_ascii=False, allow_nan=False, separators=(",", ":")
        )
        + "\n"
    ).encode("utf-8", errors="strict")


def _manifest(request: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    root = request["Root"]
    builder = request["Builder"]
    if set(root) != {"Id", "Version", "Folder"} or not all(
        isinstance(value, str) and value for value in root.values()
    ):
        raise ArchiveError("Archive: Invalid root evidence.")
    _safe_path(root["Folder"])
    if (
        set(builder) != {"Contract", "ValidationRules", "Files", "Runtimes"}
        or builder["Contract"] != "skill-archive/1"
        or builder["ValidationRules"] != "invoked-tool-bundle"
    ):
        raise ArchiveError("Archive: Invalid trusted builder evidence.")
    inputs = builder["Files"]
    if not isinstance(inputs, list) or not inputs:
        raise ArchiveError("Archive: Missing trusted bundle evidence.")
    for record in inputs:
        if set(record) != {"Path", "Sha256"} or not re.fullmatch(
            r"[0-9a-f]{64}", record["Sha256"]
        ):
            raise ArchiveError("Archive: Invalid trusted bundle digest.")
        _safe_path(record["Path"])
    paths = [record["Path"] for record in inputs]
    if paths != sorted(set(paths), key=lambda path: path.encode("utf-8")):
        raise ArchiveError("Archive: Trusted bundle evidence is not unique and ordered.")
    runtimes = builder["Runtimes"]
    if (
        set(runtimes) != {"PowerShell", "Git", "Python", "PyYAML"}
        or set(runtimes["Python"]) != {"Implementation", "Version"}
        or runtimes["Python"]["Implementation"] != "CPython"
        or not all(
            isinstance(value, str) and value and "/" not in value and "\\" not in value
            for value in [
                runtimes["PowerShell"], runtimes["Git"], runtimes["PyYAML"],
                runtimes["Python"]["Version"],
            ]
        )
    ):
        raise ArchiveError("Archive: Invalid runtime evidence.")
    if not re.fullmatch(r"[0-9a-f]{40,64}", request["SourceCommit"]):
        raise ArchiveError("Archive: Invalid source commit evidence.")
    payload: list[dict[str, Any]] = []
    staged = sorted(request["Payload"], key=lambda record: record["MemberPath"].encode("utf-8"))
    folded: dict[str, str] = {}
    files: set[str] = set()
    for record in staged:
        _safe_path(record["SourcePath"])
        name = record["MemberPath"]
        if (
            name != "payload/" + record["SourcePath"]
            or record["Mode"] not in ("100644", "100755")
            or type(record["Size"]) is not int
            or record["Size"] < 0
            or not re.fullmatch(r"[0-9a-f]{64}", record["Sha256"])
            or not isinstance(record["Owners"], list)
            or not isinstance(record["Reasons"], list)
            or name in files
        ):
            raise ArchiveError("Archive: Invalid payload evidence.")
        for count in range(1, len(name.split("/")) + 1):
            prefix = "/".join(name.split("/")[:count])
            key = prefix.casefold()
            if (key in folded and folded[key] != prefix) or prefix in files:
                raise ArchiveError("Archive: Conflicting member names.")
            folded[key] = prefix
        files.add(name)
        payload.append({key: record[key] for key in (
            "SourcePath", "MemberPath", "Mode", "Size", "Sha256", "Owners", "Reasons"
        )})
    if not payload or not isinstance(request["Components"], list):
        raise ArchiveError("Archive: Missing required inventory evidence.")
    for component in request["Components"]:
        if component["SourceCommit"] != request["SourceCommit"] or any(
            reason["Kind"] not in ("root", "required") for reason in component["Reasons"]
        ):
            raise ArchiveError("Archive: Non-required component evidence.")
    return {
        "SchemaVersion": 1,
        "SourceCommit": request["SourceCommit"],
        "Root": root,
        "OptionalSelections": [],
        "Builder": builder,
        "Components": request["Components"],
        "Payload": payload,
        "GeneratedMembers": [{"Path": "manifest.json", "Role": "build-evidence", "Mode": "100644"}],
        "Limitations": _LIMITATIONS,
    }, staged


def _predicted_size(manifest: bytes, records: list[dict[str, Any]]) -> int:
    members = [("manifest.json", len(manifest))] + [
        (record["MemberPath"], record["Size"]) for record in records
    ]
    if len(members) > 65534 or any(len(name.encode("utf-8")) > 65489 for name, _ in members):
        raise ArchiveError("Archive: Classic ZIP member or name limit exceeded.")
    size = 22 + sum(76 + 2 * len(name.encode("utf-8")) + length for name, length in members)
    if size > 1 << 30:
        raise ArchiveError("Archive: Predicted archive exceeds the one GiB limit.")
    return size


def _read_staged(record: dict[str, Any], scratch: str) -> bytes:
    path = Path(record["StagedPath"])
    if path.parent != Path(scratch) / "payload" or not path.name.isascii() or not path.name.isdecimal():
        raise ArchiveError("Inspection: Invalid staged input location.")
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size != record["Size"]:
            raise ArchiveError("Inspection: Staged input identity or size changed.")
        data = stream.read(record["Size"] + 1)
    if len(data) != record["Size"] or hashlib.sha256(data).hexdigest() != record["Sha256"]:
        raise ArchiveError("Inspection: Staged input content changed.")
    return data


def _zip_info(name: str, mode: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_STORED
    info.create_system = 3
    info.create_version = 20
    info.extract_version = 20
    info.external_attr = int(mode, 8) << 16
    info.internal_attr = 0
    info.extra = b""
    info.comment = b""
    return info


def _read_owned(output: _Output, name: str) -> bytes:
    if not output._matches(name):
        raise ArchiveError("Output: Completed output changed before verification.")
    descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=output.directory)
    with os.fdopen(descriptor, "rb") as stream:
        if _identity(os.fstat(stream.fileno())) != output.files[name].identity:
            raise ArchiveError("Output: Completed output identity changed.")
        return stream.read()


def _write_archive(
    output: _Output, request: dict[str, Any], manifest: bytes,
    records: list[dict[str, Any]], predicted: int,
) -> str:
    with output.create("package.zip") as stream:
        with zipfile.ZipFile(stream, mode="w", compression=zipfile.ZIP_STORED, allowZip64=False) as archive:
            archive.writestr(_zip_info("manifest.json", "100644"), manifest)
            for record in records:
                _checkpoint("before-staged-read", output)
                data = _read_staged(record, request["Scratch"])
                archive.writestr(_zip_info(record["MemberPath"], record["Mode"]), data)
                _checkpoint("member-written", output)
        _checkpoint("zip-closed", output)
        stream.flush()
        os.fsync(stream.fileno())
        _checkpoint("zip-synced", output)
    data = _read_owned(output, "package.zip")
    if len(data) != predicted:
        raise ArchiveError("Archive: Completed ZIP size does not match the byte contract.")
    _checkpoint("before-hash", output)
    digest = hashlib.sha256(data).hexdigest()
    checksum = f"{digest}  package.zip\n".encode("ascii")
    with output.create("package.zip.sha256") as stream:
        stream.write(checksum)
        stream.flush()
        os.fsync(stream.fileno())
    _checkpoint("checksum-synced", output)
    output.verify({".incomplete", "package.zip", "package.zip.sha256"})
    if _read_owned(output, "package.zip.sha256") != checksum:
        raise ArchiveError("Output: Detached checksum verification failed.")
    with zipfile.ZipFile(io.BytesIO(data), mode="r") as archive:
        if archive.namelist() != ["manifest.json"] + [record["MemberPath"] for record in records] or archive.testzip() is not None:
            raise ArchiveError("Archive: Independent ZIP verification failed.")
        if archive.read("manifest.json") != manifest:
            raise ArchiveError("Archive: Embedded evidence verification failed.")
    return digest


def _emit(message: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(message, ensure_ascii=True, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def main() -> int:
    """Run the internal preparation/finalization protocol, never expose partial success."""
    output: _Output | None = None
    try:
        request = json.loads(sys.stdin.readline())
        model, records = _manifest(request)
        manifest = _canonical(model)
        predicted = _predicted_size(manifest, records)
        output = _Output(request["Destination"], request["Boundaries"])
        output.reserve()
        digest = _write_archive(output, request, manifest, records, predicted)
        _emit({"Status": "Prepared"})
        if sys.stdin.readline() != "finalize\n":
            raise ArchiveError("Cleanup: Scratch cleanup acknowledgment was not received.")
        output.finalize(request["Scratch"])
        _checkpoint("before-final-acknowledgment", output)
        _emit({"Status": "Completed", "Result": {
            "SourceCommit": request["SourceCommit"],
            "RootId": model["Root"]["Id"],
            "RootVersion": model["Root"]["Version"],
            "OutputDirectory": str(output.path),
            "ArchivePath": str(output.path / "package.zip"),
            "ChecksumPath": str(output.path / "package.zip.sha256"),
            "ArchiveSha256": digest,
            "PayloadCount": len(records),
            "ArchiveContract": "skill-archive/1",
        }})
        return 0
    except (Exception, KeyboardInterrupt) as error:
        category = "Output" if isinstance(error, OSError) else "Archive"
        if isinstance(error, ArchiveError):
            category = str(error).partition(":")[0]
        if output is not None and not output.rollback():
            category = "Cleanup"
        try:
            _emit({"Status": "Failed", "Category": category})
        except (BrokenPipeError, OSError):
            pass
        return 1


if __name__ == "__main__":
    sys.exit(main())
