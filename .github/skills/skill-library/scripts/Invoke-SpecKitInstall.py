#!/usr/bin/env python3
"""Inspect local inputs and delegate an approved root installation to Spec Kit."""

from __future__ import annotations

import ast
import base64
import copy
import contextlib
import hashlib
import importlib.metadata
import importlib.util
import json
import os
import platform
import re
import stat
import sys
import tempfile
import warnings
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, BinaryIO

CONTRACT = "skill-workspace-install/1"
MAX_MEMBER = 16 * 1024 * 1024
MAX_ARCHIVE = 64 * 1024 * 1024
MAX_STATE = 4 * 1024 * 1024


class _InspectionError(ValueError):
    """Reject an unsupported or ambiguous inspection input."""

    def __init__(self, code: str = "Prerequisite", scope: str = "inspection") -> None:
        super().__init__("Unsupported or ambiguous inspection input.")
        self.code = code
        self.scope = scope


def _require(condition: bool, code: str, scope: str) -> None:
    if not condition:
        raise _InspectionError(code, scope)


def _unique_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise _InspectionError()
        result[key] = value
    return result


def _read_json(text: str) -> Any:
    def reject_constant(value: str) -> None:
        raise _InspectionError()

    return json.loads(text, object_pairs_hook=_unique_pairs, parse_constant=reject_constant)


def _safe_path(value: str, *, missing: bool = False) -> Path:
    _require(isinstance(value, str) and value.startswith("/") and "\\" not in value, "Workspace", "path")
    _require(value == "/" or not any(part in ("", ".", "..") for part in value.split("/")[1:]), "Workspace", "path")
    target = Path(value)
    for current in reversed((target, *target.parents)):
        try:
            details = current.lstat()
        except FileNotFoundError:
            _require(missing, "Workspace", "missing-path")
            continue
        _require(not stat.S_ISLNK(details.st_mode), "Ownership", "linked-path")
        _require(current == target or stat.S_ISDIR(details.st_mode), "Workspace", "ancestor")
    return target


def _bytes(path: Path, limit: int = MAX_STATE) -> bytes:
    _safe_path(str(path))
    details = path.lstat()
    _require(stat.S_ISREG(details.st_mode) and details.st_size <= limit, "Ownership", "file")
    with path.open("rb") as stream:
        data = stream.read(limit + 1)
    _require(len(data) <= limit, "Prerequisite", "bounded-read")
    return data


def _digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _read_yaml(text: str) -> Any:
    reader_path = Path(__file__).with_name("Read-Metadata.py")
    spec = importlib.util.spec_from_file_location("_skill_library_metadata", reader_path)
    _require(spec is not None and spec.loader is not None, "Prerequisite", "yaml-reader")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module._read(text, False)


def _path_record(root: Path, path: Path) -> dict[str, Any]:
    _safe_path(str(path), missing=True)
    relative = path.relative_to(root).as_posix() if path.is_relative_to(root) else str(path)
    try:
        details = path.lstat()
    except FileNotFoundError:
        return {"Path": relative, "Presence": "absent"}
    _require(stat.S_ISDIR(details.st_mode) or stat.S_ISREG(details.st_mode), "Ownership", "path-type")
    record: dict[str, Any] = {
        "Path": relative, "Presence": "present", "Type": "directory" if path.is_dir() else "file",
        "Device": details.st_dev, "Inode": details.st_ino, "Mode": f"{stat.S_IMODE(details.st_mode):04o}",
    }
    if path.is_file():
        _require(details.st_nlink == 1, "Ownership", "managed-file-links")
        data = _bytes(path, MAX_ARCHIVE)
        record.update(Size=len(data), Sha256=_digest(data))
    return record


def _tree(root: Path, directory: Path) -> list[dict[str, Any]]:
    result = [_path_record(root, directory)]
    if directory.exists():
        _require(directory.is_dir(), "Workspace", "managed-directory")
        for child in sorted(directory.iterdir()):
            _require(len(result) < 10000, "Prerequisite", "managed-tree-limit")
            record = _path_record(root, child)
            result.extend(_tree(root, child) if record.get("Type") == "directory" else [record])
    return result


def _inspect_runtime() -> dict[str, Any]:
    import yaml

    _require(sys.platform == "linux" and platform.python_implementation() == "CPython" and sys.version_info >= (3, 11), "Prerequisite", "platform")
    _require(yaml.__version__ == "6.0.3", "Prerequisite", "yaml")
    distribution = importlib.metadata.distribution("specify-cli")
    _require(distribution.version == "1.2.3", "Prerequisite", "spec-kit-version")
    package = Path(distribution.locate_file("specify_cli"))
    manager = ast.parse(_bytes(package / "extensions/__init__.py").decode("utf-8"))
    methods = [node for node in ast.walk(manager) if isinstance(node, ast.FunctionDef) and node.name == "install_from_archive"]
    _require(len(methods) == 1, "Prerequisite", "archive-api")
    method = methods[0]
    _require([item.arg for item in method.args.args] == ["self", "archive_path", "speckit_version", "priority", "force"], "Prerequisite", "archive-api")
    _require([item.arg for item in method.args.kwonlyargs] == ["archive_file", "source_name", "content_type", "catalog_name", "expected_id", "expected_version"], "Prerequisite", "archive-api")
    _require([ast.literal_eval(value) for value in method.args.defaults] == [10, False], "Prerequisite", "archive-api")
    tools = []
    for entry in distribution.files or []:
        if str(entry).startswith("specify_cli/") and str(entry).endswith(".py"):
            path = Path(distribution.locate_file(entry))
            data = _bytes(path)
            _require(entry.hash is not None and entry.hash.mode == "sha256", "Prerequisite", "runtime-record")
            expected = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).decode().rstrip("=")
            _require(entry.hash.value == expected, "Prerequisite", "runtime-integrity")
            tools.append({"Role": "spec-kit-module", "Path": str(path), "Sha256": _digest(data)})
    _require(bool(tools), "Prerequisite", "runtime-modules")
    interpreter = Path(sys.executable).resolve(strict=True)
    tools.append({"Role": "interpreter", "Path": str(interpreter), "Sha256": _digest(_bytes(interpreter, MAX_ARCHIVE)), "Version": platform.python_version(), "InvocationPath": sys.executable})
    for dependency in ("PyYAML", "packaging"):
        dependency_distribution = importlib.metadata.distribution(dependency)
        for entry in dependency_distribution.files or []:
            if str(entry).endswith(".py"):
                path = Path(dependency_distribution.locate_file(entry))
                tools.append({"Role": dependency, "Path": str(path), "Sha256": _digest(_bytes(path)), "Version": dependency_distribution.version})
    return {"Version": distribution.version, "Package": str(package), "Tools": tools}


def _operation_guard(root: Path) -> list[dict[str, Any]]:
    namespace = root / ".specify/skill-library-install"
    records = _tree(root, namespace)
    if not namespace.exists():
        return records
    marker = _read_json(_bytes(namespace / "owner.json").decode("utf-8"))
    _require(marker == {"Contract": CONTRACT, "Kind": "operation-namespace"}, "OperationState", "owner-marker")
    _require(stat.S_IMODE(namespace.stat().st_mode) == 0o700 and stat.S_IMODE((namespace / "owner.json").stat().st_mode) == 0o600, "OperationState", "operation-mode")
    _require(not (namespace / "lock").exists(), "OperationState", "lock")
    _require({child.name for child in namespace.iterdir()} <= {"owner.json", "operations"}, "OperationState", "namespace-content")
    operations = namespace / "operations"
    if operations.exists():
        _require(operations.is_dir() and stat.S_IMODE(operations.stat().st_mode) == 0o700, "OperationState", "operations")
        for directory in operations.iterdir():
            _require(directory.is_dir() and len(directory.name) == 64 and all(char in "0123456789abcdef" for char in directory.name), "OperationState", "operation-id")
            receipt = _read_json(_bytes(directory / "operation.json", MAX_ARCHIVE).decode("utf-8"))
            required = {"Contract", "OperationId", "ReviewedFingerprint", "ApprovedInputs", "State", "Extensions", "IntendedPaths", "ObservedPaths", "RecoveryLocations", "LastDurableStep"}
            _require(isinstance(receipt, dict) and set(receipt) == required, "OperationState", "receipt-shape")
            _require(receipt["Contract"] == CONTRACT and receipt["OperationId"] == directory.name == receipt["ReviewedFingerprint"], "OperationState", "receipt-identity")
            _require(receipt["State"] == "Completed" and receipt["LastDurableStep"] == "Completed", "OperationState", "unfinished-operation")
            approved = receipt["ApprovedInputs"]
            _require(isinstance(approved, dict) and approved.get("Contract") == CONTRACT and approved.get("Ready") is True and approved.get("Fingerprint") == directory.name, "OperationState", "approved-evidence")
            projection = copy.deepcopy(approved)
            projection["Ready"] = False
            projection["Fingerprint"] = None
            for write in projection["IntendedWrites"]:
                write["Path"] = write["Path"].replace(f"/operations/{directory.name}", "/operations/{operation}")
            _require(_digest(_canonical_bytes(projection)) == directory.name, "OperationState", "approved-fingerprint")
            _require(isinstance(receipt["Extensions"], list) and bool(receipt["Extensions"]) and all(isinstance(item, dict) and item.get("State") == "Verified" for item in receipt["Extensions"]), "OperationState", "unfinished-extension")
            expected_ids = [item["RootId"] for item in approved["Extensions"]]
            actual_ids = [item.get("RootId") for item in receipt["Extensions"]]
            _require(actual_ids == expected_ids and len(set(actual_ids)) == len(actual_ids) and bool(receipt["ObservedPaths"]), "OperationState", "receipt-outcomes")
            _require(all(isinstance(receipt[key], list) for key in ("IntendedPaths", "ObservedPaths", "RecoveryLocations")), "OperationState", "receipt-evidence")
            _require(stat.S_IMODE(directory.stat().st_mode) == 0o700 and stat.S_IMODE((directory / "operation.json").stat().st_mode) == 0o600, "OperationState", "receipt-mode")
            _require({child.name for child in directory.iterdir()} <= {"operation.json", "scratch"}, "OperationState", "retained-operation-content")
            scratch = directory / "scratch"
            if scratch.exists():
                _require(scratch.is_dir() and stat.S_IMODE(scratch.stat().st_mode) == 0o700 and not any(scratch.iterdir()), "OperationState", "retained-operation-scratch")
    return records


def _inspect_workspace(request: dict[str, Any], runtime: dict[str, Any]) -> dict[str, Any]:
    import yaml

    root = _safe_path(request["WorkspacePath"])
    source = _safe_path(request["RepoRoot"])
    _require(root.is_dir() and source.is_dir() and not root.is_relative_to(source) and not source.is_relative_to(root), "Workspace", "source-separation")
    paths: dict[str, dict[str, Any]] = {}

    def capture(path: Path) -> dict[str, Any]:
        record = _path_record(root, path)
        paths[record["Path"]] = record
        return record

    for ancestor in (root, *root.parents):
        capture(ancestor)
    try:
        for record in _operation_guard(root):
            paths[record["Path"]] = record
    except (ValueError, OSError, TypeError, KeyError) as error:
        raise _InspectionError("OperationState", "prior-operation") from error
    init_path = root / ".specify/init-options.json"
    capture(init_path)
    options = _read_json(_bytes(init_path).decode("utf-8"))
    _require(isinstance(options, dict) and options.get("ai") == "copilot" and options.get("ai_skills") is True, "Prerequisite", "copilot-skills-init")
    _require(options.get("integration_options", {}) in ({}, {"skills": True}) and not options.get("ai_commands") and not options.get("ai_skills_dir"), "Prerequisite", "init-options")
    _require(set(options) <= {"ai", "ai_skills", "script", "ignore_agent_tools", "integration_options", "allow_symlinks", "feature_numbering", "here", "integration", "speckit_version"}, "Prerequisite", "unknown-init-effects")
    _require(options.get("allow_symlinks", False) is False and options.get("integration", "copilot") == "copilot" and options.get("speckit_version", "1.2.3") == "1.2.3", "Prerequisite", "init-identity")
    _require(type(options.get("here", True)) is bool and options.get("feature_numbering", "sequential") == "sequential", "Prerequisite", "init-layout")
    for relative in (".specify", ".github", ".github/skills", ".github/hooks", ".specify/extensions", ".specify/extensions/.registry", ".specify/extensions.yml", ".specify/integration.json", ".specify/integrations", ".specify/skill-library-install", ".specify/skill-library-install/owner.json", ".specify/skill-library-install/lock", ".specify/skill-library-install/operations"):
        capture(root / relative)
    for relative in (".github/skills", ".specify/scripts", ".specify/extensions", ".specify/integrations"):
        for record in _tree(root, root / relative):
            paths[record["Path"]] = record
            path = root / record["Path"]
            if record.get("Type") == "file" and path.suffix == ".sh":
                data = _bytes(path, MAX_ARCHIVE)
                _require(not data.startswith(b"#!") or bool(int(record["Mode"], 8) & 0o111), "Workspace", "collateral-chmod")
    registry_path = root / ".specify/extensions/.registry"
    registry = {"schema_version": "1.0", "extensions": {}}
    if registry_path.exists():
        raw = _bytes(registry_path)
        registry = _read_json(raw.decode("utf-8"))
        _require(isinstance(registry, dict) and set(registry) == {"schema_version", "extensions"} and registry["schema_version"] == "1.0" and isinstance(registry["extensions"], dict), "Workspace", "registry")
        _require(raw == json.dumps(registry, indent=2).encode(), "Workspace", "registry-format")
        _require(all(isinstance(key, str) and isinstance(value, dict) for key, value in registry["extensions"].items()), "Workspace", "registry-entries")
    config = root / ".specify/extensions.yml"
    configuration = {"installed": [], "settings": {"auto_execute_hooks": True}, "hooks": {}}
    if config.exists():
        raw = _bytes(config)
        configuration = _read_yaml(raw.decode("utf-8"))
        _require(isinstance(configuration, dict) and set(configuration) == {"installed", "settings", "hooks"}, "Prerequisite", "extension-config")
        _require(configuration["hooks"] == {} and isinstance(configuration["settings"], dict) and set(configuration["settings"]) == {"auto_execute_hooks"} and type(configuration["settings"]["auto_execute_hooks"]) is bool, "Prerequisite", "extension-hooks")
        installed = configuration["installed"]
        _require(isinstance(installed, list) and all(isinstance(item, str) and re.fullmatch(r"[a-z0-9-]+", item) for item in installed), "Workspace", "installed-list")
        _require(installed == sorted(set(installed)) and set(installed) == set(registry["extensions"]), "Ownership", "registration-config-consistency")
        _require(raw == yaml.dump(configuration, default_flow_style=False, sort_keys=False, allow_unicode=True).encode("utf-8"), "Workspace", "extension-config-format")
    integration_path = root / ".specify/integration.json"
    if integration_path.exists():
        integration_state = _read_json(_bytes(integration_path).decode("utf-8"))
        _require(isinstance(integration_state, dict) and set(integration_state) <= {"version", "integration", "default_integration", "integration_state_schema", "installed_integrations", "integration_settings"}, "Prerequisite", "integration-state")
        _require(type(integration_state.get("integration_state_schema", 1)) is int and integration_state.get("integration_state_schema", 1) == 1, "Prerequisite", "integration-schema")
        _require(integration_state.get("integration", "copilot") == "copilot" and integration_state.get("default_integration", "copilot") == "copilot" and integration_state.get("installed_integrations", ["copilot"]) == ["copilot"], "Prerequisite", "integration-identity")
        settings = integration_state.get("integration_settings", {})
        _require(settings in ({}, {"copilot": {}}, {"copilot": {"parsed_options": {"skills": True}}}, {"copilot": {"script": "ps", "invoke_separator": "-"}}, {"copilot": {"script": "sh", "invoke_separator": "-"}}), "Prerequisite", "integration-settings")
    integration_root = root / ".specify/integrations"
    if integration_root.exists():
        for path in integration_root.rglob("*"):
            if not path.is_file():
                continue
            relative = path.relative_to(integration_root).as_posix()
            if relative.endswith(".py"):
                _require(relative == "copilot/__init__.py" and _bytes(path) == _bytes(Path(runtime["Package"]) / "integrations/copilot/__init__.py"), "Prerequisite", "project-adapter")
            elif relative == "packages.json":
                _require(_read_json(_bytes(path).decode()) == {"schema_version": "1.0", "packages": {}}, "Prerequisite", "external-integrations")
            elif relative == "copilot.manifest.json":
                manifest = _read_json(_bytes(path).decode("utf-8"))
                _require(isinstance(manifest, dict) and set(manifest) == {"integration", "version", "installed_at", "files"}, "Prerequisite", "integration-manifest")
                _require(manifest["integration"] == "copilot" and manifest["version"] == "1.2.3" and isinstance(manifest["files"], dict), "Prerequisite", "integration-manifest")
                _require(isinstance(manifest["installed_at"], str) and datetime.fromisoformat(manifest["installed_at"]).tzinfo is not None, "Prerequisite", "integration-manifest-time")
                for name, digest in manifest["files"].items():
                    _require(isinstance(name, str) and re.fullmatch(r"\.github/skills/speckit-[a-z][a-z-]*/SKILL\.md", name) is not None, "Prerequisite", "integration-manifest-path")
                    record = capture(root / name)
                    _require(isinstance(digest, str) and record.get("Sha256") == digest, "Prerequisite", "integration-manifest-hash")
            elif relative.endswith(".json"):
                _read_json(_bytes(path).decode())
                _require(False, "Prerequisite", "unpredicted-integration-manifest")
            else:
                _require(relative.startswith("copilot/__pycache__/") and relative.endswith(".pyc"), "Prerequisite", "integration-content")
    _require(not (root / ".github/hooks").exists(), "Prerequisite", "copilot-events")
    identities = request.get("RootIds") or ([request["RootId"]] if request.get("RootId") else [])
    _require(isinstance(identities, list) and len(identities) <= 16 and len(set(identities)) == len(identities), "Selection", "extension-roots")
    for identity in identities:
        _require(isinstance(identity, str) and re.fullmatch(r"[a-z0-9][a-z0-9-]*", identity) is not None, "Selection", "extension-id")
        rescue_suffix = _digest(identity.encode("utf-8"))[:16]
        for relative, code in (
            (f".specify/extensions/{identity}", "Ownership"),
            (f".github/skills/speckit-{identity}-load", "CommandConflict"),
            (f".specify/extensions/.rescue-staging-{rescue_suffix}", "OperationState"),
        ):
            record = capture(root / relative)
            _require(record["Presence"] == "absent", code, "occupied-target")
        _require(identity not in registry["extensions"], "Ownership", "registered-id")
        _require(identity not in configuration["installed"], "Ownership", "configured-id")
    for relative in request.get("AdditionalPaths", []):
        _require(isinstance(relative, str) and not relative.startswith("/") and ".." not in relative.split("/") and "\\" not in relative, "Workspace", "intended-path")
        if "{operation}" not in relative:
            capture(root / relative)
    prediction = None
    predictions = []
    after = copy.deepcopy(configuration)
    for identity in identities:
        after["installed"] = sorted([*after["installed"], identity])
        encoded = yaml.dump(after, default_flow_style=False, sort_keys=False, allow_unicode=True).encode("utf-8")
        prediction = {"Path": ".specify/extensions.yml", "Size": len(encoded), "Sha256": _digest(encoded), "AddedId": identity, "Hooks": "unchanged-empty"}
        predictions.append(prediction)
    return {"WorkspacePath": str(root), "Runtime": runtime, "Paths": list(paths.values()), "Registry": {"SchemaVersion": "1.0", "RegisteredIds": sorted(registry["extensions"])}, "ConfigurationPrediction": prediction, "ConfigurationPredictions": predictions}


def _canonical(value: Any, collection: str = "", depth: int = 0) -> Any:
    _require(depth <= 64, "VerificationFailure", "canonical-depth")
    if value is None or isinstance(value, (bool, int)):
        return value
    if isinstance(value, str):
        value.encode("utf-8", errors="strict")
        return value
    if isinstance(value, dict):
        _require(all(isinstance(key, str) for key in value), "VerificationFailure", "canonical-keys")
        return {key: _canonical(value[key], key, depth + 1) for key in sorted(value, key=lambda item: item.encode("utf-8"))}
    _require(isinstance(value, list), "VerificationFailure", "canonical-type")
    entries = [_canonical(item, collection, depth + 1) for item in value]

    def key(item: Any) -> tuple[Any, ...]:
        full = json.dumps(item, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
        if isinstance(item, str):
            return (item.encode("utf-8"), full)
        fields: tuple[str, ...] = ()
        if isinstance(item, dict):
            if collection == "Tools":
                fields = ("Role", "Path")
            elif collection == "OptionalOffers":
                fields = ("DeclaringId", "SelectionKey", "OptionalIndex")
            elif collection in ("Extensions", "ExtensionRoots", "RequiredInventories"):
                fields = ("Position",)
            elif collection in ("ActiveComponents", "Components"):
                fields = ("Id",)
            elif collection == "IntendedWrites":
                fields = ("Path", "Position", "Effect")
            elif collection in ("Payload", "Overlaps"):
                fields = ("SourcePath",)
            elif collection == "Members":
                fields = ("MemberPath",)
            elif collection in ("CatalogOrigins", "ArtifactOrigins", "Paths", "Files"):
                fields = ("Path", "EntryKey") if collection == "CatalogOrigins" else ("Path",)
        primary = []
        for field in fields:
            part = item.get(field, -1 if field in ("Position", "OptionalIndex") else "")
            if field in ("Position", "OptionalIndex"):
                _require(type(part) is int, "VerificationFailure", "canonical-index")
                primary.append(part)
            else:
                _require(isinstance(part, str), "VerificationFailure", "canonical-key")
                primary.append(part.encode("utf-8"))
        return (*primary, full)

    return sorted(entries, key=key)


def _canonical_bytes(value: Any) -> bytes:
    return json.dumps(_canonical(value), ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")


def _catalog(request: dict[str, Any]) -> dict[str, Any]:
    root = request["Root"]
    matches = []
    origins = []
    supplied = request["CatalogPath"]
    _require(isinstance(supplied, list) and bool(supplied) and len(set(supplied)) == len(supplied), "Catalog", "catalog-inputs")
    for location in supplied:
        path = _safe_path(location)
        raw = _bytes(path)
        catalog = _read_json(raw.decode("utf-8"))
        _require(isinstance(catalog, dict) and set(catalog) == {"schema_version", "extensions"} and catalog["schema_version"] == "1.0" and isinstance(catalog["extensions"], dict), "Catalog", "catalog-shape")
        origins.append({"Path": str(path), "Size": len(raw), "Sha256": _digest(raw)})
        if root["Id"] in catalog["extensions"]:
            record = catalog["extensions"][root["Id"]]
            _require(isinstance(record, dict) and record.get("version") == root["Version"], "Catalog", "catalog-version")
            matches.append(record)
    _require(len(matches) == 1, "Catalog", "selected-record")
    record = matches[0]
    _require(set(record) == {"name", "description", "version", "download_url", "sha256", "requires", "provides"}, "Catalog", "selected-record-shape")
    _require(isinstance(record["sha256"], str) and re.fullmatch(r"[a-f0-9]{64}", record["sha256"]) is not None, "Catalog", "catalog-digest")
    _require(isinstance(record["download_url"], str) and record["download_url"].startswith(("https://", "http://localhost:", "http://127.0.0.1:")) and not any(char in record["download_url"] for char in ("@", "?", "#")), "Catalog", "provenance-url")
    return {"Record": record, "CatalogOrigins": origins}


def _render_command(root: dict[str, Any], loader: str) -> str:
    from specify_cli._utils import dump_frontmatter
    from specify_cli.agents import CommandRegistrar

    lines = loader.splitlines(keepends=True)
    _require(lines[0].strip() == "---", "Artifact", "loader-frontmatter")
    end = next(index for index in range(1, len(lines)) if lines[index].strip() == "---")
    frontmatter = _read_yaml("".join(lines[1:end]))
    _require(set(frontmatter) == {"description"}, "Artifact", "loader-capabilities")
    body = "".join(lines[end + 1:]).strip()
    _require("__SPECKIT_" not in body and "{SCRIPT}" not in body, "Artifact", "loader-placeholders")
    name = f"speckit-{root['Id']}-load"
    metadata = CommandRegistrar.build_skill_frontmatter("copilot", name, frontmatter["description"], f"extension:{root['Id']}")
    title = f"{root['Id']} load".replace(".", " ").replace("-", " ").title()
    return f"---\n{dump_frontmatter(metadata)}\n---\n\n# {title} Skill\n\n{body}\n"


def _verify_artifact(request: dict[str, Any], stream: BinaryIO | None = None) -> dict[str, Any]:
    selection = request["Selection"]
    root = selection["Root"]
    _require(re.fullmatch(r"[a-z0-9][a-z0-9-]*", root["Id"]) is not None and re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", root["Version"]) is not None, "Artifact", "literal-root")
    catalog = request["Catalog"]
    path = _safe_path(request["ArchivePath"])
    if stream is None:
        with path.open("rb") as opened:
            return _verify_artifact(request, opened)
    details = os.fstat(stream.fileno())
    current = path.lstat()
    _require(stat.S_ISREG(details.st_mode) and details.st_nlink == 1 and details.st_size <= MAX_ARCHIVE and (details.st_dev, details.st_ino) == (current.st_dev, current.st_ino), "Artifact", "archive-identity")
    stream.seek(0)
    raw = stream.read(MAX_ARCHIVE + 1)
    _require(len(raw) == details.st_size and len(raw) <= MAX_ARCHIVE, "Artifact", "archive-limit")
    _require(_digest(raw) == catalog["sha256"], "Artifact", "archive-digest")
    members: dict[str, bytes] = {}
    evidence = []
    total = 0
    stream.seek(0)
    with zipfile.ZipFile(stream) as archive:
        for info in archive.infolist():
            name = info.filename
            _require(name and not name.startswith("/") and "\\" not in name and not any(part in ("", ".", "..") for part in name.split("/")), "Artifact", "member-path")
            _require(name not in members and not info.is_dir() and not info.flag_bits & 1 and info.compress_type == zipfile.ZIP_STORED, "Artifact", "member-type")
            mode = info.external_attr >> 16
            _require(mode in (0o100644, 0o100755) and info.file_size <= MAX_MEMBER, "Artifact", "member-mode-size")
            total += info.file_size
            _require(total <= MAX_ARCHIVE, "Artifact", "payload-limit")
            with archive.open(info) as member:
                data = member.read(MAX_MEMBER + 1)
            _require(len(data) == info.file_size and len(data) <= MAX_MEMBER, "Artifact", "member-read")
            members[name] = data
            evidence.append({"MemberPath": name, "Mode": f"{mode:o}", "Size": len(data), "Sha256": _digest(data)})
    expected_names = {"extension.yml", "source-manifest.json", "commands/load.md", "extension-build.json"} | {f"resources/library/{item['SourcePath']}" for item in selection["Payload"]}
    _require(set(members) == expected_names, "Artifact", "exact-membership")
    manifest = _read_json(members["source-manifest.json"].decode("utf-8"))
    _require(isinstance(manifest, dict) and set(manifest) == {"SchemaVersion", "SourceCommit", "Root", "OptionalSelections", "Builder", "Components", "Payload", "GeneratedMembers", "Limitations"}, "Artifact", "source-manifest-shape")
    _require(manifest["GeneratedMembers"] == [{"Path": "manifest.json", "Role": "build-evidence", "Mode": "100644"}] and isinstance(manifest["Limitations"], list) and all(isinstance(item, str) for item in manifest["Limitations"]), "Artifact", "source-generated-evidence")
    _require(manifest.get("SchemaVersion") == 1 and manifest.get("SourceCommit") == selection["SourceCommit"] and manifest.get("Root") == root and manifest.get("OptionalSelections") == [], "Artifact", "source-identity")
    _require(manifest.get("Builder", {}).get("Contract") == "skill-archive/1", "Artifact", "source-builder")
    _require(_canonical_bytes(manifest.get("Components")) == _canonical_bytes(selection["Inventory"]["Components"]) and _canonical_bytes(manifest.get("Payload")) == _canonical_bytes(selection["Payload"]), "Artifact", "committed-inventory")
    build = _read_json(members["extension-build.json"].decode("utf-8"))
    _require(set(build) == {"Contract", "SourceArchiveSha256", "SourceCommit", "Root", "SpecKitVersion"} and build["Contract"] == "skill-extension-pilot/1" and build["SourceCommit"] == selection["SourceCommit"] and build["Root"] == root and build["SpecKitVersion"] == "1.2.3", "Artifact", "build-evidence")
    _require(isinstance(build["SourceArchiveSha256"], str) and re.fullmatch(r"[a-f0-9]{64}", build["SourceArchiveSha256"]) is not None, "Artifact", "source-archive-digest")
    runtime = _read_yaml(members["extension.yml"].decode("utf-8"))
    description = f"Load the packaged {root['Id']} skill and its required resources."
    command = {"name": f"speckit.{root['Id']}.load", "file": "commands/load.md", "description": description}
    expected_runtime = {
        "schema_version": "1.0", "extension": {"id": root["Id"], "name": root["Id"], "version": root["Version"], "description": description, "effect": "read-only"},
        "requires": {"speckit_version": "==1.2.3"}, "provides": {"commands": [command]},
    }
    _require(runtime == expected_runtime and catalog["requires"] == runtime["requires"] and catalog["provides"] == runtime["provides"] and catalog["name"] == root["Id"] and catalog["description"] == description, "Artifact", "command-only-profile")
    for record in selection["Payload"]:
        name = f"resources/library/{record['SourcePath']}"
        data = members[name]
        member_record = next(item for item in evidence if item["MemberPath"] == name)
        _require(len(data) == record["Size"] and _digest(data) == record["Sha256"] and member_record["Mode"] == record["Mode"], "Artifact", "canonical-resource")
        executable = name.endswith(".sh") and data.startswith(b"#!")
        _require(record["Mode"] == ("100755" if executable else "100644"), "Artifact", "canonical-mode-change")
    _require(all(item["Mode"] == "100644" for item in evidence if not item["MemberPath"].startswith("resources/library/")), "Artifact", "generated-mode")
    loader = members["commands/load.md"].decode("utf-8")
    _require(loader == request["ExpectedLoader"], "Artifact", "generated-loader")
    rendered = _render_command(root, loader)
    return {
        "RootId": root["Id"], "Version": root["Version"], "Position": 0,
        "Archive": {"Path": str(path), "Size": len(raw), "Sha256": _digest(raw)},
        "CatalogUrl": catalog["download_url"], "BuildEvidence": build, "SourceManifest": manifest,
        "RuntimeManifest": runtime, "Members": evidence,
        "Command": {"Id": command["name"], "Path": f".github/skills/speckit-{root['Id']}-load/SKILL.md", "Size": len(rendered.encode()), "Sha256": _digest(rendered.encode())},
        "RegistryAddition": {"version": root["Version"], "source": "local", "manifest_hash": f"sha256:{_digest(members['extension.yml'])}", "enabled": True, "priority": 10, "registered_commands": {}, "registered_skills": [f"speckit-{root['Id']}-load"], "installed_at": "{runtime-utc-iso8601}"},
    }


def _observe_apply_paths(root: Path, approved: dict[str, Any], *, tolerant: bool = False) -> list[dict[str, Any]]:
    if tolerant:
        records: dict[str, dict[str, Any]] = {}
        pending = [(root / record["Path"], False) for record in approved["ConsumerSnapshot"]["Paths"]]
        pending.extend((root / relative, True) for relative in (".github/skills", ".specify/scripts", ".specify/extensions", ".specify/integrations", ".specify/skill-library-install"))
        while pending and len(records) < 10000:
            path, recursive = pending.pop()
            relative = path.relative_to(root).as_posix() if path.is_relative_to(root) else str(path)
            if relative in records and not recursive:
                continue
            try:
                record = _path_record(root, path)
                records[relative] = record
                if recursive and record.get("Type") == "directory":
                    children = list(path.iterdir())
                    _require(len(children) + len(pending) < 10000, "Prerequisite", "observation-limit")
                    pending.extend((child, True) for child in children)
            except (ValueError, OSError, TypeError, KeyError) as error:
                records[relative] = {"Path": relative, "Presence": "unknown", "ObservationError": type(error).__name__}
        if pending:
            records["."] = {"Path": ".", "Presence": "unknown", "ObservationError": "ObservationLimit"}
        return list(records.values())
    records = {record["Path"]: _path_record(root, root / record["Path"]) for record in approved["ConsumerSnapshot"]["Paths"]}
    for relative in (".github/skills", ".specify/scripts", ".specify/extensions", ".specify/integrations", ".specify/skill-library-install"):
        for record in _tree(root, root / relative):
            records[record["Path"]] = record
    return list(records.values())


def _validate_reservation(request: dict[str, Any], runtime: dict[str, Any]) -> dict[str, Any]:
    approved = request["ApprovedInputs"]
    root = _safe_path(request["WorkspacePath"])
    operation_id = approved["Fingerprint"]
    _require(approved.get("Contract") == CONTRACT and approved.get("Ready") is True and approved.get("Blockers") == [] and isinstance(operation_id, str) and re.fullmatch(r"[0-9a-f]{64}", operation_id) is not None, "ApprovalMismatch", "approved-inputs")
    extensions = approved["Extensions"]
    index = request.get("StepIndex", 0)
    _require(isinstance(extensions, list) and 1 <= len(extensions) <= 16 and type(index) is int and 0 <= index < len(extensions), "Selection", "ordered-roots")
    _require(len({item["RootId"] for item in extensions}) == len(extensions) and [item["Position"] for item in extensions] == list(range(len(extensions))), "Selection", "ordered-positions")
    _require([item["RootId"] for item in extensions] == [item["Id"] for item in approved["Selection"]["ExtensionRoots"]], "Selection", "ordered-identities")
    projection = copy.deepcopy(approved)
    projection.update(Ready=False, Fingerprint=None)
    for write in projection["IntendedWrites"]:
        write["Path"] = write["Path"].replace(f"/operations/{operation_id}", "/operations/{operation}")
    _require(_digest(_canonical_bytes(projection)) == operation_id, "ApprovalMismatch", "approved-fingerprint")
    _require(str(root) == approved["ConsumerSnapshot"]["WorkspacePath"] and request["RepoRoot"] == approved["Selection"]["SourceRoot"], "ApprovalMismatch", "workspace-identity")
    _require(_canonical_bytes(runtime) == _canonical_bytes(approved["ConsumerSnapshot"]["Runtime"]), "ApprovalMismatch", "runtime-drift")
    for tool in approved["Selection"]["Tools"]:
        _require(_digest(_bytes(Path(tool["Path"]), MAX_ARCHIVE)) == tool["Sha256"], "ApprovalMismatch", "tool-drift")
    operation = _safe_path(request["OperationPath"])
    namespace = root / ".specify/skill-library-install"
    _require(operation == namespace / "operations" / operation_id, "OperationState", "reserved-path")
    owned = request["OwnedFiles"]
    for location, identity in owned.items():
        _require(Path(location).is_relative_to(namespace) and _path_record(root, Path(location)) == _read_json(identity), "Ownership", "reserved-evidence")
    for path in (namespace, namespace / "operations", operation, operation / "scratch"):
        _require(path.is_dir() and stat.S_IMODE(path.stat().st_mode) == 0o700, "OperationState", "reserved-mode")
    _require(not any((operation / "scratch").iterdir()), "OperationState", "reserved-scratch")
    _require(_read_json(_bytes(namespace / "owner.json").decode()) == {"Contract": CONTRACT, "Kind": "operation-namespace"}, "OperationState", "reserved-owner")
    _require(str(namespace / "lock") in owned and str(operation / "operation.json") in owned, "Ownership", "reserved-ledger")
    _require(_read_json(_bytes(namespace / "lock").decode()) == {"Contract": CONTRACT, "OperationId": operation_id}, "OperationState", "reserved-lock")
    receipt = _read_json(_bytes(operation / "operation.json", MAX_ARCHIVE).decode())
    step = request["ExpectedStep"]
    _require(step in ("Prepared", "Attempting", "Verified") and (step != "Prepared" or index == 0) and (step != "Verified" or index > 0) and receipt["LastDurableStep"] == step and receipt["State"] == ("Prepared" if step == "Prepared" else "Running"), "OperationState", "reserved-step")
    _require(receipt["Contract"] == CONTRACT and receipt["OperationId"] == receipt["ReviewedFingerprint"] == operation_id and _canonical_bytes(receipt["ApprovedInputs"]) == _canonical_bytes(approved), "OperationState", "reserved-approval")
    outcomes = [{"RootId": item["RootId"], "State": "Verified" if position < index else "Attempting" if position == index and step == "Attempting" else "Pending"} for position, item in enumerate(extensions)]
    _require(receipt["Extensions"] == outcomes, "OperationState", "reserved-outcome")
    initial = {record["Path"]: record for record in approved["ConsumerSnapshot"]["Paths"]}
    before = {record["Path"]: record for record in receipt["ObservedPaths"]} if index else initial
    allowed = {write["Path"] for write in approved["IntendedWrites"] if write["Path"].startswith(".specify/skill-library-install")}
    observed = _observe_apply_paths(root, approved)
    for record in observed:
        location = record["Path"]
        previous = before.get(location)
        if location in allowed and (initial.get(location) is None or initial[location]["Presence"] == "absent"):
            _require(record.get("Type") != "file" or str(root / location) in owned, "Ownership", "undeclared-evidence")
            continue
        _require(record == previous, "ApprovalMismatch", "reserved-state-drift")
    for location, previous in before.items():
        if location in allowed and (initial.get(location) is None or initial[location]["Presence"] == "absent"):
            continue
        _require(_path_record(root, root / location) == previous, "ApprovalMismatch", "verified-state-drift")
    return {"Paths": observed}


def _verify_installation(root: Path, approved: dict[str, Any], before: list[dict[str, Any]], registry_before: dict[str, Any], index: int = 0) -> list[dict[str, Any]]:
    extension = approved["Extensions"][index]
    observed = _observe_apply_paths(root, approved)
    after = {record["Path"]: record for record in observed}
    original = {record["Path"]: record for record in before}
    writes = {write["Path"]: write for write in approved["IntendedWrites"] if write["Position"] == index and not write["Path"].startswith(".specify/skill-library-install")}
    for location, record in after.items():
        previous = original.get(location)
        if location not in writes or previous and previous.get("Type") == "directory":
            _require(record == previous, "VerificationFailure", "unrelated-state")
            continue
        write = writes[location]
        if write["Effect"] == "create-parent-if-absent":
            _require(record.get("Type") == "directory" and record["Mode"] == ("0700" if write["Mode"] == "0700" else "0755"), "VerificationFailure", "installed-parent")
        elif write["Effect"] in ("create-payload", "create-command"):
            _require(record.get("Type") == "file" and record["Mode"] == write["Mode"][-3:].rjust(4, "0") and record["Sha256"] == write["Sha256"], "VerificationFailure", "installed-content")
        else:
            _require(record.get("Type") == "file" and record["Mode"] == (previous["Mode"] if previous and previous["Presence"] == "present" else "0644"), "VerificationFailure", "installed-registration-mode")
            if previous and previous["Presence"] == "present":
                _require(all(record[key] == previous[key] for key in ("Device", "Inode")), "VerificationFailure", "registration-identity")
    for location in writes:
        _require(location in after and after[location]["Presence"] == "present", "VerificationFailure", "missing-installed-path")
    for member in extension["Members"]:
        location = f".specify/extensions/{extension['RootId']}/{member['MemberPath']}"
        _require(after[location]["Size"] == member["Size"], "VerificationFailure", "installed-size")
    command = after[extension["Command"]["Path"]]
    _require(command["Size"] == extension["Command"]["Size"], "VerificationFailure", "installed-command")
    registry = _read_json(_bytes(root / ".specify/extensions/.registry").decode())
    addition = registry["extensions"][extension["RootId"]]
    timestamp = addition.get("installed_at")
    _require(isinstance(timestamp, str) and timestamp.endswith("+00:00") and datetime.fromisoformat(timestamp).utcoffset() == timezone.utc.utcoffset(None), "VerificationFailure", "installed-timestamp")
    expected_addition = dict(extension["RegistryAddition"], installed_at=timestamp)
    expected_registry = copy.deepcopy(registry_before)
    expected_registry["extensions"][extension["RootId"]] = expected_addition
    _require(registry == expected_registry and _bytes(root / ".specify/extensions/.registry") == json.dumps(expected_registry, indent=2).encode(), "VerificationFailure", "installed-registry")
    prediction = approved["ConsumerSnapshot"]["ConfigurationPredictions"][index]
    configuration = after[prediction["Path"]]
    _require(configuration["Size"] == prediction["Size"] and configuration["Sha256"] == prediction["Sha256"], "VerificationFailure", "installed-configuration")
    return observed


class _DiagnosticSink:
    """Discard untrusted diagnostic content without retaining an unbounded buffer."""

    def __init__(self) -> None:
        self.seen = False

    def write(self, text: str) -> int:
        self.seen = self.seen or bool(text.strip())
        return len(text)

    def flush(self) -> None:
        return None


def _apply_archive(request: dict[str, Any]) -> dict[str, Any]:
    """Translate runtime exceptions at the process boundary into preserved uncertain outcomes."""
    root = _safe_path(request["WorkspacePath"])
    approved = request["ApprovedInputs"]
    called = False
    stage = "revalidation"
    diagnostics = _DiagnosticSink()
    observed: list[dict[str, Any]] = []
    try:
        with contextlib.redirect_stdout(diagnostics), contextlib.redirect_stderr(diagnostics), warnings.catch_warnings():
            warnings.simplefilter("error")
            runtime = _inspect_runtime()
            before = _validate_reservation(request, runtime)["Paths"]
            _require(request["ExpectedStep"] == "Attempting", "OperationState", "missing-intent")
            scratch = _safe_path(str(Path(request["OperationPath"]) / "scratch"))
            _require(os.environ.get("TMPDIR") == str(scratch) and Path(tempfile.gettempdir()) == scratch and sys.flags.isolated == 1 and sys.dont_write_bytecode, "Prerequisite", "child-environment")
            index = request.get("StepIndex", 0)
            extension = approved["Extensions"][index]
            inventory = approved["Selection"]["RequiredInventories"][index]
            selected_root = approved["Selection"]["ExtensionRoots"][index]
            selection = {"Root": {key: selected_root[key] for key in ("Id", "Version", "Folder")}, "SourceCommit": approved["Selection"]["SourceCommit"], "Inventory": inventory["Inventory"], "Payload": inventory["Payload"]}
            catalog = _catalog({"Root": selection["Root"], "CatalogPath": [origin["Path"] for origin in extension["CatalogOrigins"]]})
            _require(_canonical_bytes(catalog["CatalogOrigins"]) == _canonical_bytes(extension["CatalogOrigins"]), "ApprovalMismatch", "catalog-drift")
            path = _safe_path(extension["Archive"]["Path"])
            with path.open("rb") as stream:
                verified = _verify_artifact({"Selection": selection, "Catalog": catalog["Record"], "ArchivePath": str(path), "ExpectedLoader": request["ExpectedLoader"]}, stream)
                expected = {key: value for key, value in extension.items() if key not in ("CatalogOrigins", "ArtifactOrigins")}
                verified["Position"] = index
                _require(_canonical_bytes(verified) == _canonical_bytes(expected), "ApprovalMismatch", "artifact-drift")
                registry_path = root / ".specify/extensions/.registry"
                registry_before = _read_json(_bytes(registry_path).decode()) if registry_path.exists() else {"schema_version": "1.0", "extensions": {}}
                from specify_cli.extensions import ExtensionManager

                stream.seek(0)
                stage = "delegation"
                called = True
                manifest = ExtensionManager(root).install_from_archive(path, "1.2.3", priority=10, force=False, archive_file=stream, expected_id=extension["RootId"], expected_version=extension["Version"])
                stage = "verification"
                _require(manifest.id == extension["RootId"] and manifest.version == extension["Version"] and manifest.warnings == [] and not diagnostics.seen, "VerificationFailure", "runtime-outcome")
                stream.seek(0)
                _require(_digest(stream.read(MAX_ARCHIVE + 1)) == extension["Archive"]["Sha256"], "VerificationFailure", "archive-changed-during-install")
                observed = _verify_installation(root, approved, before, registry_before, index)
                _require(not any(scratch.iterdir()), "VerificationFailure", "retained-runtime-scratch")
        return {"Outcome": "Verified", "Called": called, "Cancelled": False, "Stage": stage, "ObservedPaths": observed, "Blockers": [], "Diagnostics": []}
    except (Exception, KeyboardInterrupt) as error:
        try:
            observed = _observe_apply_paths(root, approved, tolerant=True)
        except (ValueError, OSError, TypeError, KeyError):
            observed = []
        return {
            "Outcome": "Failed" if isinstance(error, _InspectionError) else "Unknown", "Called": called, "Cancelled": isinstance(error, KeyboardInterrupt), "Stage": stage, "ObservedPaths": observed,
            "Blockers": [{"Code": error.code if isinstance(error, _InspectionError) else "RuntimeFailure", "Scope": stage, "Explanation": "Installation was not verified; preserve all operation and runtime paths for inspection.", "Observed": type(error).__name__, "Expected": None}],
            "Diagnostics": ["Upstream diagnostics were suppressed; inspect retained operation evidence."] if diagnostics.seen else [],
        }


def _dispatch(request: dict[str, Any]) -> dict[str, Any]:
    if request.get("Contract") != CONTRACT or request.get("Mode", "inspect") not in ("inspect", "apply"):
        raise _InspectionError("Prerequisite", "protocol")
    action = request.get("Action", "probe")
    if request.get("Mode") == "apply":
        _require(action == "install-root", "Prerequisite", "protocol-action")
        return _apply_archive(request)
    if action == "validate-reservation":
        return _validate_reservation(request, _inspect_runtime())
    if action == "observe-failure":
        root = _safe_path(request["WorkspacePath"])
        return {"Paths": _observe_apply_paths(root, request["ApprovedInputs"], tolerant=True)}
    if action == "evidence-identity":
        root = _safe_path(request["WorkspacePath"])
        path = _safe_path(request["Path"])
        _require(path.is_relative_to(root / ".specify/skill-library-install"), "Ownership", "evidence-path")
        return _path_record(root, path)
    if action == "fingerprint":
        projection = _canonical_bytes(request["Projection"])
        _require(len(projection) <= MAX_STATE, "Prerequisite", "approval-size")
        return {"Fingerprint": _digest(projection)}
    if action == "catalog":
        try:
            return _catalog(request)
        except (ValueError, OSError, TypeError, KeyError) as error:
            raise _InspectionError("Catalog", "local-catalog") from error
    if action == "verify":
        try:
            return _verify_artifact(request)
        except (ValueError, OSError, TypeError, KeyError, zipfile.BadZipFile, StopIteration, IndexError) as error:
            raise _InspectionError("Artifact", "selected-archive") from error
    _require(action == "probe", "Prerequisite", "protocol-action")
    runtime = _inspect_runtime()
    snapshot = _inspect_workspace(request, runtime)
    return {"ConsumerSnapshot": snapshot}


def main() -> int:
    """Emit one structured response, with sanitized apply outcomes separate from diagnostics."""
    try:
        text = sys.stdin.read(8 * 1024 * 1024 + 1)
        _require(len(text) <= 8 * 1024 * 1024, "Prerequisite", "request-size")
        request = _read_json(text)
        if not isinstance(request, dict):
            raise _InspectionError("Prerequisite", "protocol")
        result = _dispatch(request)
        response = {"Contract": CONTRACT, "Stage": "inspection", "Status": "Inspected", "Result": result, "Blockers": []}
        code = 0
        if request.get("Mode") == "apply":
            response.update(Stage=result["Stage"], Status="Applied" if result["Outcome"] == "Verified" else "Failed", Blockers=result["Blockers"])
            code = 0 if result["Outcome"] == "Verified" else 3
    except (ValueError, OSError, TypeError, KeyError, ImportError) as error:
        response = {
            "Contract": CONTRACT,
            "Stage": "inspection",
            "Status": "Blocked",
            "Result": None,
            "Blockers": [{"Code": error.code if isinstance(error, _InspectionError) else "Prerequisite", "Scope": error.scope if isinstance(error, _InspectionError) else "inspection", "Explanation": "Restore supported, unambiguous readable local inputs.", "Observed": type(error).__name__, "Expected": None}],
        }
        code = 2
    sys.stdout.write(json.dumps(response, ensure_ascii=False, separators=(",", ":")) + "\n")
    return code


if __name__ == "__main__":
    sys.exit(main())
